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
  - **Valores Permitidos na Abertura e Correção de Contas:** No cadastro inicial e na correção auditada de abertura de conta bancária, são permitidos valores positivos, zero e negativos (ex.: cheque especial utilizado antes do início do controle ou saldo inicial devedor), respeitando o intervalo $-999.999.999.999,99 \le \text{saldo inicial} \le 999.999.999.999,99$ (em centavos de 64 bits de $-99999999999999$ a $99999999999999$), refletindo exatamente no saldo disponível da conta bancária. Demais valores informados em pagamentos e recebimentos são obrigatoriamente positivos ($> 0$).
  - Saldos de contas podem tornar-se negativos tanto por saldo de abertura negativo quanto após pagamentos efetivados superiores ao disponível, representados com sinal negativo (ex.: `"-250.00"`, `"-995.98"`).

---

### 2.2. Divisão Determinística e Cronogramas de Vencimento

- **AC-FIN-005 [Distribuição Determinística de Centavos Restantes]:** Ao dividir um total em $N$ parcelas (de 1 a 1.200 parcelas), quando houver resto na divisão inteira de centavos, cada centavo restante deve ser alocado obrigatoriamente às primeiras parcelas em ordem crescente (ex.: R$ 100,00 em 3 parcelas gera parcelas de R$ 33,34, R$ 33,33 e R$ 33,33). A soma das parcelas deve ser matematicamente idêntica ao total contratado.
- **AC-FIN-006 [Preservação do Dia de Referência de Vencimento]:**
  - O dia da primeira parcela define o dia de referência fixo para todas as parcelas subsequentes.
  - Em meses cujo total de dias for menor que o dia de referência (ex.: dia 31 em fevereiro com 28/29 dias ou abril com 30 dias), o vencimento deve cair no último dia do mês correspondente.
  - Nos meses posteriores com duração suficiente, o dia de referência original deve ser restaurado (ex.: 31/01 -> 28/02 -> 31/03). Anos bissextos devem considerar 29 de fevereiro.
  - O cronograma contratual usa datas civis. A prévia de novos carnês pode sugerir ajustes opcionais conforme AC-FIN-033.

---

### 2.3. Juros, Multas, Descontos e Liquidação Contábil

- **AC-FIN-007 [Composição de Pagamento com Encargos e Descontos]:**
  - O sistema suporta liquidação de contas a pagar com discriminação de valor principal, juros de mora (`interest`), multas (`fine`) e descontos (`discount`).
  - Fórmula Canônica: $\text{Total Debitado} = \text{Principal} + \text{Juros} + \text{Multa} - \text{Desconto}$.
  - O saldo devido da obrigação (`paid_cents`) é amortizado unicamente pelo valor principal contratual.
  - A movimentação bancária na conta de origem (`account_movements.amount_cents`) debita exatamente o total líquido efetivamente pago.
  - Toda aritmética é conduzida estritamente em centavos inteiros de 64 bits, sem frações de centavos e com proibição absoluta de ponto flutuante (`float`/`double`).
  - Todos os componentes são persistidos no pagamento (`principal_cents`, `interest_cents`, `fine_cents`, `discount_cents`, `total_cents`) e auditados indelevelmente.
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

### 2.7. Suíte Especializada de Contas a Pagar (Reversão, Categoria e Encargos)

#### 2.7.1. Estorno e Correção de Pagamento de Contas a Pagar (AC-PAY-REV)
- **AC-PAY-REV-001 [Histórico Visível de Pagamentos]:** Ao abrir uma conta a pagar no Web Desktop ou Mobile que possua liquidação parcial ou total (`paid_cents > 0`), a interface exibe a seção "Histórico de pagamentos" contendo para cada pagamento: valor formatado em BRL, data de liquidação, conta bancária debitada, situação (ativo, estornado ou substituto) e decomposição financeira.
- **AC-PAY-REV-002 [Ações de Estorno e Correção Acessíveis]:** Cada pagamento ativo exibe as ações "Estornar" e "Corrigir" tanto na Web quanto no Mobile, respeitando as permissões do usuário no espaço (perfis `operador` e `contador` bloqueados).
- **AC-PAY-REV-003 [Justificativa Obrigatória]:** A ação de estorno exige fornecimento de motivo obrigatório com no mínimo 3 caracteres e no máximo 500 caracteres, persistido permanentemente em `payment_reversals` e `obligation_changes`.
- **AC-PAY-REV-004 [Recomposição Exata do Saldo e Status]:** O estorno credita na conta bancária original o exato valor debitado no pagamento e decrementa o saldo amortizado da obrigação pelo principal, reabrindo a conta a pagar para o status correspondente ("Aberto" ou "Parcial") sem recarregar a aplicação.
- **AC-PAY-REV-005 [Proteção contra Duplicidade, Replay e Locks]:** É estritamente proibido estornar um pagamento já estornado (retornando HTTP 422). Replays idempotentes retornam o estado atualizado com HTTP 200 e `replayed: true`. Operações concorrentes são serializadas por lock na chave e lock pessimista ordenado.
- **AC-PAY-REV-006 [Correção com Pagamento Substituto]:** A ação "Corrigir pagamento" permite alterar conta bancária, data ou valor com motivo obrigatório, realizando o estorno do original e a emissão do substituto de forma atômica na mesma transação.

#### 2.7.2. Edição de Categoria de Contas a Pagar (AC-PAY-CAT)
- **AC-PAY-CAT-001 [Contrato PATCH com Categoria]:** O endpoint `PATCH /api/spaces/{space}/payables/{payable}` aceita o campo opcional e anulável `category_id`.
- **AC-PAY-CAT-002 [Validação Estrita de Tenant e Tipo]:** Se `category_id` for informado, valida obrigatoriamente que a categoria existe, pertence ao mesmo `space_id` e possui `type == 'expense'`.
- **AC-PAY-CAT-003 [Prevenção IDOR / BOLA]:** Tentativas de vincular categorias inexistentes ou pertencentes a outro espaço respondem invariavelmente com HTTP 404 Not Found.
- **AC-PAY-CAT-004 [Trilha de Auditoria Indelével]:** Toda alteração de categoria é registrada em `obligation_changes` com `subject == 'payable'`, `action == 'edit'` e antes/depois de `category_id`.
- **AC-PAY-CAT-005 [Edição Pré e Pós-Liquidação sem Violação Contábil]:** A categoria pode ser alterada antes da liquidação e inclusive após a liquidação integral (`paid_cents == amount_cents`), atuando como reclassificação analítica e gerencial sem alterar retroativamente `account_movements` históricos.
- **AC-PAY-CAT-006 [Interface Web e Mobile Atualizada]:** O formulário de edição de contas a pagar no Web Desktop (`PayableModal`) e no Mobile (`PayableEditScreen`) disponibiliza o seletor `CategoryPickerField` para seleção, troca e remoção de categoria, atualizando imediatamente a interface após salvar.

#### 2.7.3. Composição de Pagamento com Juros, Multa e Desconto (AC-PAY-INT)
- **AC-PAY-INT-001 [Contrato de Pagamento com Encargos e Desconto]:** O endpoint `POST /api/spaces/{space}/payables/{payable}/payments` aceita os campos opcionais em string decimal canônica não negativa: `interest_amount` (juros), `fine_amount` (multa) e `discount_amount` (desconto).
- **AC-PAY-INT-002 [Fórmula Canônica e Aritmética de Centavos]:** O cálculo aplica estritamente em centavos inteiros de 64 bits: $\text{total\_cents} = \text{principal\_cents} + \text{interest\_cents} + \text{fine\_cents} - \text{discount\_cents}$. Proibido float/double. Rejeita `total_cents <= 0` ou `discount_cents > principal_cents + interest_cents + fine_cents`.
- **AC-PAY-INT-003 [Segregação Contábil do Exemplo Obrigatório]:** Para uma obrigação de R$ 100,00 com juros de R$ 15,00: a obrigação é amortizada em R$ 100,00 (status "Pago"); a conta bancária sofre débito de R$ 115,00 (`account_movements.amount_cents = -11500`).
- **AC-PAY-INT-004 [Persistência e Auditoria Completa]:** A tabela `payments` armazena de forma auditável `principal_cents`, `interest_cents`, `fine_cents`, `discount_cents` e `total_cents`.
- **AC-PAY-INT-005 [Estorno com Recomposição Integral]:** Ao estornar um pagamento com encargos, a conta bancária é creditada pelo exato `total_cents` (+R$ 115,00) e a obrigação reabre pelo `principal_cents` amortizado (R$ 100,00).
- **AC-PAY-INT-006 [Ergonomia Web e Mobile]:** O formulário de baixa disponibiliza seção expansível "Juros e encargos", calculando e exibindo em tempo real o principal, juros, multa, desconto e o total a debitar da conta.
- **AC-PAY-INT-007 [Garantias de Integridade Transacional]:** Idempotência com fingerprint dos encargos, locks ordenados e limites monetários permanecem 100% garantidos.

---

### 2.8. Seleção Explícita de Contas nas Liquidações (AC-FIN-024)

- **AC-FIN-024 [Seleção Explícita Obrigatória de Conta Bancária nas Baixas]:**
  - Nos fluxos de liquidação de contas a pagar (`PayableActionModal`, `BatchPayableModal`, `PaymentFormScreen`) e de contas a receber (`AgreementActionModal`, `ReceiptFormScreen`), unitários ou em lote:
    1. O campo de conta bancária inicia obrigatoriamente sem pré-seleção, exibindo o hint orientativo `"Selecione uma conta"`.
    2. É expressamente proibida a auto-seleção da primeira conta cadastrada da lista, prevenindo débitos ou créditos acidentais na conta bancária errada por desatenção.
    3. A tentativa de confirmação sem seleção prévia de conta é bloqueada com mensagem de validação clara (`"Selecione uma conta bancária para debitar o pagamento."` / `"Selecione uma conta bancária de destino para o recebimento."`).
    4. O comportamento é perfeitamente uniforme e consistente entre recebimentos e pagamentos, fluxos individuais e em lote, inclusive quando existir apenas uma única conta cadastrada no espaço ativo.
    5. Apenas contas ativas e pertencentes ao espaço autenticado são listadas e aceitas na operação.

---

### 2.9. Experiência Multiplataforma, Ergonomia e Acessibilidade (AC-UI)

- **AC-UI-001 [Retorno Coerente e Sem Empilhamento na Criação, Pagamento e Recebimento]:**
  - Ao cadastrar uma nova conta a receber via `AgreementFormScreen` (desktop modal ou mobile bottom sheet), o salvamento bem-sucedido emite feedback instantâneo via `SnackBar`, aciona `SessionController.dataChanged()` para recarregamento reativo e executa `Navigator.of(context).pop(agreement)`.
  - Ao acionar o recebimento de parcela via ação rápida ("Receber") em `AgreementModal`, a confirmação bem-sucedida emite feedback visual breve (700ms), fecha o modal reativamente com `Navigator.of(context).pop()` e exibe `SnackBar('Recebimento registrado com sucesso.')`, evitando empilhamento sucessivo de modais.
  - De forma estritamente análoga, em Contas a Pagar (`PayablesTab`), a ação rápida "Pagar" abre `PayableModal` em modo de liquidação direta (`initialPaying: true`); após confirmação bem-sucedida, o modal é fechado reativamente com emissão de `SnackBar`, mantendo o usuário na lista de origem com filtros e posição preservados.
- **AC-UI-002 [Filtro de Período Padrão no Mês Corrente e Intervalo Personalizado]:**
  - As listagens de Contas a Pagar (`PayablesTab`) e Contas a Receber (`AgreementsTab`) iniciam por padrão com a situação "Em aberto" selecionada e período restrito ao **mês corrente completo** (do 1º ao último dia do mês corrente, ex.: 1º a 30 de novembro) com base na data de vencimento.
  - O Extrato (`StatementTab`) lista exclusivamente movimentações financeiras efetivamente realizadas e liquidadas, iniciando por padrão no **mês corrente completo**, com todas as direções (`direction: all`), todas as contas bancárias e todas as categorias.
  - O seletor de períodos suporta a opção "Intervalo personalizado...", abrindo o diálogo nativo `showDateRangePicker` com validação de datas, limites de mês, virada de ano e ordenação cronológica estrita (`start <= end`), permitindo consultar qualquer janela temporal arbitrária.
- **AC-UI-003 [Navegação Mensal Fluida, Tratamento de Bordas e Igualdade de Seleção]:**
  - O componente `FinancialPeriodBar` oferece navegação mensal instantânea pelos botões chevron (`<` e `>`), permitindo alternar meses sem recarregar a aplicação.
  - O cálculo de intervalo preserva virada de ano (dezembro $\leftrightarrow$ janeiro) e calcula o último dia de forma exata para meses curtos e anos bissextos (28 vs. 29 de fevereiro).
  - A classe `FinancialPeriodSelection` implementa normalização automática, correspondência estrita por intervalo (`contains(dueDate)` / `matchesCustom(dueDate)`) e operadores `==` e `hashCode` para estabilidade de estado reativo.
- **AC-UI-004 [Alerta Contextual de Contas Vencidas Fora do Mês Ativo]:**
  - Quando houver contas em aberto com vencimento anterior ao início do mês em exibição, a interface apresenta o componente `FinancialOverdueBanner` alertando sobre a existência de pendências vencidas e disponibilizando atalho de 1 toque ("Ver vencidas") para visualização imediata.
- **AC-UI-005 [Alinhamento Numérico Contábil e Leitura Responsiva]:**
  - Em visualização desktop em tabela (`FinancialDesktopTableRow`), as colunas de valor e saldo devido utilizam alinhamento estrito à direita (`TextAlign.right`, `Alignment.centerRight`) para conferência contábil vertical imediata.
  - Títulos e descrições longas contam com `Tooltip` no desktop e exibição adaptativa fluida no mobile (`Wrap` e `FinancialMobileCard`), prevenindo cortes inacessíveis e estouramento de layout.
- **AC-UI-006 [Extrato com Filtros Compostos, Limpeza Rápida e Contenção Widescreen]:**
  - As telas de Dashboard (`SummaryTab`) e Extrato (`StatementTab`) possuem contenção de largura máxima (`maxWidth: 1040`) centralizada em monitores widescreen desktop, eliminando campos dispersos e esticados.
  - O Extrato (`StatementTab`) integra barra de período canônica (`FinancialPeriodBar`), filtros por direção (Todos, Entradas, Saídas), conta bancária e categoria, chips visuais de filtros ativos com remoção individual, botão de limpeza rápida ("Limpar filtros") e estado vazio contextual com ação de restauração.
  - Lançamentos no Extrato utilizam obrigatoriamente a formatação brasileira de datas (`formatDateBr`, `dd/MM/yyyy`) e distinção visual nítida de sinal e cor entre entradas (`+ R$`) e saídas (`- R$`).
- **AC-UI-010 [Identificação Visual de Obrigatoriedade e Foco Automático no Primeiro Erro em Formulários Financeiros]:**
  - Em todos os formulários financeiros modais e telas de cadastro/edição (`PayableFormScreen`, `PayableEditScreen`, `AgreementFormScreen`, `AccountFormScreen`, `AccountEditScreen`), compartilhados entre os espaços Pessoa Física (PF) e Pessoa Jurídica (PJ):
    1. **Identificação Visual Prévia:** Todo campo de preenchimento obrigatório deve conter um asterisco explícito no rótulo (`*`), garantindo identificação visual clara antes de qualquer tentativa de submissão e acessibilidade semântica (a cor não é a única indicação de obrigatoriedade).
    2. **Campos Opcionais:** Campos opcionais recebem a indicação explícita e suave `(opcional)` no rótulo (ex.: `Beneficiário (opcional)`, `Categoria (opcional)`, `Data limite (opcional)`, `Estimativa de valor (opcional, para planejamento)`, `Motivo da alteração (opcional)`).
    3. **Dinamismo por Modalidade Contratual:** Campos condicionais adaptam seus rótulos em tempo real de acordo com a modalidade selecionada:
       - *Avulsa:* `Valor *` e `Vencimento *`.
       - *Parcelada:* `Valor total *` (ou `Valor da parcela *` conforme o modo de cálculo), `Número de parcelas *` (ou `Parcelas *` em desktop) e `Primeiro vencimento *`.
       - *Recorrência Fixa:* `Valor mensal *` e `Primeiro vencimento *`.
       - *Recorrência Variável:* `Valor da primeira ocorrência (opcional)` e `Primeiro vencimento *`. O valor é opcional na modalidade variável e não impede o avanço/salvamento.
    4. **Validação Inline e Erro Imediato:** Quando o usuário tenta submeter ou avançar no formulário com campos inválidos ou pendentes:
       - As mensagens de validação aparecem inline imediatamente adjacentes aos campos com erro (ex.: *"Informe a descrição."*, *"Informe o valor."*, *"De 1 a 1200 parcelas."*, *"Informe um nome."*, *"Informe o saldo inicial."*).
       - O formulário requisita foco automaticamente e rola suavemente (`Scrollable.ensureVisible` com `alignment: 0.1` e duração adaptativa) até o **primeiro campo inválido na ordem visual** (de cima para baixo), mesmo que o campo esteja abaixo da dobra ou oculto pela rolagem.
    5. **Preservação de Dados e Tolerância a Campos Ocultos:** Campos preenchidos validamente não são limpos em caso de erro; campos ocultos pela modalidade corrente ou opcionais jamais bloqueiam a submissão. Ao sanar os erros pendentes, o envio é concluído com sucesso.

---

### 2.10. Novas Funcionalidades Contábeis e Notificações (2026-11)

- **AC-FIN-025 [Conta Recorrente com Valor Variável e Ocorrências 'Aguardando Valor']:**
  - O fluxo de cadastro de despesa recorrente (`POST /api/spaces/{space}/payables` com `kind = 'recurring'`) suporta modalidade fixa e variável (`is_variable = true`).
  - Na modalidade variável, o usuário pode opcionalmente definir uma estimativa de valor para planejamento orçamentário (`estimated_amount`), mas o valor contratual das ocorrências geradas é inicialmente indefinido (`amount_cents = null`).
  - Ocorrências variáveis geradas até o horizonte (mês atual + 12) assumem situação `awaiting_amount` e exibem o badge "Aguardando valor" na agenda financeira.
  - Na agenda e nos totais analíticos, o sistema segrega valores confirmados, valores estimados e ocorrências de valor desconhecido.
  - O sistema permite confirmar o valor de uma ocorrência pontual (`PATCH /api/spaces/{space}/payables/{payable}`) sem alterar os demais meses da série.
  - Na liquidação de uma ocorrência em `awaiting_amount`, o usuário pode informar o valor efetivo e quitar na mesma requisição atômica (`POST .../payments`).
  - Apenas a liquidação efetiva debita a conta bancária; compromissos aguardando valor ou estimados jamais alteram o saldo disponível.
  - Reexecução do gerador de obrigações (`GenerateObligations`) preserva as ocorrências variáveis existentes e seus valores confirmados ou pagos.

- **AC-FIN-026 [Registro Direto de Compra no Débito em Transação Atômica e Idempotente]:**
  - Disponibiliza a ação "Registrar despesa paga" a partir da tela inicial (Dashboard) e do Extrato (`StatementTab`), distinguindo-se claramente de "Agendar conta a pagar".
  - Ao ser acionada a partir do Extrato com uma conta bancária selecionada no filtro de contexto, a interface destaca visualmente essa conta mantendo a seleção transparente.
  - Permite informar conta bancária, valor, data do pagamento, descrição e categoria opcional, concluindo a operação com uma única confirmação do usuário.
  - O backend processa a operação de forma estritamente atômica em uma única transação de banco de dados (`RegisterDirectExpense` / `POST /api/spaces/{space}/payables/direct-expense`):
    1. Cria a obrigação (`Payable`) com `kind = 'single'`, `due_date = paid_on`, `amount_cents = valor` e `paid_cents = valor` (status quitado imediatamente);
    2. Cria o pagamento (`Payment`) debitando a conta de origem;
    3. Cria a movimentação de conta (`AccountMovement`) com sinal negativo;
    4. Registra a auditoria em `ObligationChange`.
  - Exemplo mandatório: compra de R$ 35,90 em conta com saldo de R$ 100,00 resulta em saldo disponível de exatamente R$ 64,10, gerando uma única saída no extrato, uma única despesa no relatório analítico e zero obrigações em aberto.
  - Idempotência rigorosa: requisição repetida com a mesma chave e idêntico payload devolve o resultado prévio (`200 OK` / `201 Created` com `replayed = true`); payload divergente responde `409 Conflict`.
  - Estorno integral: caso o pagamento seja estornado via `ReversePayment`, o saldo da conta bancária é recomposto aos R$ 100,00 originais com trilha indelével de auditoria, sem deixar obrigações abertas pendentes de cancelamento manual.

- **AC-FIN-027 [Catálogo de Instituições com Wise e DUCZ Benefícios]:**
  - O catálogo local (`BankCatalog`) inclui as marcas oficiais:
    - **Wise:** id `'wise'`, nome `'Wise'`, código COMPE oficial `'362'`, cor floresta/verde claro (`#163300` / `#9FE870`) e asset local 256x256 com proporções preservadas e legibilidade nos modos claro e escuro.
    - **DUCZ Benefícios:** id `'ducz'`, nome `'DUCZ Benefícios'`, código `'---'` (instituição de benefícios / despesas corporativas), cor institucional roxo/magenta (`#7B2CBF`) e suporte a fallback de iniciais caso o logo não esteja presente.
  - Ambas as marcas são localizáveis por busca de texto na criação e edição de contas bancárias.
  - A instituição permanece corretamente associada e exibida nos cards de conta, extrato e seletores mesmo após edição de apelido da conta.
  - Permite que uma conta preexistente cadastrada como "Outra Instituição" seja reassociada à DUCZ Benefícios ou à Wise, preservando integralmente seu ID, saldo disponível, movimentações históricas e correções de abertura.

- **AC-FIN-028 [Sininho de Notificações com Leitura e Dispensa Persistentes]:**
  - O sistema implementa persistência de estado de alertas (`AlertState`) segregada por tupla `(user_id, space_id, alert_key)` na tabela `alert_states`.
  - Ações disponíveis por alerta ativo no painel executivo:
    - **Marcar como lido:** atualiza `read_at = now()`, mantendo o alerta consultável na lista ativa com estilo visual lido e decrementando o badge de notificações não lidas.
    - **Dispensar:** atualiza `dismissed_at = now()`, removendo o alerta da lista ativa de notificações sem excluir nem afetar a obrigação financeira na agenda ou no extrato.
  - O badge numérico do sininho na barra superior reflete estritamente o total de alertas ativos não dispensados e não lidos (`unread_active_count`), desaparecendo automaticamente quando a contagem atingir zero.
  - Persistência granular: duas contas com vencimento na mesma data geram chaves de alerta distintas; dispensar uma mantém a outra ativa.
  - Uma nova competência mensal de uma mesma conta recorrente possui identificador próprio e gera seu próprio alerta.
  - Isolamento intransponível: estados de leitura e dispensa são estritamente isolados entre usuários e entre os espaços PF e PJ do mesmo usuário.

- **AC-FIN-029 [Canal Oficial Exclusivo via Navegador e Barreira Dupla de Release]:**
  - O canal oficial de entrega e homologação do BigDev.Z Finance é estritamente o navegador (Flutter Web em Desktop Widescreen >= 840px / 1200px e Mobile Web em smartphones < 840px / 375px), conforme a Decisão de Arquitetura ADR 0007. A publicação em lojas de aplicativos nativas (Google Play e Apple App Store) fica congelada.
  - A publicação em produção exige barreira dupla pós-deploy executada via HTTPS público:
    1. Revisão e integridade da API em `/api/health` com `.status == "ok"` e `.revision == $RELEASE_SHA`.
    2. Hash SHA-256 do arquivo JavaScript principal `main.dart.js` idêntico ao hash do bundle compilado para a release (`EXPECTED_WEB_HASH`).
  - Qualquer divergência entre o backend publicado e o bundle web servido bloqueia a promoção e aciona falha no pipeline via `scripts/verify-production-release.sh`.

- **AC-FIN-032 [Persistência de Carnês e Parcelamentos com Valores e Vencimentos Customizados]:**
  - O backend permite o cadastro de parcelamentos (`kind: 'installment'`) informando opcionalmente a coleção explícita de parcelas (`installments: list<array{number: int, amount: string, due_date: string}>`).
  - Validações determinísticas obrigatórias:
    1. Quantidade de itens no array idêntica ao `installment_count`.
    2. Numeração sequencial contígua de 1 até `installment_count`.
    3. Cada parcela possui valor monetário estritamente positivo (`amount > 0`) e no limite suportado (`MoneyAmount`).
    4. Cada parcela possui data de vencimento válida no formato `Y-m-d`.
    5. A data da primeira parcela (`number == 1`) deve ser idêntica a `first_due_date`.
    6. As parcelas devem respeitar ordenação cronológica não-decrescente (`due_date[i] >= due_date[i-1]`).
    7. A soma algébrica exata dos centavos de todas as parcelas (`sum(amount_cents)`) deve ser rigorosamente igual ao `total_cents` (`total` do plano). Divergências geram rejeição atômica `422 Unprocessable Entity` com erro explicativo no campo `total`.
  - Se `installments` for omitido, o sistema preserva 100% de compatibilidade retroativa, dividindo o valor total de forma determinística via `InstallmentSchedule::generate`.
  - Cada parcela é gravada como obrigação prevista individual (`Payable`) associada ao plano (`PayablePlan`), mantendo idempotência por chave e isolamento estrito por espaço multi-tenant (`space_id`).

- **AC-UI-011 [Edição de Valores e Vencimentos na Prévia de Parcelamento]:**
  - No formulário de Contas a Pagar (`PayableFormScreen`), a seção de prévia do cronograma de parcelamento exibe cards/linhas interativas permitindo editar individualmente a data de vencimento e o valor de cada parcela antes da gravação.
  - Ao alterar o valor de qualquer parcela, o total agregado do plano é recalculado e atualizado instantaneamente na interface sem necessidade de nova requisição ao servidor.
  - Ao alterar o vencimento de uma parcela, a data é atualizada com seletor de data (`DateField` / date picker formatado `DD/MM/AAAA`).
  - O envio do formulário transmite a lista de parcelas customizadas confirmadas na prévia, persistindo com exatidão matemática os mesmos valores e datas na API.

- **AC-FIN-033 [Sugestão de Próximo Dia Útil Bancário na Prévia de Carnês]:**
  - Para novos carnês de boletos comuns, a opção “Sugerir próximo dia útil bancário” começa desativada. O usuário usa as datas da guia para tributos.
  - Quando ativada, a prévia gera as datas contratuais mensais e avança cada data não útil de forma independente. O calendário nacional usa sábados, domingos, feriados bancários fixos e móveis e o último dia de expediente restrito do ano. Referências: [Resolução CMN 4.880](https://www.bcb.gov.br/estabilidadefinanceira/exibenormativo?numero=4880&tipo=RESOLU%C3%87%C3%83O+CMN) e [calendário Febraban](https://portal.febraban.org.br/Noticia/4413/pt_br).
  - O ajuste preserva o dia de referência da série e a distribuição monetária. A data editada manualmente prevalece, inclusive ao recalcular a prévia com a mesma data de referência e quantidade. Cabe ao usuário informar datas específicas de feriados locais ou do emissor.
  - O backend calcula a sugestão somente na prévia. O cadastro persiste as datas confirmadas por parcela, preservando o contrato de criação e a edição manual.

- **AC-FIN-034 [Receitas Mensais Recorrentes Fixas e Variáveis no Módulo A Receber]:**
  - O módulo A Receber (`agreements`) suporta contratos de receita contínua mensal (`kind = 'recurring'`), categorizados em modalidade de valor fixo (`is_variable = false`) ou valor variável (`is_variable = true`).
  - No modo fixo, o valor mensal (`amount_cents`) é obrigatório no cadastro e replica seu valor exato em todas as ocorrências geradas da série.
  - No modo variável, o usuário pode definir um valor estimado opcional (`estimated_amount_cents`) e, opcionalmente, informar o valor da primeira ocorrência (`amount_cents` na data inicial `due_date == start_date`). Ocorrências sem valor confirmado nascem com `amount_cents = null` e situação `awaiting_amount` ("Aguardando valor"). A prévia mantém a estimativa separada do valor inicial confirmado.
  - O cadastro de receita recorrente representa uma projeção orçamentária e jamais altera o saldo disponível das contas bancárias até a efetiva liquidação via recebimento.
  - A operação exige cabeçalho `Idempotency-Key` por espaço. Replays da mesma requisição com a mesma chave devolvem o contrato já existente e suas ocorrências sem duplicidade.

- **AC-FIN-035 [Geração Periódica, Horizonte e Preservação de Data de Referência em Receitas Recorrentes]:**
  - A geração de ocorrências (`installments`) de receitas recorrentes projeta ciclos mensais até o horizonte canônico (`horizon = now + 12 meses`) ou até a data limite final (`end_date`), quando configurada.
  - A chave de unicidade composta `(agreement_id, cycle)` no banco garante idempotência estrita: reexecuções da geração nunca duplicam ciclos existentes nem alteram ocorrências já baixadas, confirmadas ou editadas.
  - A data de vencimento de cada ocorrência preserva deterministicamente o dia de referência (`reference_day`) do cadastro, utilizando `MonthlyDate::shift`: em meses curtos (ex.: 28 ou 29 em fevereiro, 30 em abril/junho/setembro/novembro), o vencimento recai no último dia válido do mês e retorna ao dia de referência no mês seguinte.
  - Quando a data inicial for retroativa em relação à data atual, a criação exige confirmação explícita (`confirm_past = true`) das ocorrências nascidas no passado.

- **AC-FIN-036 [Liquidação e Estorno de Ocorrências Recorrentes com Preservação de Saldo e Auditoria]:**
  - A liquidação de qualquer ocorrência de receita recorrente ocorre pela Action atômica `ReceiveInstallment`, creditando a conta bancária indicada na data de recebimento e registrando a respectiva movimentação em `account_movements`.
  - Ocorrências variáveis com `amount_cents = null` podem ter seu valor confirmado no próprio ato do recebimento, fixando `amount_cents = amountReceived` e quitando o lançamento.
  - O estorno de recebimento de receita recorrente via `ReverseReceipt` reverte o crédito na conta bancária através de contra-movimentação negativa idêntica, preserva auditoria em `receipt_reversals` e `obligation_changes`, e restaura a ocorrência para situação pendente ou aguardando valor, sem alterar outros ciclos da série. O usuário acessa o recebimento e seu estorno pelo histórico da ocorrência.

- **AC-UI-012 [Interface de Cadastro de Receitas Recorrentes com Prévia e Alternância Ergonômica]:**
  - No formulário de cadastro de conta a receber (`AgreementFormScreen`), o usuário pode selecionar o tipo `Recorrente` via seletor de segmento (`Avulsa | Parcelada | Recorrente`).
  - Em modo Recorrente:
    - Alternador ergonômico entre `Valor Fixo` e `Valor Variável`.
    - No modo fixo, exibe o campo obrigatório `"Valor mensal"`.
    - No modo variável, exibe os campos `"Valor da 1ª ocorrência (opcional)"` e `"Valor estimado mensal (opcional)"`.
    - Campo de data de início (`DateField`) e campo de data de término opcional.
    - Botão de prévia interativa com modal demonstrando o cronograma projetado de ocorrências, quantidade de ocorrências passadas/vencidas e checkbox mandatório de confirmação de ocorrências passadas quando aplicável.
    - No `AgreementsTab` e no `AgreementModal`, ocorrências com `amount == null` exibem rótulo destacado `"Aguardando valor"` com tom neutro e botão de baixa/definição de valor inline.
- **AC-FIN-030 [Compromissos em Aberto sem Dupla Contagem]:**
  - O campo `open_total` já inclui as contas em aberto vencidas e a vencer com valor definido. O dashboard exibe o total em aberto e as fatias temporais separadamente, sem somar vencidos novamente ao total. A projeção temporal segue o AC-FIN-037.
- **AC-UI-008 [Ergonomia Widescreen e Grid Multi-Colunas nas Telas Principais]:**
  - Aplica contenção de largura máxima padronizada de 1280px (`maxWidth: 1280`) nas cinco telas principais da aplicação: Dashboard (`SummaryTab`), Extrato (`StatementTab`), A Pagar (`PayablesTab`), A Receber (`AgreementsTab`) e Contas (`AccountsTab`), com margens responsivas centralizadas e padding de 24px em desktop (>= 840px) e 16px em mobile (< 840px).
  - No Dashboard (`SummaryTab`), em desktop widescreen (`isDesktop`), a carteira agrupada à distribuição por bancos e o Fluxo de Caixa ficam lado a lado em duas colunas equivalentes.
  - Na tela de Contas (`AccountsTab`), em desktop widescreen com mais de uma conta ativa cadastrada, a listagem adota visualização em grade multi-colunas (`Wrap` com largura flexível para cada card), eliminando estiramento excessivo em monitores ultrawide.
  - Na tabela executiva desktop compartilhada (`FinancialDesktopTable`), as proporções de colunas de texto são expandidas para `flex: 5` na Descrição, `flex: 3` na Categoria e `flex: 2` no Tipo/Parcela, preservando as larguras mínimas fixas de Vencimento (96px), Situação (110px), Valor (120px) e Ações (90px), eliminando truncamento precoce de nomes e subcategorias sem prejudicar a leitura numérica.
  - Mantém a ergonomia touch original em telas compactas e smartphones (< 840px), preservando listas verticais de coluna única, bottom sheets e padding de 16px.

- **AC-UI-009 [Botão Integrado de Despesa Paga no Dashboard]:**
  - Na seção de Ações Rápidas do Dashboard (`_DashboardPriorities`), o botão de registro direto de despesa utiliza o rótulo objetivo e conciso `"Registrar despesa paga"`.
  - Em telas desktop (>= 840px), o botão possui largura controlada com `maxWidth: 320` alinhado à esquerda na seção de ações, evitando estiramento horizontal desproporcional. Em telas mobile (< 840px), ocupa 100% da largura útil com altura mínima de toque de 44px (`minHeight: 44`).
  - Adota estilo visual tonal (`FilledButton.tonalIcon`) com ícone representativo (`Icons.receipt_long_rounded` ou `Icons.payment_rounded`), mantendo consistência com o tema visual do sistema em PF e PJ.
  - O acionamento abre o modal unificado de despesa rápida (`showDirectExpenseModal`) preservando a integridade do lançamento financeiro em conta e no extrato.
- **AC-FIN-031 [Primeira Ocorrência de Recorrência Variável com Valor Inicial Confirmado]:**
  - Ao cadastrar uma recorrência com valor variável (`is_variable = true`), o usuário pode opcionalmente preencher o valor monetário da primeira fatura/ocorrência no campo `amount`.
  - Quando informado no cadastro, esse valor inicial é atribuído estritamente como `amount_cents` confirmado da ocorrência vinculada ao primeiro vencimento (`due_date == start_date`), nascendo com status `open` (ou `overdue` se a data for anterior ao dia atual) e `paid_cents = 0`.
  - Todas as ocorrências subsequentes da série (`due_date > start_date`) continuam nascendo com `amount_cents = null` e situação `awaiting_amount` ("Aguardando valor").
  - Caso o usuário não informe valor inicial (`amount = null`), todas as ocorrências (inclusive a primeira) nascem com `amount_cents = null` e situação `awaiting_amount`.
  - Reexecuções do gerador de obrigações (`GenerateObligations::forRecurrence` e `all()`) preservam o valor da primeira ocorrência e das demais sem alteração, sem duplicidade e sem sobrescrever dados.
  - O cadastro de recorrência variável continua representando um compromisso orçamentário em aberto e jamais altera o saldo disponível da conta bancária até que haja pagamento efetivo registrado.

- **AC-UI-007 [Rótulo Conciso e Não Truncado do Campo de Valor em Recorrência Variável]:**
  - No formulário de cadastro de conta a pagar (`PayableFormScreen`), quando a modalidade selecionada for Recorrente (`_Kind.recurring`):
    - Em modo Valor Fixo (`!_isVariable`): o rótulo do campo de valor exibe `"Valor mensal"`.
    - Em modo Valor Variável (`_isVariable`): o rótulo do campo de valor exibe `"Valor da 1ª ocorrência (opcional)"`, formulado de forma concisa e legível, sem sofrer truncamento por reticências em viewports estreitos (mobile 375pt) nem na disposição em colunas lado a lado no desktop widescreen.

- **AC-FIN-037 [Saldo Projetado de Curto Prazo]:** O dashboard mostra o saldo disponível hoje mais entradas previstas e menos saídas previstas com valor informado, com vencimentos de hoje até hoje + 30 dias no fuso financeiro. A projeção exclui vencidos, realizados e registros cancelados. A interface informa a janela, a exclusão de vencidos e a limitação aos valores conhecidos. Se a API não fornecer entradas do período, a projeção fica indisponível.
- **AC-UI-013 [Prioridades do Dashboard]:** A primeira seção após o saldo apresenta vencidos, próximos 30 dias e valores a informar, com navegação para as listas correspondentes. A carteira e a distribuição por bancos ficam agrupadas. A ação de despesa paga usa o estilo tonal do tema. A interface mantém o modo de privacidade e a leitura em desktop e mobile.

- **AC-UI-014 [Filtros e Estados de Consulta das Operações Web]:** Extrato, A Pagar e A Receber agrupam os filtros de período e de seleção em uma área visível no desktop, inclusive com resultados vazios. O Extrato oferece intervalos dos últimos 7 e 30 dias, incluindo hoje. A agenda oferece próximos 7 e 30 dias e mantém intervalo personalizado. O seletor de categorias apresenta a hierarquia e permite pesquisar pelo nome e pelo caminho. Os estados vazios orientam a próxima ação. O mobile mantém controles compactos e só aplica mudanças do painel ao confirmar. As tabelas mantêm valores, datas e categorias legíveis, com situação identificada em coluna própria.
- **AC-UI-015 [Entrada Monetária no Cronograma]:** Os campos de valor das parcelas descartam caracteres não numéricos, exibem centavos no formato brasileiro e mantêm o total exato durante a edição no desktop e no mobile.

## 3. Matriz de Rastreabilidade (Spec ↔ Código ↔ Testes)

| Critério | Implementação Backend / Mobile | Testes Automatizados |
| :--- | :--- | :--- |
| **AC-FIN-001** | `Money.php`, `money.dart`, migrations `BIGINT` | `apps/api/tests/domain.php`, `money_test.dart` |
| **AC-FIN-002** | `Money::toCents`, `Money.parse`, colunas `_cents` | `apps/api/tests/domain.php`, `ReceivablesFlowTest.php` |
| **AC-FIN-003** | `MoneyAmount.php`, `Money::fromCents`, API REST | `apps/api/tests/domain.php`, `PayablesTest.php` |
| **AC-FIN-004** | `Money::MAX_CENTS`, `Money.isNegative`, checks SQL | `apps/api/tests/domain.php`, `PayableCreationRecoveryTest.php` |
| **AC-FIN-005** | `InstallmentSchedule.php`, `CreatePayable::schedule` | `apps/api/tests/domain.php`, `PayablesTest.php` |
| **AC-FIN-006** | `MonthlyDate.php`, `InstallmentSchedule::generate` | `apps/api/tests/domain.php` |
| **AC-FIN-007** | `PayPayable.php`, `Payment.php`, `PaymentResource.php`, `payable_modal.dart`, `payment_form_screen.dart` | `apps/api/tests/domain.php`, `PayableChargesAndDiscountsTest.php` |
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
| **AC-PAY-REV-001..006** | `ReversePayment.php`, `PaymentController.php`, `payable_modal.dart`, `payment_fix_screen.dart` | `PayablesTest.php`, `payable_modal_reversal_test.dart` |
| **AC-PAY-CAT-001..006** | `PayableController.php`, `ChangeObligations.php`, `payable_modal.dart`, `payable_edit_screen.dart` | `PayableCategoryEditTest.php`, `payable_category_edit_widget_test.dart` |
| **AC-PAY-INT-001..007** | `PayPayable.php`, `Payment.php`, `PaymentController.php`, `payable_modal.dart`, `payment_form_screen.dart` | `domain.php`, `PayableChargesAndDiscountsTest.php`, `payment_charges_widget_test.dart` |
| **AC-FIN-024** | `payable_modal.dart`, `batch_payable_modal.dart`, `agreement_modal.dart`, `payment_form_screen.dart`, `receipt_form_screen.dart` | `payable_modal_test.dart`, `agreement_modal_test.dart`, `payables_test.dart`, `payable_charges_widget_test.dart` |
| **AC-FIN-025** | `CreatePayable.php`, `GenerateObligations.php`, `PayableController.php` | `VariableRecurrenceTest.php` |
| **AC-FIN-026** | `RegisterDirectExpense.php`, `PayableController.php`, `direct_expense_modal.dart` | `DirectExpenseTest.php` |
| **AC-FIN-027** | `bank_catalog.dart`, `account_form_screen.dart`, `account_edit_screen.dart` | `bank_catalog_test.dart`, `account_form_test.dart` |
| **AC-FIN-028** | `AlertState.php`, `AlertController.php`, `notifications_modal.dart` | `AlertsTest.php`, `notifications_modal_test.dart` |
| **AC-FIN-029** | `scripts/build-web.sh`, `scripts/vps-deploy.sh`, `deploy.yml`, `scripts/verify-production-release.sh` | `test-release-verification.sh`, `test-deploy-integrated-simulation.sh` |
| **AC-FIN-032** | `PayableController.php`, `CreatePayable.php`, `PayablePlan.php` | `EditableInstallmentPlanTest.php` |
| **AC-FIN-033** | `NationalBankCalendar.php`, `PayableController.php`, `payable_form_screen.dart` | `EditableInstallmentPlanTest.php`, `editable_installment_schedule_test.dart` |
| **AC-FIN-034** | `Agreement.php`, `Installment.php`, `CreateAgreement.php`, `GenerateReceivables.php`, `AgreementController.php` | `RecurringReceivableTest.php` |
| **AC-FIN-035** | `GenerateReceivables.php`, `MonthlyDate.php`, `AgreementController.php` | `RecurringReceivableTest.php` |
| **AC-FIN-036** | `ReceiveInstallment.php`, `ReverseReceipt.php`, `agreement_modal.dart` | `RecurringReceivableTest.php`, `agreement_modal_test.dart` |
| **AC-FIN-030** | `dashboard_charts.dart`, `SpaceController.php` | `dashboard_charts_test.dart` |
| **AC-FIN-031** | `CreatePayable.php`, `GenerateObligations.php`, `PayableController.php` | `VariableRecurrenceTest.php` |
| **AC-UI-001** | `agreement_form_screen.dart`, `agreement_modal.dart`, `payable_modal.dart`, `payables_tab.dart` | `agreements_tab_test.dart`, `agreement_modal_test.dart`, `payable_modal_test.dart` |
| **AC-UI-002** | `financial_search_bar.dart`, `payables_tab.dart`, `agreements_tab.dart`, `statement_tab.dart` | `financial_search_and_sort_test.dart`, `financial_agenda_test.dart` |
| **AC-UI-003** | `FinancialPeriodBar`, `FinancialPeriodSelection` (suporte a `custom` e `showDateRangePicker`) | `financial_search_and_sort_test.dart`, `financial_agenda_test.dart` |
| **AC-UI-004** | `FinancialOverdueBanner`, `payables_tab.dart`, `agreements_tab.dart` | `agreements_tab_test.dart`, `payables_test.dart` |
| **AC-UI-005** | `FinancialDesktopTableRow`, `MoneyText`, `Tooltip` | `financial_desktop_table_test.dart`, `agreements_tab_test.dart` |
| **AC-UI-006** | `statement_tab.dart`, `summary_tab.dart`, `FinancialPeriodBar`, filtros por direção/conta/categoria | `statement_tab_test.dart`, `summary_test.dart` |
| **AC-UI-011** | `payable_form_screen.dart`, `payables_repository.dart` | `editable_installment_schedule_test.dart` |
| **AC-UI-012** | `agreement_form_screen.dart`, `agreement_item_adapter.dart`, `agreement_modal.dart` | `recurring_receivable_form_test.dart`, `agreements_tab_test.dart` |
| **AC-UI-008** | `summary_tab.dart`, `statement_tab.dart`, `payables_tab.dart`, `agreements_tab.dart`, `accounts_tab.dart`, `financial_desktop_table.dart` | `widescreen_and_direct_expense_test.dart` |
| **AC-UI-009** | `summary_tab.dart`, `direct_expense_modal.dart` | `widescreen_and_direct_expense_test.dart`, `six_features_homologation_test.dart` |
| **AC-UI-007** | `payable_form_screen.dart` | `payable_form_modal_test.dart` |
| **AC-UI-010** | `payable_form_screen.dart`, `payable_edit_screen.dart`, `agreement_form_screen.dart`, `account_form_screen.dart`, `account_edit_screen.dart`, `widgets.dart` | `form_validation_and_required_indicators_test.dart` |
| **AC-UI-014** | `financial_search_bar.dart`, `statement_tab.dart`, `payables_tab.dart`, `agreements_tab.dart` | `financial_search_and_sort_test.dart`, `statement_tab_test.dart`, `financial_agenda_test.dart` |
| **AC-FIN-037** | `SpaceController.php`, `dashboard_charts.dart` | `PayablesTest.php`, `dashboard_charts_test.dart` |
| **AC-UI-013** | `summary_tab.dart`, `PayableController.php`, `payables_tab.dart` | `summary_test.dart`, `home_shell_test.dart`, `PayablesTest.php` |
| **AC-UI-015** | `payable_form_screen.dart` | `editable_installment_schedule_test.dart` |
