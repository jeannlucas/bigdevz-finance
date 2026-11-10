# Especificação Permanente da Capability Financeira (Financeiro)

> **Capability:** `financeiro`<br>
> **Status:** Ativo / Canônico<br>
> **Referência de Governança:** `~/AGENTS.md` (item 15.1), `docs/project-guidelines.md`, ADRs `0001` a `0006`.<br>
> **Regra de Ouro:** O código e os testes respondem a esta especificação; qualquer divergência (*drift*) é considerada defeito de primeira classe.

---

## 1. Visão Geral da Capability

A capability **Financeiro** é o núcleo de integridade patrimonial do BigDev.Z Finance, cobrindo gestão de contas, conciliação contábil, recebíveis (acordos e parcelas), compromissos a pagar (avulsos, parcelados, recorrentes e faturas de cartão), movimentações financeiras, estornos e idempotência transacional.

---

## 2. Critérios de Aceite Numerados (AC-FIN)

### 2.1. Integridade Monetária e Proibição de Ponto Flutuante

- **AC-FIN-001 [Proibição Estrita de Float/Double Financeiro]:** É expressamente proibido o uso de tipos de ponto flutuante (`float`, `double`, `real`) para manipulação, armazenamento ou cálculo de valores monetários tanto no backend PHP quanto no frontend Flutter/Dart. O tipo `double` no Flutter é permitido estrita e exclusivamente para tokens visuais e propriedades de layout/renderização gráfica (ex.: `padding`, `fontSize`, `opacity`, `width`, `height`), jamais para dinheiro.
- **AC-FIN-002 [Centavos Inteiros no Núcleo e Persistência]:** Todos os valores monetários são processados no domínio e armazenados no banco de dados PostgreSQL como inteiros de 64 bits (`int` em PHP/Dart e colunas `BIGINT` com `CHECK` no PostgreSQL) representando centavos da menor unidade da moeda (ex.: R$ 1.250,50 = `125050` centavos).
- **AC-FIN-003 [Formato Canônico Decimal em Contratos de API]:** Em endpoints REST e serializações JSON, os valores monetários transitam exclusivamente como strings decimais canônicas com ponto separador e exatamente duas casas decimais (ex.: `"2000.00"`, `"1250.50"`). Formatos numéricos puros, com vírgula ou mais de duas casas devem ser rejeitados com `422 Unprocessable Entity`.
- **AC-FIN-004 [Limites Máximos Individuais vs. Totais Agregados]:**
  - **Limite Individual (`Money::MAX_CENTS`):** O valor monetário unitário máximo suportado por cada conta, movimentação, pagamento, recebimento, obrigação ou acordo individual é `999999999999.99` (representado por `99999999999999` centavos = R$ 999 bilhões), protegido por restrições `CHECK` no banco de dados e validações de domínio.
  - **Totais Agregados Exatos:** Agregações de múltiplas entidades (saldo consolidado do espaço no Dashboard, totalizador de compromissos abertos/vencidos, prévias de recorrências de múltiplos ciclos) podem ultrapassar o limite unitário de R$ 999 bilhões, sendo processados e formatados via `Money::formatAggregate(int|string $cents)` e lidos no Flutter até o teto de inteiros de 64 bits (`PHP_INT_MAX` / Dart int64 = ~92 quadrilhões de reais), sem truncamento, sem float e sem estouro de exceção.
  - Valores informados em formulários e cadastros são obrigatoriamente positivos (`> 0` ou `>= 0` para saldo de abertura).
  - Saldos de contas podem tornar-se negativos exclusivamente após pagamentos efetivados superiores ao disponível, representados com sinal negativo (ex.: `"-250.00"`).

---

### 2.2. Divisão Determinística e Cronogramas de Vencimento

- **AC-FIN-005 [Distribuição Determinística de Centavos Restantes]:** Ao dividir um total em $N$ parcelas (de 1 a 1.200 parcelas), quando houver resto na divisão inteira de centavos, cada centavo restante deve ser alocado obrigatoriamente às primeiras parcelas em ordem crescente (ex.: R$ 100,00 em 3 parcelas gera parcelas de R$ 33,34, R$ 33,33 e R$ 33,33). A soma das parcelas deve ser matematicamente idêntica ao total contratado.
- **AC-FIN-006 [Preservação do Dia de Referência de Vencimento]:**
  - O dia da primeira parcela define o dia de referência fixo para todas as parcelas subsequentes.
  - Em meses cujo total de dias for menor que o dia de referência (ex.: dia 31 em fevereiro com 28/29 dias ou abril com 30 dias), o vencimento deve cair no último dia do mês correspondente.
  - Nos meses posteriores com duração suficiente, o dia de referência original deve ser restaurado (ex.: 31/01 -> 28/02 -> 31/03). Anos bissextos devem considerar 29 de fevereiro.
  - Vencimentos não são antecipados nem postergados por feriados ou finais de semana no cronograma contratual.

---

### 2.3. Juros, Multas e Conciliação Contábil

- **AC-FIN-007 [Juros e Multas — ESPECIFICADO MAS NÃO IMPLEMENTADO (ROADMAP FUTURO)]:**
  - O cálculo automático e a cobrança de juros de mora ou multas contratuais sobre parcelas e obrigações vencidas estão formalmente mapeados nos requisitos do produto, porém **não implementados no motor financeiro atual**.
  - O sistema opera estritamente sob valor facial/líquido exato. Quando implementada em checkpoint futuro, qualquer adição de acréscimos deverá ser realizada em centavos inteiros determinísticos, sem frações de centavos e sem ponto flutuante.
- **AC-FIN-008 [Marco Temporal de Abertura de Conta e Conciliação]:**
  - Toda conta bancária possui uma data e saldo inicial de abertura auditáveis (`opening_balance_date`, `opening_balance_cents`).
  - É proibido registrar qualquer lançamento, recebimento ou pagamento com data de liquidação anterior à data do saldo inicial da conta bancária (`paid_on < opening_balance_date` ou `received_on < opening_balance_date`), retornando erro de validação `422`.
- **AC-FIN-009 [Imutabilidade do Histórico Contábil Efetivado]:**
  - Lançamentos financeiros liquidados (`AccountMovement`, `Receipt`, `Payment`) são imutáveis e jamais sofrem exclusão física (`DELETE`).
  - Correções de saldo ou destino exigem registro de estorno com contra-movimentação de sinal algébrico inverso na data original do lançamento, acompanhado do lançamento substituto na nova data/conta quando aplicável, preservando trilha de auditoria completa com justificativa.

---

### 2.4. Isolamento Multi-Tenant e Prevenção de IDOR/BOLA

- **AC-FIN-010 [Escopo por Espaço (Space) Autenticado]:**
  - O multi-tenant no BigDev.Z Finance é estruturado em torno da entidade `Space` (`space_id`), segregando estritamente finanças pessoais (`PF`) e empresariais (`PJ`).
  - Toda rota protegida da API pertence a um espaço e injeta o `space_id` autenticado resolvido exclusivamente via relação do usuário autenticado: `$request->user()->spaces()->findOrFail($spaceId)`.
- **AC-FIN-011 [Prevenção Ativa de IDOR / BOLA]:**
  - Nenhuma requisição pode consultar, criar, atualizar ou excluir recursos fora dos espaços pertencentes ao usuário autenticado.
  - Tentativas de manipular identificadores (`space_id`, `account_id`, `payable_id`, `installment_id`, `receipt_id`, etc.) para alcançar recursos de terceiros ou de outro espaço do próprio usuário devem responder imediatamente com `404 Not Found` (sem expor se o recurso existe) ou `422 Unprocessable Entity` quando houver conflito de validação de espaço.
- **AC-FIN-012 [Restrições Compostas de Banco de Dados `(id, space_id)`]:**
  - Chaves estrangeiras compostas no PostgreSQL `FOREIGN KEY (item_id, space_id)` garantem que recebimentos, pagamentos, contas e parcelas pertençam invariavelmente ao mesmo espaço, constituindo uma barreira de integridade intransponível mesmo se houver regressão no nível de aplicação.

---

### 2.5. Saldo Disponível vs. Compromissos Previstos

- **AC-FIN-013 [Composição Exclusiva do Saldo Disponível]:**
  - O saldo disponível de uma conta é unicamente a soma algébrica de seu saldo inicial com suas movimentações efetivamente liquidadas (`AccountMovement`).
  - Contas a pagar em aberto, parcelas vincendas, faturas futuras e recorrências programadas representam projeção de fluxo de caixa e **jamais alteram o saldo disponível** da conta bancária até que haja pagamento efetivo registrado.
- **AC-FIN-014 [Preservação de Saldo em Contas Arquivadas]:**
  - Arquivar uma conta não apaga seu saldo nem redistribui valores; o saldo da conta arquivada permanece computado no saldo total consolidado do espaço, mas a conta fica indisponível para novos lançamentos.

---

### 2.6. Idempotência e Concorrência Transacional

- **AC-FIN-015 [Chave de Idempotência Obrigatória e Replay Determinístico]:**
  - Mutações financeiras críticas que movimentam patrimônio (recebimentos, pagamentos, estornos de recebimento, estornos de pagamento, correções de recebimento, correções de pagamento, ajustes de abertura de conta e criação de obrigações/recorrências) exigem o cabeçalho `Idempotency-Key`.
  - **Unicidade e Lock:** A chave de idempotência possui restrição de unicidade por espaço (`space_id, key`) na tabela `idempotency_keys`. Requisições concorrentes com a mesma chave são serializadas por lock consultivo transacional no PostgreSQL (`pg_advisory_xact_lock("idempotency:{space_id}:{key}")`). O identificador do usuário (`user_id`) é persistido para trilha de auditoria.
  - **Impressão Digital (Fingerprint):** O payload gera uma impressão digital SHA-256 (`operation|target|json_encode(fields)`).
  - **Replay de Sucesso:** Quando a chave já foi concluída com sucesso (`status = 'completed'`), a requisição devolve o resultado serializando o estado atual dos modelos vinculados com status `200 OK`, `replayed: true` e metadados de idempotência (primeira execução com sucesso responde `201 Created` para criações e `200 OK` para outras mutações).
  - **Replay de Rejeição de Validação e Negócio:** Quando uma mutação financeira portando `Idempotency-Key` válido falha na validação dos campos do request (ex.: payload sintaticamente inválido, tipos ou campos obrigatórios ausentes) ou é rejeitada por regra de negócio durante o processamento do caso de uso (ex.: limite de saldo ultrapassado, conta arquivada, data anterior à abertura, obrigação cancelada, valor excedente), a transação interna do trabalho sofre rollback via savepoint e a chave é gravada no banco com `status = 'rejected'` e a lista de erros; reenvios da mesma chave com o mesmo payload retornam a resposta de erro `422 Unprocessable Entity` com `idempotency.status = 'rejected'` e `idempotency.replayed = true`. Reenvio da mesma chave com payload corrigido ou alterado gera `409 Conflict` devido à divergência de fingerprint. Requisições que falham por ausência completa ou malformação do próprio cabeçalho `Idempotency-Key` são rejeitadas sem consumo nem persistência de chave.
  - **Conflito de Idempotência:** Reenvio de uma chave já decidida com operação ou fingerprint divergente é rejeitado imediatamente com status `409 Conflict`.
  - **Mutações sem Idempotência no Backend:** O cadastro e a edição simples de contas bancárias e a criação de acordos avulsos não consomem `Idempotency-Key` no backend e dependem atualmente de debounce de clique no frontend mobile; o debounce do cliente não constitui garantia de idempotência no backend sob falhas de rede.
- **AC-FIN-016 [Proteção Pessimista contra Condição de Corrida]:**
  - Operações concorrentes de pagamento ou recebimento devem utilizar locks pessimistas (`lockForUpdate`) seguindo a ordem canônica determinística:
    1. Lock na chave de idempotência;
    2. Lock no documento / obrigação / parcela;
    3. Lock nas contas bancárias envolvidas ordenadas por `id` crescente.
  - A soma dos recebimentos ou pagamentos concorrentes jamais pode exceder o valor restante devido, garantido pela restrição `CHECK` no banco de dados.

---

### 2.7. Edição e Cancelamento de Lançamentos em Aberto

- **AC-FIN-017 [Edição e Cancelamento Seguro de Obrigações e Acordos]:**
  - **Obrigações e Acordos sem Liquidação (Valor Pago/Recebido Zero):**
    - Podem ser cancelados a qualquer momento pelo usuário mediante fornecimento de justificativa obrigatória (`cancel_reason`).
    - Uma vez cancelados, deixam de ser listados em filtros de pendências abertas/vencidas e não alteram fluxo de caixa projetado nem saldos disponíveis.
    - É estritamente proibido cancelar obrigações ou acordos que possuam pagamentos ou recebimentos ativos (`paid_cents > 0` ou `received_cents > 0`). Caso haja liquidação ativa, exige-se o estorno contábil prévio de todas as liquidações antes do cancelamento.
  - **Edição de Dados Cadastrais:**
    - Antes da liquidação, é permitida a edição de dados descritivos (`description`, `category_id`, `payee` e datas de vencimento).
    - Obrigações ou acordos cancelados são imutáveis e não aceitam edições nem liquidações.

---

### 2.5. Segurança Operacional, RBAC e Integridade de Fechamento

- **AC-FIN-018 [Controle de Acesso Baseado em Papéis — RBAC Real por Espaço PJ]:**
  - Espaços empresariais (PJ) suportam perfis dedicados: `administrador`, `financeiro`, `operador` e `contador`.
  - No espaço pessoal (PF), o usuário autenticado opera nativamente como administrador.
  - O perfil `operador` pode cadastrar lançamentos e baixas rotineiras, mas é estritamente bloqueado (HTTP 403) de: cancelar acordos/obrigações, estornar pagamentos/recebimentos, exportar dados e alterar saldos iniciais de contas.
  - O perfil `contador` possui acesso exclusivamente de consulta e exportação, sendo estritamente impedido (HTTP 403) de realizar mutações financeiras (criação, edição, baixas, estornos e transferências).
  - O perfil `administrador` possui autoridade total, incluindo gestão de membros (`/members`), fechamento e reabertura contábil.
  - As permissões são aplicadas por espaço, garantindo isolamento total sem vazamento entre organizações.

- **AC-FIN-019 [Período Contábil Fechado e Bloqueio de Mutações Retroativas]:**
  - O sistema permite definir uma data limite de fechamento contábil por espaço (`spaces.closed_until`).
  - Nenhuma operação financeira (criação, edição, pagamento, baixa, estorno ou cancelamento) pode ser gravada ou alterada com data contábil menor ou igual à data de fechamento (`<= closed_until`), retornando erro de validação HTTP 422.
  - Apenas administradores do espaço podem fechar ou reabrir o período contábil.
  - A reabertura exige obrigatoriamente justificativa detalhada (mínimo de 5 caracteres), registrada permanentemente na trilha de auditoria (`space_closing_logs` e `obligation_changes`).

- **AC-FIN-020 [Auditoria Imutável para o Gestor e Rastreabilidade Integral]:**
  - Todas as mutações críticas (estornos, cancelamentos, alterações de valores monetários e reaberturas de período) são registradas de forma indelével na tabela de auditoria.
  - Registros de auditoria são estritamente imutáveis (tentativas de `UPDATE` ou `DELETE` são rejeitadas com exceção em nível de domínio e banco).
  - O endpoint `GET /spaces/{space}/audit` disponibiliza histórico cronológico completo contendo autor, data/hora, ação, diff estruturado (`before` vs. `after`) e sinalizador de criticidade (`is_critical`).

---

### 2.6. Operações Financeiras Avançadas, Planejamento e Conciliação (P1 Interno)

- **AC-FIN-021 [Baixas Parciais com Auditoria e Saldo Residual Exato]:**
  - O sistema permite o pagamento ou recebimento parcial de obrigações (`Payable`) e parcelas (`Installment`).
  - Cada baixa parcial calcula e mantém o saldo residual exato em centavos inteiros (`amount_cents - paid_cents` / `amount_cents - received_cents`).
  - O status evolui dinamicamente para 'Parcialmente pago' / 'Parcialmente recebido' (badge 'Parcial' em layouts compactos) enquanto houver saldo devedor/credor pendente.
  - Cada evento de baixa ou estorno parcial gera um registro indelével em `obligation_changes` contendo o valor amortizado, saldo anterior e saldo restante.
  - É proibido registrar baixa cujo valor somado aos pagamentos/recebimentos anteriores ultrapasse o valor facial total da obrigação/parcela, retornando HTTP 422.
  - Cada baixa parcial pode ser estornada de forma atômica e independente sem afetar as demais amortizações prévias, restaurando o saldo restante na proporção exata daquela baixa.
  - Baixas e estornos respeitam integralmente os bloqueios de RBAC e período contábil fechado (`closed_until`).

- **AC-FIN-022 [Fluxo de Caixa Realizado vs. Previsto e Planejamento Financeiro]:**
  - O módulo de planejamento disponibiliza projeção de fluxo de caixa em janelas pré-configuradas de 30, 60 e 90 dias a partir da data de referência.
  - Suporta segregação entre visão de Caixa (`cash` - baseado nas datas de liquidação/vencimento efetivas) e Competência (`accrual` - baseado nas datas de emissão/competência contábil).
  - O saldo inicial projetado é composto exclusivamente pelo saldo real consolidado das contas bancárias ativas no espaço no início do horizonte.
  - Cada dia da projeção agrega entradas realizadas, entradas previstas, saídas realizadas, saídas previstas e saldo final acumulado dia a dia sem descontinuidade matemática.
  - Filtros granulares permitem consultar por espaço (PF/PJ), conta bancária específica e categoria orçamentária.
  - O sistema suporta estados visuais de carregamento, vazio (sem movimentações no horizonte) e erro de rede.
  - A exportação dos dados projetados (ex.: CSV estruturado) é protegida por permissão (`export_data`), bloqueando operadores rotineiros com HTTP 403.

- **AC-FIN-023 [Conciliação Bancária OFX com Deduplicação e Confirmação Humana]:**
  - Importação de arquivos de extrato bancário no padrão OFX (suporte a tags abertas e fechadas em SGML 1.02 e XML 2.0) sem consumo de bibliotecas ou dependências externas não homologadas.
  - Prévia estruturada dos lançamentos antes de qualquer persistência contábil, exibindo data, descrição, valor (crédito/débito) e identificador único (`FITID`).
  - Algoritmo de sugestão automática de correspondência (*fuzzy match*) por valor monetário exato e proximidade de data de vencimento (+/- 7 dias) contra contas a pagar em aberto e parcelas de recebíveis ativas.
  - Deduplicação rigorosa baseada em chave única composta `(space_id, account_id, fitid)` na tabela `reconciled_transactions`. Transações já conciliadas no espaço são sinalizadas com badge e bloqueadas para duplicação.
  - Confirmação humana obrigatória para conclusão da conciliação: cada item pode ser confirmado como liquidação de obrigação existente, recebimento de acordo ou lançamento de movimentação avulsa.
  - Zero conexões automáticas ou chamadas a APIs de Open Finance nesta fase (operação estritamente local/manual via upload ou colagem de conteúdo).

---

## 3. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério | Implementação Backend / Mobile | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-FIN-001** | `Money.php`, `money.dart`, migrations `BIGINT` | `apps/api/tests/domain.php`, `money_test.dart` |
| **AC-FIN-002** | `Money::toCents`, `Money.parse`, colunas `_cents` | `apps/api/tests/domain.php`, `ReceivablesFlowTest.php` |
| **AC-FIN-003** | `MoneyAmount.php`, `Money::fromCents`, API REST | `apps/api/tests/domain.php`, `PayablesTest.php` |
| **AC-FIN-004** | `Money::MAX_CENTS`, `Money.isNegative`, checks SQL | `apps/api/tests/domain.php`, `PayableCreationRecoveryTest.php` |
| **AC-FIN-005** | `InstallmentSchedule.php`, `CreatePayable::schedule` | `apps/api/tests/domain.php`, `PayablesTest.php` |
| **AC-FIN-006** | `MonthlyDate.php`, `InstallmentSchedule::generate` | `apps/api/tests/domain.php` |
| **AC-FIN-007** | Não implementado (Planejado para checkpoint futuro) | N/A (Regra ausente; opera por valor facial) |
| **AC-FIN-008** | `PayPayable::validateTarget`, `ReceiveInstallment::handle` | `ReceivablesFlowTest.php`, `PayablesTest.php` |
| **AC-FIN-009** | `ReverseReceipt.php`, `ReversePayment.php`, `AccountMovement` | `ReceiptReversalTest.php`, `PayablesTest.php` |
| **AC-FIN-010** | `Controller::space`, `SpaceController.php`, `routes/api.php` | `IsolationAndAtomicityTest.php` |
| **AC-FIN-011** | Injeção de `space_id` em todos os controllers e actions | `IsolationAndAtomicityTest.php` |
| **AC-FIN-012** | Foreign keys compostas `(id, space_id)` em todas as tabelas | `IsolationAndAtomicityTest.php`, migrations |
| **AC-FIN-013** | `SpaceController::summary`, `Account::balanceCents` | `summary_test.dart`, `IsolationAndAtomicityTest.php` |
| **AC-FIN-014** | `ArchiveAccount.php`, `AccountController::archive` | `AccountManagementTest.php`, `accounts_test.dart` |
| **AC-FIN-015** | `IdempotentOperations.php`, `HandlesIdempotency.php` | `ConcurrentReceiptsTest.php`, `ConcurrentPaymentsTest.php` |
| **AC-FIN-016** | `lockForUpdate` ordenado, locks advisory Postgres | `ConcurrentReceiptsTest.php`, `ConcurrentPaymentsTest.php` |
| **AC-FIN-017** | `ChangeObligations.php`, `ChangeAgreements.php`, Modais Web/Mobile | `PayablesTest.php`, `AgreementCancellationAndEditTest.php`, `agreement_cancel_and_edit_test.dart` |
| **AC-FIN-018** | `Space::ensureCan`, `space_users`, `SpaceMemberController`, `SpaceMembersScreen` | `RbacSecurityTest.php`, `auth_models_test.dart`, `space_members_screen_test.dart`, `space_members_repository_test.dart` |
| **AC-FIN-019** | `Space::ensureDateNotClosed`, `AccountingPeriodController`, `space_closing_logs`, `AccountingPeriodDialog` | `AccountingPeriodClosingTest.php` |
| **AC-FIN-020** | `ObligationChange`, `AuditController`, `RecordsChanges`, `AuditScreen` | `AuditTrailTest.php`, `audit_screen_test.dart`, `audit_repository_test.dart` |
| **AC-FIN-021** | `PayPayable.php`, `ReceiveInstallment.php`, `ReversePayment.php`, `ReverseReceipt.php`, `agreement_modal.dart`, `payable_modal.dart` | `PartialPaymentsAndReceiptsAuditTest.php`, `agreement_modal_test.dart`, `payable_modal_edit_test.dart` |
| **AC-FIN-022** | `CashFlowController.php`, `planning_models.dart`, `planning_repository.dart`, `PlanningScreen.dart` | `CashFlowPlanningTest.php`, `planning_screen_test.dart`, `planning_repository_test.dart` |
| **AC-FIN-023** | `OfxParserService.php`, `OfxReconciliationController.php`, `ReconciledTransaction.php`, `ofx_screen.dart`, `ofx_repository.dart` | `OfxReconciliationTest.php`, `ofx_screen_test.dart`, `ofx_repository_test.dart` |
