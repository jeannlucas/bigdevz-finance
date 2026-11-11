# Handoff Canônico Universal — BigDev.Z Finance

> **Autoridade Canônica de Continuidade:** BigDev.Z Finance<br>
> **Aplica-se a:** Google Antigravity e OpenAI Codex operando no projeto.<br>
> **Protocolo:** Handoff Universal Bidirecional BigDev.Z (GOV-03 / GOV-06.B).<br>
> **Registro Histórico Precedente:** [`HANDOFF.md`](../../HANDOFF.md) (preservado na raiz como histórico consolidado até 09/10/2026).

---

## 1. Contexto e Identidade do Projeto

- **Produto:** BigDev.Z Finance — Sistema financeiro pessoal e empresarial (multi-espaço PF/PJ) de alta integridade e precisão matemática.
- **Stack:**
  - **Mobile:** Flutter / Dart (3.x) modular por features em `apps/mobile/` (`features/accounts`, `payables`, `agreements`, `summary`).
  - **Backend:** Laravel 13 monólito modular em `apps/api/` com Actions dedicadas (`ReceiveInstallment`, `ReverseReceipt`).
  - **Banco de Dados:** PostgreSQL com restrições compostas `(id, space_id)` e advisory locks para controle de concorrência.
- **Modo do Repositório:** **DESENVOLVIMENTO ATIVO**.
- **Licença:** MIT Formalizada ([LICENSE](../../LICENSE)).
- **Diretrizes e Regras de Domínio:** Consolidadas em [`docs/project-guidelines.md`](../project-guidelines.md) e [`docs/architecture.md`](../architecture.md).

---

## 2. Estado Operacional Atual e Máquina de Estados

- **Estado Operacional:** **`PRODUCAO_INFRA_READY`** (Checkpoint `FINANCE-PADRONIZACAO-MAIUSCULAS-APRESENTACAO-LEGADOS-02`, `FINANCE-PADRONIZACAO-MAIUSCULAS-TEXTOS-FINANCEIROS-01`, `FINANCE-AGENDA-FINANCEIRA-ESCALAVEL-03-FILTROS-REFINADOS`, `FINANCE-PRODUCAO-INFRAESTRUTURA-READINESS-01`).
- **Ciclo de Padronização de Apresentação de Dados Legados em MAIÚSCULAS (100% Concluído e Validado):**
  1. **Auditoria Universal e Aplicação de `toFinancialUpper(...)` exclusivamente na Camada de Apresentação:**
     - **Contas Bancárias / Carteiras:**
       - Cards de conta (`AccountCard`): Título, modalidade, banco e nós semânticos de acessibilidade (`Semantics`) devidamente normalizados em maiúsculas (`Conta NUBANK PRINCIPAL, saldo oculto`).
       - Listagem e aba de contas (`AccountsTab`): Lista "Todas as contas", modalidade, banco catálogo e contadores.
       - Tela de detalhes da conta (`AccountScreen`): Cabeçalho, card de conta e histórico.
       - Ajuste de saldo de abertura (`OpeningFixReview` e `AccountScreen`): Revisões com antes/depois, histórico de ajustes e linhas de saldo.
       - Diálogos de arquivar e desarquivar: Diálogo de confirmação e reversão exibindo identificação em maiúsculas.
       - Seletores de conta em transferências e empréstimos (`TransferFormScreen`, `LoanFormScreen`): Normalizados em `${toFinancialUpper(a.name)} (${a.balance.brl})`.
     - **Empréstimos (`LoanCard`, `LoanDetailScreen`, `LoanFormScreen`):**
       - Listagem de empréstimos (título e contraparte/instituição credora em maiúsculas).
       - Tela de detalhe do empréstimo (título, credor/devedor e dados de parcelas).
       - Seletores de conta de desembolso normalizados.
     - **Contas a Pagar (`PayablesTab`, `PayableScreen`, `PaymentFormScreen`, `PaymentFixReview`, `PayableCreations`, `PayableEditScreen`, `PayableModal`):**
       - Cards e tabela desktop (descrição e favorecido em maiúsculas).
       - Tela de detalhe da conta a pagar (descrição e favorecido em maiúsculas).
       - Telas de pagamento (`PaymentFormScreen`) e correção/revisão (`PaymentFixReview`).
       - Dropdown de conta de origem em pagamentos e pagamentos em lote.
       - Diálogos de confirmação de alterações (`ConfirmChangesDialog`) com `oldValue` e comparações livres de falso diff.
       - Mensagens de pendência, confirmação, replay e alertas de saldo negativo (`BANCO PF`, `RESERVA PF`).
     - **Contas a Receber (`AgreementsTab`, `AgreementModal`, `InstallmentScreen`, `ReceiptFormScreen`, `ReceiptFixReview`, `ReceiptAttempt`):**
       - Acordos, contratos e clientes apresentados em maiúsculas na listagem e detalhes.
       - Seletores de conta de destino na baixa de parcela e correções.
       - Mensagens e banners de confirmação de recebimento (`Recebimento confirmado: ... em BANCO PF`).
       - Linhas de auditoria da parcela com `BANCO PF · 10/03/2026`.
     - **Extrato, Conciliação, Planejamento e Gráficos (`StatementTab`, `OfxScreen`, `PlanningScreen`, `DashboardCharts`, `CategoriesScreen`, `FinancialDesktopTable`, `FinancialMobileCard`):**
       - Extrato de movimentações: Descrição de transação e nome de conta em maiúsculas.
       - Conciliação OFX: Seletores de conta bancária de destino e correspondências sugeridas em maiúsculas.
       - Planejamento financeiro: Filtros de conta e categoria em maiúsculas.
       - Gráficos executivos: Legendas de contas bancárias e categorias no gráfico donut em maiúsculas (`MORADIA`, `ALIMENTAÇÃO`, `NUBANK PRINCIPAL`).
       - Tabela Desktop e Mobile Card universais: `item.title` e `item.counterparty` normalizados.
  2. **Garantia de Não-Mutação e Preservação Estrita:**
     - Nenhum dado legado do banco foi regravado, atualizado em massa ou mutado em memória.
     - Campos sensíveis/técnicos e observações livres preservam sua caixa original sem alteração (`notes`, `reason`, `cancel_reason`, emails, senhas, chaves de idempotência, tokens, enums técnicos, valores monetários e datas).
  3. **Comprovação com Testes Automatizados (292 Testes Flutter 100% Verdes):**
     - Testes específicos criados e atualizados comprovando que registros legados em minúsculas chegam da API e são apresentados em MAIÚSCULAS na UI sem mutar o modelo Dart em memória (`accounts_test.dart`, `payables_test.dart`, `loans_test.dart`, `receipt_form_test.dart`, `receipt_fix_test.dart`, `categories_test.dart`, `dashboard_charts_test.dart`, `financial_desktop_table_test.dart`).
  4. **Quality Gate e Backpressure 100% Verde (`./scripts/check.sh --full`):**
     - 181 testes Laravel (1.728 asserções) com zero falhas no PostgreSQL.
     - 292 testes Flutter (unitários, widgets e fluxos) aprovados com zero falhas.
     - 13 testes de domínio financeiro puro PHP aprovados.
     - `flutter analyze` com "No issues found!".
     - Laravel Pint (156 arquivos) e Dart format (155 arquivos) 100% limpos.
     - `git diff --check` com zero erros.
- **Ciclo de Padronização Segura de Textos Financeiros em MAIÚSCULAS (100% Concluído e Validado):**
  1. **Defesa em Profundidade no Backend (Laravel 13):**
     - Trait `NormalizesFinancialText` em `apps/api/app/Models/Concerns/NormalizesFinancialText.php` com o método utilitário `financialUpper(?string $value)` e o mutator `uppercaseTextAttribute()`.
     - Mutators integrados em todos os 8 models com textos financeiros livres:
       - `Payable.php`: `description` e `payee`.
       - `PayablePlan.php`: `description` e `payee`.
       - `Recurrence.php`: `description` e `payee`.
       - `Agreement.php`: `description`.
       - `Category.php`: `name`.
       - `Account.php`: `name`.
       - `Card.php`: `name`.
       - `Loan.php`: `title` e `counterparty`.
     - `CategoryController.php`: Normalização antecipada do campo `name` antes do `$request->validate()` para que a constraint `Rule::unique` valide o valor em MAIÚSCULAS no banco de dados.
     - Suíte TDD dedicada em `apps/api/tests/Feature/FinancialTextNormalizationTest.php` cobrindo 9 cenários de cadastro, edição, acentuação e preservação estrita de campos sensíveis.
     - Zero migrations destrutivas ou alterações em massa no banco de produção.
  2. **Camada de Apresentação e Digitação no Frontend (Flutter / Dart):**
     - Utilitário `apps/mobile/lib/core/text_formatters.dart`:
       - `toFinancialUpper(String? text)`: Converte textos livres de identificação financeira para MAIÚSCULAS com limpeza de espaços e suporte a Unicode/português.
       - `UpperCaseTextFormatter`: `TextInputFormatter` que converte a digitação em tempo real preservando o cursor do usuário, seleções ativas e sem deslocamentos indesejados.
     - Apresentação de dados legados sem alteração estrutural no banco:
       - `PayableItemAdapter` e `AgreementItemAdapter`: Títulos e credores formatados via `toFinancialUpper`.
       - `CategoryBadge` e `CategoryFilterChip`: Nomes de categorias formatados via `toFinancialUpper`.
       - Modais e telas principais (`PayablesTab`, `AgreementsTab`, `PayableModal`, `AgreementModal`, `CardsScreen`): Cabeçalhos e listagens legadas exibidos em MAIÚSCULAS.
     - Formulários equipados com `UpperCaseTextFormatter`:
       - `payable_form_screen.dart`, `payable_edit_screen.dart`, `payable_modal.dart`.
       - `agreement_form_screen.dart`, `agreement_modal.dart`.
       - `account_form_screen.dart`, `account_edit_screen.dart`.
       - `cards_screen.dart`.
       - `loan_form_screen.dart`.
       - `categories_screen.dart`, `category_picker_field.dart`.
     - Preservação estrita de campos excluídos: E-mails, senhas, tokens/UUIDs, chaves de idempotência, enums técnicos, notas/observações (`notes`) e justificativas de auditoria/cancelamento (`reason`, `cancel_reason`) mantêm seu formato original.
  3. **Quality Gate e Backpressure 100% Verde (`./scripts/check.sh --full`):**
     - 181 testes de API Laravel aprovados (1.728 asserções) com zero falhas no PostgreSQL isolado descartável.
     - 290 testes Flutter aprovados (unitários, widgets e fluxos) sem erros.
     - 13 testes de domínio financeiro puro PHP aprovados.
     - `flutter analyze` com "No issues found!".
     - Laravel Pint (156 arquivos) e Dart format (155 arquivos) 100% limpos.
- **Ciclo de Evolução da Agenda Financeira Escalável (100% Concluído e Validado):**
  1. **Virtualização Real com Lista Plana Sob Demanda:**
     - `financial_agenda_view.dart`: Achatamento das entradas temporais em `_AgendaEntry` (`_GroupHeaderEntry`, `_DesktopTableHeaderEntry`, `_ItemEntry`) alimentando um único `ListView.builder`.
     - Eliminação completa de loops `for` rígidos que instanciavam centenas de widgets simultaneamente.
     - Suporta 110, 500 ou mais lançamentos no mesmo grupo sem sobrecarga de memória, instanciando apenas os widgets visíveis na viewport (+ cache).
     - Comprovado por teste de widget que valida menos de 25 linhas instanciadas inicialmente para uma lista de 120 itens no mesmo grupo temporal, e scroll sob demanda até o item #119.
  2. **Integração Real de Cards Compactos Mobile (< 840px):**
     - `financial_mobile_card.dart`: Layout compacto com badges de situação, data de vencimento com cálculo de atraso, categoria com truncamento seguro (`Flexible`), tipo/parcela, valor e botão de ação rápida ("Pagar" / "Receber").
     - Reflow responsivo via `Wrap` evitando overflow mesmo em telas ultra-compactas (320pt) e escalas de texto de até 200%.
     - `PayablesTab` e `AgreementsTab`: `customMobileCardBuilder` legado removido; ambos usam nativamente `FinancialMobileCard`.
  3. **Filtros Unificados Concluídos e Corrigidos:**
     - `financial_search_bar.dart`: Normalização textual determinística e segura (`normalizeSearchText`), sem dependências externas, com remoção de acentos (`_diacriticsMap`), minúsculas e colapso de espaços excedentes. Comprovado: `agua` encontra `Água`, `JOAO` encontra `João`, `  mercado  ` encontra `Mercado`, tanto em título quanto favorecido/cliente.
     - Correção funcional de categoria: `PayablesTab` e `AgreementsTab` repassam efetivamente `categoryId: _selectedCategoryId` para `filterAndSortFinancialItems`, isolando de verdade os lançamentos da categoria selecionada e restaurando todos os itens ao remover o chip ou limpar filtros.
     - Enum de períodos `FinancialPeriodFilter` (`all`, `overdue`, `today`, `next7Days`, `thisMonth`, `next30Days`, `future`).
     - Ordenação tripla (Vencimento, Maior Valor, Menor Valor, Descrição A-Z).
     - Filtros em chips ativos removíveis com botão "Limpar filtros" (`onClearAllFilters`).
     - Experiência desktop com controles horizontais organizados e experiência mobile abrindo `BottomSheet` modal com contagem de filtros ativos em badge.
  4. **Ação Rápida em "A Receber" com Parcela Específica (`initialInstallmentId`):**
     - `agreement_modal.dart`: `showAgreementModal` expandido para receber parâmetro opcional `initialInstallmentId`. Ao carregar, localiza a parcela informada e direciona a modal diretamente para `_buildBaixaView` ("Baixar Parcela N").
     - `agreements_tab.dart`: Ação rápida "Receber" na tabela desktop e card mobile passa `initialInstallmentId: adapter.installment.id`, eliminando qualquer ambiguidade de direcionamento.
     - Comprovado por teste de widget que simula toque em "Receber" na Parcela 2 e valida abertura direta com "Baixar Parcela 2".
  5. **Quality Gate e Backpressure 100% Verde (`./scripts/check.sh --full`):**
     - 283 testes Flutter aprovados (sem advertências ou falhas).
     - 172 testes de feature da API Laravel (1.708 asserções) com zero falhas no PostgreSQL 18.
     - 13 testes de domínio financeiro aprovados.
     - Flutter analyze com zero avisos ou erros ("No issues found!").
     - Laravel Pint (154 arquivos) e Dart format (153 arquivos) 100% limpos.
- **Ciclo de Preparação da Infraestrutura de Produção (100% Concluído):**
  1. **Decisão Arquitetural de Ambiente Único (Produção):**
     - O projeto operará com ambiente único de produção na branch `main`. A branch atual de funcionalidades (`feature/edicao-cancelamento-lancamentos`) será integrada via Pull Request após revisão humana.
     - Toda e qualquer menção, arquivo ou configuração de staging foi integralmente substituída pela arquitetura canônica de produção.
  2. **Arquitetura Declarativa de Produção Implementada (Alinhada à VPS):**
     - `docker-compose.production.yml`: Orquestração com `postgres:17-alpine` (base `bigdevz_finance`, volume persistente `postgres-data`), `api` Laravel 13 em PHP 8.3 CLI com 4 workers em `127.0.0.1:8510` e `scheduler` para recorrências contínuas. Sem container Nginx no Compose (o Caddy no host gerencia HTTPS e arquivos estáticos SPA em `/srv/finance/web`).
     - `apps/api/Dockerfile.production` e `apps/api/docker/entrypoint.production.sh`: Multi-stage build otimizado com Composer sem dependências de dev (`--no-dev`), usuário não-root `appuser:appgroup` e validação fail-safe obrigatória de `APP_KEY`, `DB_PASSWORD` e `APP_URL`.
     - `.env.production.example`: Especificação estrita e segura das variáveis de produção com placeholders e zero segredos expostos.
     - `scripts/backup-production.sh`: Script de backup do PostgreSQL 17 em formato custom (`pg_dump -Fc`) na base `bigdevz_finance`, com cálculo automático de checksum SHA-256 e rotação/retenção de 30 dias.
     - `scripts/deploy-production.sh`: Script idempotente de deploy com validação de branch `main`, backup automático pré-migração, build, migrations `--force`, caches e rollback automático em falhas.
     - `scripts/rollback-production.sh`: Script de reversão emergencial de código (`--code-only`) e restauração segura do banco `bigdevz_finance` (`--with-db-restore <dump>`).
     - `docs/operations/production-deployment.md`: Guia de deploy alinhado à topologia real da VPS (PostgreSQL 17, `/srv/finance`, Caddy).
     - `docs/operations/production-runbook.md`: Manual operacional com inventário real dos containers e playbooks de incidentes.
  3. **Validação Local dos Artefatos de Produção:**
     - Validação de sintaxe do Docker Compose e de todos os scripts bash.
     - Build de release do Flutter Web e build de produção da API Laravel aprovados.
     - Teste de restauração de dump em banco descartável com 32 tabelas verificadas.
     - Quality gate completo aprovado (`php tests/domain.php`, `vendor/bin/pint --test`, `flutter analyze`, `dart format`, `scripts/smoke-api.sh`).
  4. **Garantia de Soberania e Não-Publicação:**
     - Nenhum deploy remoto, merge ou push para `main` foi executado. O repositório aguarda as definições do proprietário Jeann Lucas para publicação.
- **Ciclo de Release Readiness para Piloto Controlado (100% Concluído):**
  1. **Eliminação Integral de Warnings:**
     - Investigação minuciosa e eliminação da raiz de warnings emitidos pelo phpdotenv sob PHPUnit 10+, atingindo 100% PASS com zero warnings e zero falhas em todas as 1.708 asserções da API.
  2. **Observabilidade e Tracing:**
     - Middleware `AssignRequestId` implementado e registrado no pipeline global, injetando `X-Request-ID` UUID em todas as requisições e respostas HTTP e context logging.
     - Endpoint de monitoramento detalhado `GET /api/health` avaliando conectividade com PostgreSQL, latência em ms, driver e storage.
     - Proteção de Rate Limiting com `throttle:30,1` nos endpoints de processamento OFX.
  3. **Rotina de Backup, Restauração e DR:**
     - Procedimento de backup e restauração estruturado em formato custom (`pg_dump -Fc`), preservando integridade das 32 tabelas, restrições compostas `(id, space_id)`, auditoria (`obligation_changes`), RBAC (`space_users`) e encerramentos contábeis.
     - Teste de restauração real executado com sucesso em banco isolado (`bigdevz_finance_restore_test`) sem impacto nos bancos de produção/desenvolvimento.
     - Runbook operacional completo em `docs/operations/pilot-runbook.md` com critérios de entrada/saída, checklists pré/pós-deploy e protocolo de resposta a incidentes.
  4. **Quality Gate e Backpressure 100% Verde (`./scripts/check.sh --full`):**
     - 172 testes de feature da API Laravel (1.708 asserções) com ZERO warnings e ZERO falhas.
     - 248 testes de widgets e integração Flutter aprovados.
     - 13 testes de domínio financeiro aprovados.
     - 154 arquivos PHP validados pelo Laravel Pint.
     - 141 arquivos Dart validados e sem advertências no `flutter analyze`.
     - Laravel Pint (141 arquivos) e Dart format (131 arquivos) 100% limpos.
     - Flutter analyze com zero avisos ou erros ("No issues found!").
  5. **Auditoria Integral de Produto, UX/UI, Linguagem e Benchmark ERP com 100% de Aprovação:
  1. **Auditoria E2E e Avaliação de Produto via Google Chrome MCP (28 Casos em 6 Lotes):**
     - Homologação completa de ponta a ponta dos módulos de Autenticação, Dashboard, Contas Bancárias, Contas a Pagar, Contas a Receber, Extrato, Categorias e Transferências internas.
  2. **Refinamento de Linguagem e Eliminação de Jargões Técnicos:**
     - Substituição de termos jurídicos/contábeis ("Obrigações", "Baixa múltipla de obrigações", "Anula a obrigação") por linguagem clara e orientada ao usuário final brasileiro ("Contas a pagar", "Pagamento em lote de contas", "Esta ação cancela a conta a pagar") em `payable_modal.dart`, `payment_form_screen.dart`, `payment_fix_screen.dart`, `batch_payable_modal.dart` e `categories_screen.dart`.
  3. **Integração de Funcionalidades Ocultas (Empréstimos e Financiamentos):**
     - Desbloqueio e integração de ponto de entrada direto para `LoansScreen` no menu superior desktop (`_DesktopTopBar`) e no menu de contexto mobile (`home_shell.dart`), permitindo gestão de dívidas tomadas e créditos concedidos com amortização.
  4. **Matriz Estratégica de ERP e Benchmark de Mercado:**
     - Relatório executivo consolidado em `product-ux-erp-analysis.md` com comparação competitiva frente a Conta Azul, Omie e TOTVS, proposta de nova arquitetura de informação e roadmap priorizado (P0 a P3).
  5. **Quality Gate e Backpressure 100% Verde:**
     - Suíte Flutter com 227 testes passando 100% verde.
     - 127 testes da API Laravel passando com 1.483 asserções no banco PostgreSQL real.
     - 13 testes de domínio financeiro PHP passando.
     - Dart format e Pint 100% limpos.
  6. **Diálogo Reutilizável de Double-Check (`ConfirmChangesDialog`):**
     - Criado em [`apps/mobile/lib/ui/confirm_changes_dialog.dart`](../../apps/mobile/lib/ui/confirm_changes_dialog.dart) com suporte a exibição de diff estruturado (`ChangeDifference`: label, oldValue com tachado e newValue em destaque).
     - Alerta visual dinâmico caso haja recálculo determinístico de parcelas em aberto.
     - Botões "Revisar" (cancela) e "Confirmar e salvar".
     - Integrado em:
       - `EditAgreementDialog` (Contas a Receber / Agreements no modal e tela de detalhes);
       - `PayableModal` (Contas a Pagar no modal desktop);
       - `PayableEditScreen` (Contas a Pagar na tela mobile).
  2. **Contas a Receber (Agreements) com Edição de Valor e Recálculo no Backend:**
     - Migration `2026_11_09_120000_add_cancelled_at_to_agreements.php` adicionando `cancelled_at`, `cancel_reason`, `edited_at` e atualizando `obligation_changes_subject_check` com subject `'agreement'`.
     - Action `ChangeAgreements` implementando `cancel` (com validação estrita de ausência de recebimentos ativos) e `edit` (descrição, categoria, valor total, número de parcelas e primeiro vencimento). Quando há alteração de valor ou parcelas, regenera deterministicamente o cronograma de parcelas via `InstallmentSchedule::generate` e audita em `obligation_changes`. Rejeita alteração de valor caso já haja parcelas recebidas (`422`).
     - Endpoints `PATCH /api/spaces/{space}/agreements/{agreement}` e `POST /api/spaces/{space}/agreements/{agreement}/cancel`.
     - `AgreementController::index` ocultando automaticamente contas canceladas das listas de abertos/vencidos e suportando filtro explícito `status=cancelled`.
  3. **Contas a Receber no Frontend (Web/Desktop e Mobile):**
     - `AgreementModal` e `AgreementScreen` com botões de ação "Editar conta" e "Cancelar conta a receber" para contas em aberto sem recebimento.
     - Diálogo de cancelamento com justificativa obrigatória e anulação contábil segura (sem tocar em saldos bancários).
     - Diálogo de edição completa `EditAgreementDialog` com suporte a:
       - Alteração de descrição e categoria (`income`).
       - Edição de valor (por parcela ou total) e número de parcelas.
       - Pré-visualização em tempo real das novas parcelas via `InstallmentSummaryCard`.
       - Alerta visual dinâmico avisando que as parcelas abertas serão recalculadas deterministicamente.
       - Double-check explícito "Deseja realmente salvar?" exibindo o comparativo de cada campo alterado.
     - Banner de status "Conta a receber cancelada" e bloqueio de novas baixas para títulos cancelados.
  4. **Paridade no Contas a Pagar (`PayableModal` Web/Desktop e Mobile):**
     - Inclusão dos botões "Editar conta a pagar" e "Cancelar conta a pagar" no cabeçalho do `PayableModal` executivo.
     - Suporte a cancelamento com justificativa e edição direta de descrição, credor, valor e data de vencimento.
     - Double-check de confirmação exibindo cada campo modificado antes de efetivar o update.
     - Banner de status cancelado e desativação de botão de pagamento para contas a pagar canceladas.
  5. **Quality Gate e Backpressure 100% Verde:**
     - `./scripts/check.sh --full` aprovado com ZERO erros.
     - Suíte Flutter com 226 testes passando 100% verde (incluindo testes de double-check em Contas a Pagar e Receber).
     - 127 testes de API Laravel passando com 1.483 asserções no banco PostgreSQL real `bigdevz_finance_test`.
     - 13 testes de domínio PHP passando.
     - Pint e Dart format 100% limpos.
- **Ambiente de Desenvolvimento Local:**
  - API Laravel 13 Docker ativa em `http://127.0.0.1:8000/api`.
  - PostgreSQL 18 Docker ativo em `127.0.0.1:5440`.
  - Frontend Flutter Web Server em `http://127.0.0.1:8085`.
- **Branch Ativa:** `feature/agenda-financeira-escalavel`.
- **Branch de Produção:** `main`.

---

## 3. Decisões Arquiteturais e Histórico Preservado

Todas as decisões técnicas e arquiteturais consolidadas nas etapas anteriores permanecem válidas e vinculantes:

1. **Decisão 0001 (Monólito Modular no Backend):** Laravel 13 estruturado em camadas coesas (Domínio puro, Actions específicas e Controllers/Resources REST).
2. **Decisão 0002 (Integridade Monetária Inegociável):** Dinheiro exato sem `float`. Strings decimais com 2 casas na interface/API, inteiros na menor unidade (centavos) no núcleo e limite de `999999999999.99`. Distribuição determinística de centavos e preservação do dia de referência.
3. **Decisão 0003 (Isolamento Multi-Espaço PF/PJ):** Chaves estrangeiras compostas `(id, space_id)` em todas as tabelas transacionais. No mobile, isolamento absoluto de árvore de widgets via `KeyedSubtree` para alternância de contexto sem vazamento de estado.
4. **Decisão 0004 (Estornos e Idempotência Persistida):** Tabela `IdempotentOperation` associada a advisory locks por usuário/espaço/operação. Estornos registrados via `ReceiptReversal` sem apagar histórico efetivado.
5. **Decisão 0005 (Gestão e Correção de Contas):** Edição e arquivamento de contas financeiras sem violar integridade de lançamentos pretéritos.
6. **Decisão 0006 (Contas a Pagar, Parcelas e Recorrências):** Módulo de contas a pagar, parcelas e recorrências (conforme `docs/project-guidelines.md`), com harness de acessibilidade em 375pt padronizado para insets reais.

> Detalhamento integral das causas raízes e auditorias históricas disponível em [`HANDOFF.md`](../../HANDOFF.md).

---

## 4. Alterações em Andamento e Working Tree

Inventário detalhado do escopo documental homologado para versionamento local:

| Arquivo | Tipo | Descrição e Finalidade |
| :--- | :--- | :--- |
| `.gitignore` | Modificado | Proteção de `.local/`, `docs/archive/`, DevTools, script local e capturas temporárias. |
| `AGENTS.md` | Modificado | Sanitização de links absolutos, regras autossuficientes e autorizações normativas. |
| `CONTRIBUTING.md` | Modificado | Guia comunitário (Fork, Branch, PR, CI) e nota sobre governança de agentes. |
| `HANDOFF.md` | Modificado | Sanitização de caminhos locais e assinatura Apple, preservando integridade histórica. |
| `README.md` | Modificado | Badge dinâmico oficial de CI, links para SECURITY/TRADEMARK e seção de Licença. |
| `docs/ai/AJUSTES-PARA-RETOMADA.md` | Modificado | Generalização de portas do host e alinhamento com diretrizes públicas. |
| `docs/ai/HANDOFF.md` | Modificado | Este documento canônico (links normalizados e estado operacional atualizado). |
| `docs/screenshots.md` | Modificado | Precisão terminológica separando apresentação visual de testes funcionais. |
| `SECURITY.md` | Novo | Política de divulgação responsável e canal seguro via GitHub Security Advisories. |
| `TRADEMARK.md` | Novo | Diretrizes de uso da marca BigDev.Z e do gorila em harmonia com a licença MIT. |

**Arquivos particulares protegidos preservados fora do commit:**
- `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (configurações locais de build/assinatura).
- `apps/mobile/ios/Runner/Info.plist` (ajustes locais de rede).
- `apps/mobile/integration_test/ux_evidences_test.dart` (teste local não rastreado).

---

## 5. Catálogo de Evidências Visuais e Demonstração Real (GOV-04)

- **Diretório Oficial de Capturas:** [`prints/`](../../prints/) (15 capturas oficiais ativas, geradas no simulador iPhone 17 Pro e harness 375pt).
- **Referência Histórica Local:** `design/screenshots/simulator_state.png` (captura técnica de design preservada exclusivamente no ambiente de trabalho local).
- **Regra de Plataforma:** **Validação em Android não convalida iOS; validação em iOS não convalida Android.**
- **Inventário de Evidências Oficiais:**
  - **Tema Escuro (Dark Mode - 402x874pt):**
    - `dark_01_resumo_pf.png`: Resumo financeiro PF no tema escuro.
    - `dark_02_resumo_pj.png`: Resumo financeiro PJ no tema escuro.
    - `dark_03_carteira_pf.png`: Carteira de contas PF no tema escuro.
    - `dark_04_carteira_pj.png`: Carteira de contas PJ no tema escuro.
    - `dark_05_novo_payable_pf.png`: Formulário de nova conta a pagar PF no tema escuro.
    - `dark_06_novo_payable_pj.png`: Formulário de nova conta a pagar PJ no tema escuro.
  - **Tema Claro (Light Mode - 402x874pt):**
    - `light_01_resumo_pf.png`: Resumo financeiro PF no tema claro.
    - `light_02_resumo_pj.png`: Resumo financeiro PJ no tema claro.
    - `light_03_carteira_pf.png`: Carteira de contas PF com dados estritamente de PF e cartão azul escuro.
    - `light_04_carteira_pj.png`: Carteira de contas PJ no tema claro.
    - `light_05_novo_payable_pf.png`: Formulário de nova conta a pagar PF no tema claro.
    - `light_06_novo_payable_pj.png`: Formulário de nova conta a pagar PJ no tema claro.
  - **Acessibilidade e Fontes Ampliadas (Harness 375pt):**
    - `a11y_375px_scale_150_formulario.png`: Formulário com texto ampliado em 150% (1.5x) sem sobreposição.
    - `a11y_375px_scale_150_seletor.png`: Seletor de contas/espaço com texto ampliado em 150%.
    - `a11y_375px_scale_200_scroll.png`: Comportamento de rolagem e legibilidade extrema com texto em 200% (2.0x).

---

## 6. Auditoria de QA, Testes e Verificação (25 Práticas)

Os comandos reais de verificação aprovados na última auditoria de consolidação:

1. **Testes de Domínio:** `make test-domain`
   - **Resultado:** 11 testes, 0 falhas (cálculo de centavos, bissextos, datas e tolerâncias).
2. **Testes de Integração e API:** `make test-api`
   - **Resultado:** 71 testes, 1.011 asserções aprovadas (PostgreSQL real `bigdevz_finance_test`, rollback, concorrência com subprocessos, estornos e idempotência).
3. **Smoke Tests:** `make smoke-api`
   - **Resultado:** 100% aprovado contra o container Docker da API.
4. **Padronização de Código PHP:** `make lint-api` (Laravel Pint)
   - **Resultado:** 100% de conformidade de estilo.
5. **Formatação Dart:** `dart format --output=none --set-exit-if-changed lib test integration_test`
   - **Resultado:** 75 arquivos formatados, 0 alterações pendentes.
6. **Análise Estática Dart:** `flutter analyze` em `apps/mobile/`
   - **Resultado:** `No issues found!`.
7. **Testes Unitários e Widgets:** `flutter test` em `apps/mobile/`
   - **Resultado:** 86 testes aprovados.

---

## 7. Governança Git, Soberania Humana e Segurança

- **Branch de Trabalho:** `dev`. Todo desenvolvimento ocorre exclusivamente nesta branch.
- **Branch de Produção:** `main`. Push direto é estritamente proibido. Integração realizada exclusivamente pelo mantenedor via Pull Request formal após aprovação completa de todos os checks da CI.
- **Soberania do Desenvolvedor Jeann Lucas:** Commits são preparados pelo agente mas criados e autorizados exclusivamente pelo Jeann. Proibido criar commits, tags ou branches autonomamente.
- **Segurança de Credenciais:** Proibido comitar `.env` real, tokens ou dados pessoais (PII). Variáveis de ambiente vivem exclusivamente em `.env` ignorado pelo Git, com templates em `.env.example`.
- **Deploy:** Nenhum deploy automático é realizado por agentes de IA.

---

## 8. Próximos Passos Imediatos e Retomada Multi-IA

Roteiro de continuidade operacional para **Google Antigravity** e **OpenAI Codex**:

1. **Proteção Rigorosa do Ambiente Live em Produção (`https://finance.bigdevz.com`):**
   - Com o BigDev.Z Finance publicado em produção com usuários ativos realizando testes reais, todo novo desenvolvimento DEVE operar sob isolamento estrito:
     - Criação de branches dedicadas a partir da `dev` (ex: `feature/clientes`, `feature/projetos`).
     - Zero intervenções manuais ou mutações descontroladas na base de produção da VPS.
     - Banco de dados local de testes (`bigdevz_finance_test`) estritamente descartável e isolado.
     - Quality gate determinístico (`scripts/check.sh --full`) obrigatório antes de qualquer solicitação de commit/merge.
2. **Início da Etapa 3 do Roadmap (Negócio & Clientes):**
   - Planejamento e especificação (L2 em `specs/clientes/`) para Gestão de Clientes, Contratos/Mensalidades recorrentes e Projetos por etapas.
3. **Soberania Git Inegociável:**
   - Nenhum commit, merge ou push ocorre sem autorização prévia, expressa e soberana do mantenedor Jeann Lucas.
4. **Atualização Contínua deste Documento:**
   - Manter as seções 2 e checkpoints históricos atualizados a cada novo ciclo de entrega.


## Registro de Homologação — Checkpoint FINANCE-QA-01 (15/10/2026)

- **Modo:** QA Nativo + Inspeção Visual + Auditoria Independente.
- **Branch Ativa:** `dev` (HEAD `0f49606bf5ee57ce29256209ac51991f992cef89`), staging vazio, nenhum commit ou push realizado.
- **Ambiente & Portas:** API Laravel e PostgreSQL mantidos na porta 8000 e 5440 via Docker Compose existente sem mutações de infraestrutura.
- **Execução Multiplataforma:**
  - **iOS:** Simulador `iPhone 17 Pro` (iOS 26.5), executando `generate_evidences_test.dart` e `inspection_test.dart` contra a API real.
  - **Android:** Emulador `emulator-5554` (`bigdevz_api36`, API 36 / Android 16), executando `inspection_test.dart` com túnel de rede e conectividade validada.
- **Suíte de Testes Automatizados:**
  - `apps/mobile/test/features/home_shell_test.dart`: 4 novos testes cobrindo alternância PF/PJ no HomeShell real, mudança dinâmica de tema (Azul Profundo ↔ Verde Esmeralda), integridade e ciclo de vida efêmero da privacidade do saldo.
  - `apps/mobile/test/features/summary_test.dart`: 11 testes cobrindo isolamento estrito de `spaceId`, descarte de respostas obsoletas, privacidade de valores monetários, recuperação de erro, pull-to-refresh e acessibilidade 150%/200% em 375pt.
  - **Total Flutter:** 101 testes unitários e de widgets aprovados (0 falhas).
  - **Análise Estática Dart:** `flutter analyze` com 0 issues (`No issues found!`).
  - **Domínio Financeiro PHP:** `make test-domain` com 11/11 testes aprovados (0 falhas).
- **Evidências Visuais Primárias:**
  - Diretório oficial preservado: `prints/` intacto sem mutações.
  - Novo diretório de evidências: `prints/qa-01/` com 15 capturas iOS e 13 capturas Android demonstrando o Dashboard modernizado nos modos claro/escuro para PF e PJ.
- **Auditoria Independente OpenAI Codex (CLI 0.160.0, `--sandbox read-only`):**
  - Parecer: **APROVADO COM RESSALVAS**.
- **Estado Operacional:** Pronto para decisão e homologação humana do mantenedor Jeann Lucas.

---

## Registro de Homologação — Checkpoint FINANCE-UX-01 (15/10/2026)

- **Missão:** Central de Configurações, Personalização de Aparência, Privacidade Financeira Compartilhada e Refinamento de UX.
- **Modo:** IMPLEMENTAÇÃO CONTROLADA + UX/UI + QA + AUDITORIA INDEPENDENTE.
- **Branch Ativa:** `dev` (HEAD `0f49606bf5ee57ce29256209ac51991f992cef89`), staging vazio, zero commits, zero pushes, zero deploys.
- **Arquitetura & Implementação:**
  1. `PreferencesController` (`apps/mobile/lib/features/settings/preferences_controller.dart`): controle de `ThemeMode` (`system`, `light`, `dark`), `hideValuesByDefault` e `obscureValues` volátil na sessão, persistido via `SessionStorage` de forma transparente e segura, com proteção `try/catch` contra falhas de storage.
  2. `SettingsScreen` (`apps/mobile/lib/features/settings/settings_screen.dart`): Central de Configurações acessível pelo menu "Conta" do `HomeShell`, com seções Aparência, Privacidade Financeira e Sobre o Aplicativo, acessibilidade para leitores de tela (`Semantics(selected: ..., inMutuallyExclusiveGroup: true)`) e suporte comprovado a texto ampliado a 200%.
  3. `ThemeMode` e Identidade Multi-Tenant: `Brightness` derivado da preferência global sem comprometer a identidade das cores dos espaços: PF = Azul Profundo (`#2459D4`), PJ = Verde Esmeralda (`#137A63`).
  4. Privacidade Financeira de Sessão: Máscara consistente (`R$ ••••••••`) no Dashboard (Master Card, cards secundários e totalizadores) e Carteira de Contas (`accounts_tab.dart` e `_AccountTile`), preservada durante a navegação entre abas e alternância de espaços PF/PJ.
  5. Ciclo de Vida do Logout e Expiração: Conexão no `bootstrap.dart` via listener de `SessionController` para resetar a privacidade para `hideValuesByDefault` estritamente quando `session.status == SessionStatus.signedOut` (logout confirmado ou expiração). O cancelamento do diálogo de logout preserva integralmente a privacidade da sessão ativa.
  6. Refinamentos de UX: Espaçamento vertical confortável (`const SizedBox(height: 12)`) após campos com `maxLength` em `PayableFormScreen` e indicadores limpos no carrossel de contas.
- **Suíte de Testes Automatizados (100% de Aprovação):**
  - `apps/mobile/test/features/preferences_test.dart`: 13 testes cobrindo a matriz A1-A12 e P1-P20, cancelamento de logout, expiração de sessão, resiliência de storage e semântica de acessibilidade.
  - `apps/mobile/test/features/home_shell_test.dart`: 4 testes atualizados validando persistência da privacidade através da navegação de abas e integridade dos atalhos rápidos.
  - **Total Flutter:** 114 testes aprovados (0 falhas).
  - **Análise Estática Dart:** `flutter analyze` com 0 issues (`No issues found!`).
  - **Domínio Financeiro PHP:** `make test-domain` com 11 testes aprovados (0 falhas).
- **Evidências Visuais Nativas Geradas (`prints/ux-01/`):**
  - `ux_01_settings_light.png`: Tela de Configurações no tema Claro.
  - `ux_02_settings_dark.png`: Tela de Configurações no tema Escuro.
  - `ux_03_dashboard_pf_hidden_balance.png`: Dashboard PF com saldo mascarado (`R$ ••••••••`).
  - `ux_04_accounts_pf_hidden_balance.png`: Carteira de Contas PF com saldos mascarados.
  - `ux_05_accounts_pj_hidden_balance.png`: Carteira de Contas PJ com saldos mascarados.
  - `ux_06_dashboard_pj_hidden_balance.png`: Dashboard PJ com saldos mascarados.
  - `ux_07_dashboard_pf_revealed_balance.png`: Dashboard PF com valores revelados e ícone semântico `view`.
- **Auditoria Independente OpenAI Codex CLI (0.160.0, `--sandbox read-only`):**
  - Parecer Inicial: REPROVADO (apontamento de reset precoce no cancelamento de saída).
  - Ajustes Executados: Remoção do reset antecipado, listener atômico em `SessionController`, `try/catch` de resiliência e semântica de rádio.
  - Parecer de Reavaliação Final: **APROVADO COM RESSALVAS** (confirmando resolução do defeito de privacidade, conexão efetiva de encerramento, e semântica de seleção).
- **Estado Final:** Concluído com sucesso. Aguardando revisão e autorização soberana do desenvolvedor Jeann Lucas para commit/versionamento.

---

## Registro de Homologação — Checkpoint FINANCE-UX-02 (15/10/2026)

- **Missão:** Refinamento Final de UX, Privacidade Financeira em Listagens de Consulta, Semântica Acessível e Homologação Android/iOS.
- **Modo:** IMPLEMENTAÇÃO CONTROLADA + QA + AUDITORIA INDEPENDENTE.
- **Branch Ativa:** `dev` (HEAD `0f49606bf5ee57ce29256209ac51991f992cef89`), staging vazio, zero commits, zero pushes, zero merges.
- **Arquitetura & Refinamentos Concluídos:**
  1. **Contraste Acessível no Tema Escuro (`settings_screen.dart`):** Substituído `Colors.black26` pelo valor semântico de alto contraste `theme.colorScheme.outline.withValues(alpha: 0.7)` no trailing do `_ThemeOptionTile`, garantindo distinção nítida dos indicadores desmarcados sem ofuscar o item ativo.
  2. **Acessibilidade e Semântica do Botão de Privacidade (`summary_tab.dart`):** Envolvido com `Semantics(button: true, label: obscureBalance ? 'Mostrar saldo' : 'Ocultar saldo')`, fornecendo anúncio correto para tecnologias assistivas (TalkBack/VoiceOver) alinhado aos ícones dinâmicos `AppIcons.view` e `AppIcons.viewOff`.
  3. **Privacidade Financeira em Listagens de Consulta:**
     - `agreements_tab.dart`: `AgreementCard` escuta `PreferencesController.obscureValues` e aplica máscara nos `MoneyText` principal e secundário, e sanitiza a string e o `semanticsLabel` do indicador de recebimento ('Recebido: ••••••' e 'Recebido da conta: oculto').
     - `payables_tab.dart`: `PayableCard` escuta `PreferencesController.obscureValues` e mascara os `MoneyText` de valor total, restante a pagar e pago líquido.
     - Preservação da conferência visual em formulários transacionais (`PayableFormScreen`, `ReceiptFormScreen`).
  4. **Exibição da Versão e Build do Aplicativo:** Novas constantes desacopladas `appVersion`, `appBuildNumber` e `appVersionLabel` em `config.dart`, alinhadas ao `pubspec.yaml` (`1.0.0+1`), exibidas dinamicamente na Central de Configurações sem sobrecarga de dependências desnecessárias.
  5. **Tema Automático (`ThemeMode.system`):** Homologado com acompanhamento dinâmico do brilho do sistema operacional.
- **Suíte de Testes Automatizados (100% de Aprovação):**
  - `apps/mobile/test/features/preferences_test.dart`: 15 testes aprovados (adicionados testes de versão real do app e mascaramento nas abas de A Receber e A Pagar).
  - Suíte completa do Flutter: **116 testes aprovados** (0 falhas).
  - Análise estática Dart: `flutter analyze` com **0 issues** (`No issues found!`).
  - Formatação Dart: `dart format --output=none --set-exit-if-changed` com **81 arquivos 100% conformes**.
  - Domínio Financeiro PHP: `make test-domain` com **11/11 testes aprovados** (0 falhas).
- **Evidências Visuais Nativas Geradas (`prints/ux-02/` - 20 Capturas Reais):**
  - **10 capturas iOS (iPhone 17 Pro):**
    - `ux_01_settings_light.png`: Configurações no tema Claro com versão e build reais.
    - `ux_02_settings_dark.png`: Configurações no tema Escuro com contraste corrigido no radio button.
    - `ux_02b_settings_auto_light.png`: Configurações com tema Automático ativo.
    - `ux_03_dashboard_pf_hidden_balance.png`: Dashboard PF com valores mascarados e botão semântico.
    - `ux_04_agreements_pf_hidden.png`: Aba A Receber com `AgreementCard` mascarado.
    - `ux_05_payables_pf_hidden.png`: Aba A Pagar com `PayableCard` mascarado.
    - `ux_06_accounts_pf_hidden_balance.png`: Carteira de Contas PF com saldos mascarados.
    - `ux_07_accounts_pj_hidden_balance.png`: Carteira de Contas PJ com privacidade preservada.
    - `ux_08_dashboard_pj_hidden_balance.png`: Dashboard PJ com valores mascarados.
    - `ux_09_dashboard_pf_revealed_balance.png`: Dashboard PF com valores revelados e ícone `viewOff`.
  - **10 capturas Android (Pixel / API 36):**
    - `android_ux_01_settings_light.png` a `android_ux_09_dashboard_pf_revealed_balance.png`: Homologação nativa idêntica no ecossistema Android Material 3.
- **Auditoria Independente OpenAI Codex CLI (0.160.0, `--sandbox read-only`):**
  - Parecer: **APROVADO COM RESSALVAS**.
  - Confirmação de integridade dos 20 PNGs, 11 testes PHP, governança Git estrita e conformidade das regras financeiras e sementes de espaço PF (`#2459D4`) e PJ (`#137A63`).
  - Ressalva anotada: execução Flutter bloqueada no ambiente sandbox Codex por cache do SDK somente leitura e recomendação de futura sincronização automatizada dos metadados de versão com o binário instalado.
- **Estado Operacional:** `VALIDADO TECNICAMENTE` / Homologação nativa concluída em Android e iOS.

---

## 5. Checkpoint FINANCE-COMMIT-01 (16/10/2026) — Auditoria de Versionamento e Consolidação Git

- **Objetivo**: Auditoria exaustiva de alterações, exclusão de segredos e configurações locais de ambiente, validação técnica pré-commit e criação do commit local na branch `dev`.
- **Branch**: `dev` (após o commit `0f49606bf5ee57ce29256209ac51991f992cef89`).
- **Governança Git Estrita**:
  - `git push`: NÃO EXECUTADO (proibido).
  - `git merge`: NÃO EXECUTADO (proibido).
  - Branch `main`: 100% INTOCADA.
  - Staging seletivo por arquivo: `git add <arquivo>` (PROIBIDO `git add .` ou `git add -A`).
- **Validação Técnica Executada**:
  - `dart format --output=none --set-exit-if-changed`: 81 arquivos verificados, 0 alterações pendentes.
  - `flutter analyze`: Resolvido sem issues (0 warnings/erros).
  - `flutter test`: 116 de 116 testes aprovados (100% verde).
  - `make test-domain`: 11 de 11 testes de domínio aprovados (0 falhas).
  - `git diff --check`: 0 erros de whitespace.
- **Auditoria Independente OpenAI Codex CLI (`--sandbox read-only`)**:
  - Parecer: **APROVADO COM RESSALVAS** para a proposta de commit local na `dev`.
  - Ausência de segredos reais, tokens ou chaves privadas.
  - Preservação estrita das configurações locais particulares de ambiente:
    - `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (Team ID local do mantenedor).
    - `apps/mobile/ios/Runner/Info.plist` (reordenação interna do Xcode).
    - `apps/mobile/devtools_options.yaml` (configurações locais de perfilamento).
    - `scripts/run-mobile.sh` (atalho local de simulação com UUID do device).
    - `apps/mobile/integration_test/ux_evidences_test.dart` (script dependente do `screenshot_server.py` local).
    - Diretórios temporários de capturas de tela dos checkpoints (`prints/qa-01/`, `prints/ux-01/`, `prints/ux-02/`, `design/screenshots/`).
- **Próximos Passos**: Submissão ao portão formal pré-push no checkpoint `FINANCE-PUBLISH-01`.

---

## 6. Checkpoint FINANCE-PUBLISH-01 (16/10/2026) — Auditoria Pré-Publicação e Bloqueio de Segurança

- **Objetivo**: Auditoria de portão pré-push antes de publicar na branch remota `origin/dev`.
- **Diagnóstico de Segurança Realizado**:
  - Inspeção profunda de `PreferencesController.load()` e `SessionStorage`.
  - Descoberta de vulnerabilidade P0: bloco `catch (_)` em erro de leitura do armazenamento seguro redefinia `_obscureValues = false`, revelando valores financeiros na tela contrariando a escolha do usuário de ocultar saldos.
  - Auditoria independente OpenAI Codex CLI (`--sandbox read-only`): Parecer **BLOQUEAR PUSH**.
- **Decisão Operacional**: Portão de segurança pré-push acionado com sucesso. Push para `origin/dev` **BLOQUEADO**. Nenhum dado foi publicado no GitHub e a CI remota permaneceu não acionada (`NOT_TRIGGERED`).
- **Encaminhamento**: Abertura imediata do checkpoint corretivo de segurança `FINANCE-SEC-01`.

---

## 7. Checkpoint FINANCE-SEC-01 (16/10/2026) — Correção de Segurança da Privacidade Financeira (P0)

- **Objetivo**: Eliminação definitiva da vulnerabilidade de exposição financeira inesperada e proteção contra flicker no boot.
- **Correções Implementadas**:
  1. **Política Fail-Closed:** `_obscureValues` inicia como `true` por padrão no `PreferencesController` e sob qualquer erro de leitura (`catch`), valor inválido ou corrupção no storage, mantendo os valores financeiros mascarados por precaução.
  2. **Desacoplamento de Erros:** Leitura de `themeModeKey` e `hideByDefaultKey` isoladas em blocos `try/catch` independentes. Falha no carregamento de tema não afeta nem bloqueia a privacidade financeira.
  3. **Proteção Anti-Flicker:** Durante carregamento assíncrono atrasado do storage (`isLoaded == false`), a interface já renderiza mascarada, eliminando vazamento transitório de saldos reais.
  4. **Padrão Aprovado Preservado:** Ausência comprovada de chave (`rawHide == null`) e escolhas explícitas (`'true'` ou `'false'`) continuam funcionando com total fidelidade.
  5. **Retificação do HANDOFF Histórico:** O arquivo `HANDOFF.md` da raiz teve seu texto histórico legítimo original de `0f49606` integralmente restaurado, mantendo a canonicidade ativa exclusivamente em `docs/ai/HANDOFF.md`.
- **Validação Técnica Executada**:
  - `dart format`: 100% conforme.
  - `flutter analyze`: 0 issues.
  - `flutter test`: **123 testes aprovados** (116 anteriores + 7 novos testes de segurança `SEC-01` a `SEC-08` + teste anti-flicker dinâmico com `Completer`).
  - `php apps/api/tests/domain.php`: 11/11 testes aprovados (0 falhas).
  - `git diff --check`: 0 erros de whitespace.
- **Commit Corretivo Criado**: `3cbf8566a212a125d00e19b5492455935bea691a` (`fix(security): proteger privacidade financeira em falhas de storage`).

---

## 8. Checkpoint FINANCE-SEC-02 (16/10/2026) — Persistência Segura de Preferências, Integridade de Estado e Correção de Segurança

- **Objetivo**: Corrigir a vulnerabilidade de persistência e integridade de estado identificada na auditoria Codex: eliminação do silenciamento em `catch (_)` na gravação de preferências em `PreferencesController.setHideValuesByDefault` e na tela `SettingsScreen`.
- **Causa Raiz Corrigida**:
  - Anteriormente, o método `setHideValuesByDefault` atualizava a variável `_hideValuesByDefault = hide` antes de gravar no storage e silenciava a exceção de escrita no `catch (_)`. Como consequência, em caso de erro de gravação em disco/keychain, a UI refletia o switch como persistido sem que o valor tivesse sido de fato salvo, gerando reversão inesperada de privacidade após reinicialização do app.
- **Correções Implementadas**:
  1. **Contrato de Persistência Confiável (`PreferencesController`):**
     - `setHideValuesByDefault` agora retorna `Future<bool>`.
     - Implementado lock contra concorrência e toques repetidos via flag `_isSavingPrivacy` e getter público `isSavingPrivacy`.
     - A variável de estado persistido `_hideValuesByDefault` somente é atualizada após a confirmação bem-sucedida de escrita no storage (`storage.write`).
     - Em caso de falha de escrita (`catch`), `_hideValuesByDefault` NÃO é alterado (mantendo honestidade quanto ao dado em disco). Se o usuário estava tentando ativar privacidade (`hide == true`), a sessão ativa adota política fail-closed preventiva (`_obscureValues = true`) e retorna `false`.
     - `setThemeMode` também retorna `Future<bool>`, mantendo a escolha visual na sessão ativa sem causar flicker na UI.
  2. **Experiência de Usuário e Acessibilidade (`SettingsScreen`):**
     - O `SwitchListTile` de privacidade é desabilitado (`onChanged: preferences.isSavingPrivacy ? null : ...`) durante a persistência assíncrona para prevenir concorrência.
     - Subtítulo dinâmico indica `'Salvando preferência...'` durante a escrita.
     - Em caso de falha de persistência, um `SnackBar` acessível e informativo é exibido com a mensagem `'Não foi possível salvar a preferência de privacidade.'` e um botão de ação `SnackBarAction` (`'Tentar novamente'`) para recuperação transparente.
  3. **Nova Matriz de Testes de Segurança (`SEC-W01` a `SEC-W10`):**
     - Testes unitários com storage falho (`_WriteFaultyStorage`) validando que falha de escrita retorna `false`, mantém `_hideValuesByDefault` inalterado e preserva `_obscureValues = true`.
     - Teste de novo controller instanciado após falha comprovando que o storage simulado reteve o valor original sem falso estado.
     - Teste cobrindo falha ao desativar preferência previamente true mantendo o valor persistido.
     - Teste de bloqueio de concorrência com escrita lenta (`_SlowStorage`).
     - Testes de widget cobrindo desabilitação do switch durante gravação, exibição do SnackBar de erro e recuperação bem-sucedida via ação "Tentar novamente" com suporte a múltiplos retries.
- **Validação Técnica Executada**:
  - `dart format lib test`: 100% conforme.
  - `flutter analyze`: 0 issues (No issues found).
  - `flutter test`: **132 testes aprovados** (100% verde em todas as suítes mobile).
  - `php apps/api/tests/domain.php`: 11/11 testes aprovados (0 falhas).
  - `git diff --check`: 0 erros de whitespace.
- **Parecer Codex**: APROVADO COM RESSALVAS (ressalvas atendidas integralmente antes da criação do commit).
- **Próximos Passos**: Criação do commit local na branch `dev` com a mensagem `fix(security): garantir persistencia segura da privacidade`.

---

## 9. Checkpoint FINANCE-RETOMADA-01 (17/10/2026) — Alinhamento à Governança Global, Spec Permanente e Quality Gate

- **Objetivo**: Retomada do projeto com base na governança unificada (`~/AGENTS.md`), auditoria de integridade monetária, verificação de isolamento multi-tenant (prevenção de IDOR), criação da spec permanente com critérios de aceite numerados e execução do script determinístico de validação única (`scripts/check.sh`).
- **Diagnóstico e Auditorias Realizadas**:
  1. **Integridade Monetária e Proibição de Float:** Confirmado que a aplicação não utiliza `float` ou `double` para cálculos financeiros (`Money.php`, `money.dart`, migrations `BIGINT` com restrições `CHECK` entre 0 e `99999999999999`). Juros, multas e conciliação seguem rigorosamente a aritmética de centavos inteiros e marco temporal de abertura da conta.
  2. **Isolamento Multi-Tenant e Prevenção de IDOR:** O modelo multi-tenant é baseado na entidade `Space` (`space_id`), com separação rígida entre PF e PJ. Toda consulta e mutação injeta obrigatoriamente o identificador derivado do usuário autenticado (`$request->user()->spaces()->findOrFail($spaceId)`). Acesso a espaços ou recursos alheios resulta em 404 imediato (sem vazar metadados). Chaves estrangeiras compostas `(id, space_id)` no PostgreSQL blindam a integridade no banco.
  3. **Spec Permanente Criada (`specs/financeiro/financeiro.md`):** Regras de negócio formalizadas com critérios de aceite numerados de `AC-FIN-001` a `AC-FIN-016` cobrindo precisão monetária, cronogramas, juros/multas/conciliação, isolamento multi-tenant, saldo disponível e concorrência/idempotência.
  4. **Quality Gate Unificado (`scripts/check.sh`):** Implementado o script determinístico "O Primeiro Não da Máquina" que executa análise de tipagem/estática, linters e toda a suíte de testes (11 testes PHP de domínio, 132 testes Flutter, Pint e Dart format).
- **Validação Técnica Executada (`bash scripts/check.sh`):**
  - Domínio Financeiro PHP: 11/11 testes aprovados (0 falhas).
  - Análise Estática Flutter: `No issues found!`.
  - Laravel Pint: `passed`.
  - Formatação Dart: 81 arquivos verificados, 0 alterações pendentes.
  - Testes Mobile Flutter: 132/132 testes aprovados (100% verde).
- **Estado Operacional:** `VALIDADO TECNICAMENTE` / `AGUARDANDO_APROVACAO`. Pronto para inspeção e aprovação do desenvolvedor Jeann Lucas.

---

## 10. Checkpoint FINANCE-FIN-02 — Fase B (18/10/2026) — Correções de Integridade Financeira, Agregados Exatos e Quality Gate

- **Objetivo**: Implementação controlada dos achados de integridade financeira identificados na auditoria FINANCE-FIN-01 e fechados arquiteturalmente no FINANCE-FIN-02.A2 sob a Opção 1 (valores individuais limitados a R$ 999 bilhões; agregados exatos sem float até inteiros de 64 bits).
- **Modo**: IMPLEMENTAÇÃO CONTROLADA LOCAL, sob autorização humana explícita. Sem staging, commit ou push.
- **Branch Ativa**: `dev` (HEAD `58cc1c9d7bf65447df68d09c0c5de999efe257d2`).
- **Arquivos Particulares Protegidos**: Intactos e rigorosamente preservados fora do escopo (`project.pbxproj`, `Info.plist`, `ux_evidences_test.dart`, `HANDOFF.md` raiz).

### Correções Implementadas

1. **A1 — Integridade dos Estornos e Correções de Saldo (`ReversePayment.php`, `ReverseReceipt.php`):**
   - Em `ReversePayment::handle`, adicionada validação do saldo líquido resultante na conta original sob lock pessimista antes de qualquer mutação contábil (`resulting > Money::MAX_CENTS || resulting < -Money::MAX_CENTS`).
   - Em `ReverseReceipt::handle` e `validateReplacement`, adicionadas verificações de limites bidirecionais tanto na conta original quanto na conta substituta.
   - Ambas as ações lançam `ValidationException::withMessages(['amount' => 'O saldo da conta ultrapassaria o limite suportado.'])` com rollback transacional automático e gravação do estado `rejected` na chave de idempotência com replay determinístico (HTTP 422).
2. **A2 — Limite Inferior no Ajuste de Saldo de Abertura (`AdjustAccountOpening.php`):**
   - A validação de saldo resultante pós-ajuste (`openingCents + movements`) tornou-se estritamente bidirecional (`> Money::MAX_CENTS || < -Money::MAX_CENTS`), impedindo subfluxo contábil abaixo do piso.
3. **A3 — Agregados Monetários Exatos e Sem Float (`Money.php`, `SpaceController.php`, `PayableController.php`, `CreatePayable.php`, `money.dart`):**
   - Implementado `Money::formatAggregate(int|string $cents): string` no domínio PHP com formatação aritmética inteira pura em 64 bits (`PHP_INT_MAX` = ~92 quadrilhões de reais), eliminando o risco de `InvalidArgumentException` / HTTP 500 em dashboards e relatórios consolidados.
   - Atualizados `SpaceController::summary` (`balance`, `received_total`, `receivable_remaining`, `open_total`, `overdue_total`, `due_next_30_days_total`, `paid_total`), `PayableController::preview` (`past_total`, `total`) e `CreatePayable::createRecurrence` (mensagem de confirmação de vencidos).
   - No Flutter (`money.dart`), ampliado o regex de API de `[0-9]{0,11}` para `[0-9]*` com controle estrito contra overflow de 64 bits (`92233720368547758.07`). Adicionado `Money.parseAggregate`. Entradas de usuário (`Money.fromInput` e `MoneyInputFormatter`) mantêm restrição estrita a `maxCents = 99999999999999`.
4. **A4 — Eliminação de Falso PASS no Quality Gate (`scripts/check.sh`):**
   - Implementado contrato com modos `--fast` e `--full` (padrão sem argumentos).
   - O modo `--full` realiza sondagem ativa PDO contra o banco PostgreSQL de testes (`bigdevz_finance_test` na porta 5440) sem expor credenciais no script.
   - Caso o banco esteja inacessível ou o ambiente não seja homologado, o script encerra imediatamente com exit code `2`, bloqueando o gate. Exit code `0` é retornado apenas sob aprovação integral de todos os testes.
5. **Sincronização da Especificação Permanente (`specs/financeiro/financeiro.md`):**
   - Atualizados `AC-FIN-001` (double permitido exclusivamente em tokens de layout Flutter), `AC-FIN-004` (diferenciação explícita entre limite individual `MAX_CENTS` e agregados exatos int64), `AC-FIN-007` (juros/multas classificados como especificados mas não implementados no roadmap futuro) e `AC-FIN-015` (detalhamento de replay de sucesso 200, replay de rejeição 422 e operações sem idempotência no backend).

### Testes Automatizados e Evidências

- **Domínio Financeiro PHP (`apps/api/tests/domain.php`):** 13 testes aprovados (inclui `formatAggregate` com canonicalização de zeros à esquerda e `Money::sum` imune a `bcscale` global), 0 falhas.
- **Testes Flutter Mobile (`apps/mobile/test`):** 133 testes aprovados (leitura de agregados e roundtrip nos extremos int64 com remainder e divisão inteira segura), 0 falhas.
- **Análise Estática Dart (`flutter analyze`):** 0 issues (`No issues found!`).
- **Laravel Pint (`vendor/bin/pint --test`):** 100% conforme.
- **Testes de Integração API Laravel em PostgreSQL Real (`php artisan test`):** 74 testes aprovados (3 novos testes de regressão: `test_payment_reversal_is_rejected_if_account_balance_would_exceed_max_cents`, `test_receipt_reversal_is_rejected_if_account_balance_would_underflow_max_cents`, `test_opening_adjustment_is_rejected_if_resulting_balance_would_underflow_max_cents`), 1044 asserções, 0 falhas.
- **Quality Gate FAST (`bash scripts/check.sh --fast`):** Aprovado (código 0).
- **Quality Gate FULL (`bash scripts/check.sh --full`):** Aprovado (código 0), com validação da conexão efetiva no runtime do framework (`127.0.0.1:5440/bigdevz_finance_test`).
- **Auditoria Independente OpenAI Codex CLI (`codex exec -s read-only`):** Executada com sucesso; todas as observações técnicas (scale 0 em bcadd, remainder/abs em Dart int64, canonicalização decimal e injeção forçada de conexão no test runner) foram refinadas e validadas.
- **Estado Operacional:** `VALIDADO TECNICAMENTE` / `AGUARDANDO_APROVACAO`. Pronto para inspeção e homologação humana soberana do desenvolvedor Jeann Lucas.

---

## 11. Checkpoint FINANCE-FIN-02.D (18/10/2026) — Saneamento de Bloqueadores, Segurança do PostgreSQL e Homologação do Commit Gate

- **Objetivo**: Saneamento completo dos 4 apontamentos técnicos identificados no Commit Gate (P0: blindagem da conexão efetiva de testes; P1: declaração formal de `ext-bcmath` no Composer; P1: testes HTTP dedicados de integração do Dashboard com agregação > MAX_CENTS; P1: reconciliação de `AC-FIN-015` com a arquitetura real de idempotência) e adição de testes de fronteira A1/A2.
- **Modo**: IMPLEMENTAÇÃO CONTROLADA LOCAL, sob autorização humana explícita para o Portão 2. Sem staging, commit ou push.
- **Branch Ativa**: `dev` (HEAD `58cc1c9d7bf65447df68d09c0c5de999efe257d2`).
- **Arquivos Particulares Protegidos**: Intactos e rigorosamente preservados fora do escopo (`project.pbxproj`, `Info.plist`, `ux_evidences_test.dart`, `HANDOFF.md` raiz).

### Correções Implementadas

1. **P0 — Blindagem da Conexão Efetiva de Testes (`phpunit.xml`, `TestCase.php`, `scripts/check.sh`):**
   - Em `phpunit.xml`, adicionado `force="true"` nas variáveis de conexão (`DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DB_URL`), impedindo sobreposição por variáveis ambientais do shell.
   - Em `TestCase.php`, implementada validação restrita no `setUpTraits()` antes de qualquer migrate ou transação:
     - Validação estrita do driver `pgsql` e pares autorizados `('127.0.0.1:5440'`, `'localhost:5440'` no host, e exclusivamente `'postgres:5432'` dentro do container Docker) para o banco `bigdevz_finance_test`.
     - Consulta ativa direta ao PDO de escrita: `$writePdo->query('SELECT current_database()')->fetchColumn()`, rejeitando qualquer conexão divergente com `RuntimeException`.
   - Em `scripts/check.sh`, validação dinâmica a partir de `phpunit.xml` e teste direto no write PDO antes da execução da suíte de testes.
2. **P1 — Declaração Formal da Extensão BCMath (`composer.json`, `composer.lock`):**
   - Adicionada dependência `"ext-bcmath": "*"` na seção `"require"` de `apps/api/composer.json`.
   - Sincronizados os metadados do `apps/api/composer.lock` estritamente via `composer update --lock --no-install --no-scripts --no-plugins`, preservando 100% das versões de pacotes instalados.
   - Validado com `composer check-platform-reqs` (`ext-bcmath: success`).
3. **P1 — Testes HTTP de Integração do Dashboard (`apps/api/tests/Feature/SpaceSummaryTest.php`):**
   - Criado arquivo de teste dedicado para o contrato `GET /api/spaces/{space}/summary` cobrindo rigorosamente os 7 cenários obrigatórios (T-01 a T-07):
     - **T-01:** Duas contas de R$ 600 bilhões somando R$ 1,2 trilhão exato (`"1200000000000.00"`), sem float e sem erro 500.
     - **T-02:** Soma monetária regular dentro de MAX_CENTS (`"1500.00"`).
     - **T-03:** Agregado negativo válido após pagamentos superiores à abertura (`"-200.00"`).
     - **T-04:** Multi-tenant estrito: 404 para Space de outro usuário sem vazar dados; segregação total entre PF e PJ do mesmo usuário.
     - **T-05:** Espaço vazio sem contas retorna `"0.00"` e contagens zeradas.
     - **T-06:** Duas contas no limite individual exato MAX_CENTS (`999999999999.99` cada) somando exatamente 2 x MAX_CENTS (`"1999999999999.98"`).
     - **T-07:** Resposta JSON preserva strings decimais canônicas com ponto e exatamente duas casas decimais em todos os totalizadores com valores não-zero e assert matemático exato (`balance`: `"850.00"`, `received_total`: `"150.00"`, `receivable_remaining`: `"350.00"`, `open_total`: `"700.00"`, `overdue_total`: `"200.00"`, `due_next_30_days_total`: `"500.00"`, `paid_total`: `"300.00"`).
4. **P1 — Reconciliação Textual de Idempotência (`specs/financeiro/financeiro.md`):**
   - Reconciliado `AC-FIN-015`: unicidade real no banco por `UNIQUE(space_id, key)`; distinção precisa entre validação sintática do request com chave válida (que persiste a chave como `rejected` com erros e devolve 422 em replay ou 409 em alteração) versus chave ausente/malformada (que é rejeitada preliminarmente sem persistência de chave); replay de sucesso responde `HTTP 200 OK` com `replayed: true` resserializando recursos atuais; `HTTP 409 Conflict` em caso de fingerprint divergente.
5. **Testes de Fronteira Adicionais (A1 e A2) com Asserções de Persistência no Banco:**
   - `PayablesTest.php`: Adicionado `test_payment_reversal_boundary_at_exact_max_cents_and_one_cent_above`, conferindo saldo persistido exato no teto e ausência de mutação/estorno na rejeição por 1 centavo.
   - `ReceiptReversalTest.php`: Adicionado `test_receipt_reversal_boundary_at_exact_negative_max_cents_and_one_cent_below`, conferindo saldo persistido exato no piso e integridade na tabela `receipt_reversals`.
   - `AccountManagementTest.php`: Adicionado `test_opening_adjustment_boundary_at_exact_max_cents_and_one_cent_above`, conferindo persistência e histórico de `account_opening_adjustments`.

### Resultados das Suítes Automatizadas
- **Domínio Financeiro PHP (`apps/api/tests/domain.php`):** 13 testes aprovados (0 falhas).
- **Testes Flutter Mobile (`apps/mobile/test`):** 133 testes aprovados (0 falhas).
- **Análise Estática Dart (`flutter analyze`):** 0 issues (`No issues found!`).
- **Laravel Pint (`vendor/bin/pint --test`):** 100% conforme.
- **Testes de Integração API Laravel em PostgreSQL Real (`php artisan test`):** 84 testes aprovados (inclui os 7 testes de `SpaceSummaryTest` e os 3 novos testes de fronteira com asserções de persistência), 1.139 asserções, 0 falhas.
- **Quality Gate FAST (`bash scripts/check.sh --fast`):** Aprovado (código 0).
- **Quality Gate FULL (`bash scripts/check.sh --full`):** Aprovado (código 0).
- **Auditoria Independente OpenAI Codex CLI (`codex exec -s read-only`):** **APROVADO** em todos os 5 critérios técnicos avaliados (P0: APROVADO; P1 bcmath: APROVADO; P1 dashboard: APROVADO; P1 spec: APROVADO; Fronteiras A1/A2: APROVADO).
- **Estado Operacional:** `HOMOLOGADO LOCALMENTE` / `AGUARDANDO_HOMOLOGACAO_MANUTENCAO`. Zero commits, zero pushes, área de staging limpa.

---

## 12. Ciclo FINANCE-MOB-01.B (B.1 a B.4-E) e Checkpoints Documentais B.5 a B.5-B — Acessibilidade Responsiva, Privacidade Semântica, Homologação na CI e Retificação Documental

- **Objetivo**: Resolução completa dos problemas de overflow em telas compactas (largura ensaiada de 320pt) e escalas ampliadas de acessibilidade (150% e 200%) no app Flutter; implementação de semântica acessível em cartões de contas financeiras com exclusão de nós internos ao ocultar saldos; catálogo de 76 evidências visuais locais cruzadas (Android e iOS); auditoria e recuperação de incidente de restauração não autorizada de arquivos Apple; auditoria estrita pré-push e publicação controlada de commit único para `origin/dev`; homologação dos jobs `api` e `mobile` na CI remota do GitHub Actions; e saneamento/retificação documental rigorosa.
- **Modo**: Ciclo de acessibilidade, testes de widget, auditorias pré-push com portões humanos, verificação de CI remota e retificação documental pré-commit.
- **Branch Ativa**: `dev` (HEAD local e publicado: `da8545fdfef934c91c0ca764023043bf80a040e0`, parent: `2a379f8b668440dce100873b2900bbaf8119151d`).
- **Branch de Produção**: `origin/main` (`a9e6e8b...`); branch local `main` (`42a3e39...`, intocada e preservada).

### Rastreabilidade Cronológica e Individualizada dos Checkpoints

| Checkpoint | Escopo / Operação Técnica | Evidência / Artefato Principal | Governança / Autorização | Status |
|---|---|---|---|---|
| **FINANCE-MOB-01.B.1** | Diagnóstico inicial READ-ONLY: identificação de capturas inválidas, overflows de texto em 150% e 200% em acordos e despesas, e identificação de risco de vazamento de saldo via acessibilidade semântica. | Capturas BEFORE em `prints/finance-mob-01/ios/` (`ios_iphone17e_mob-b1_agreements_overflow_200.png` e `ios_iphone17e_mob-b1_payables_overflow_200.png`). | Autorizado em sessão de diagnóstico | Homologado |
| **FINANCE-MOB-01.B.2 (Portão A)** | Planejamento técnico: especificação das correções de layout e isolamento do manifesto restrito de exatamente 7 arquivos Flutter. | Plano de execução aprovado sem alterações de código. | Portão A de Planejamento aprovado | Homologado |
| **FINANCE-MOB-01.B.2 (Portão B)** | Implementação controlada de código: reflow adaptativo com `Wrap` nas abas Contas, A receber e A pagar; clamp de carrossel em Contas; semântica com `excludeSemantics: true` e rótulo dinâmico em `AccountCard`; expansão de testes de 133 para 162. | 7 arquivos Flutter modificados; suíte com 162 testes aprovados localmente; ensaios em Pixel 8 e iPhone 17/17e. | Portão B de Implementação aprovado | Homologado |
| **FINANCE-MOB-01.B.3** | Auditoria final pré-commit: revisão detalhada do diff dos 7 arquivos, confirmação dos 162 testes locais, conferência da privacidade semântica, ressalvas de acessibilidade WCAG e parecer OpenAI Codex CLI read-only. Sem novas alterações de código. | Relatório de auditoria pré-commit; nenhum código modificado. | Portão de Auditoria aprovado | Homologado |
| **FINANCE-MOB-01.B.4-A** | Auditoria de incidente de governança envolvendo restauração não autorizada dos arquivos Apple locais por `git checkout`. Investigação read-only do Step 860, identificação do diff anterior no Step 859, análise dos efeitos sobre `project.pbxproj` e `Info.plist` e elaboração do plano de recuperação. Nenhuma recuperação executada neste checkpoint. | Relatório de auditoria de incidente em modo read-only; plano de recuperação aprovado. | Portão de auditoria de incidente | Homologado |
| **FINANCE-MOB-01.B.4-B** | Preparação, autorização humana e execução da recuperação controlada dos dois arquivos Apple a partir do patch original documentado no Step 859. Aplicação validada, `plutil -lint` aprovado, alterações locais do mantenedor restauradas, sete arquivos Flutter preservados, staging vazio e auditoria Codex favorável. | Arquivos Apple recuperados e validados (`plutil -lint: OK`); staging vazio. | Autorização formal de recuperação concedida | Homologado |
| **FINANCE-MOB-01.B.4-C** | Commit seletivo contendo exclusivamente os 7 arquivos Flutter homologados (`da8545fdfef934c91c0ca764023043bf80a040e0`). | Commit local `da8545f` criado com staging limpo; arquivos Apple e prints preservados. | Autorização de commit exclusivo concedida | Homologado |
| **FINANCE-MOB-01.B.4-D** | Auditoria pré-push em modo read-only: conferência de fast-forward limpo, staging vazio e inspeção de fluxos em `.github/workflows/ci.yml`. | Relatório de auditoria pré-push e verificação de integridade remota. | Portão humano pré-push | Aprovado |
| **FINANCE-MOB-01.B.4-E** | Execução de push único para `origin/dev` e homologação da CI GitHub Actions (Run ID `39365113034`). | `git push origin dev:dev`; CI #23 verde em ambos os jobs (`api` e `mobile`). | Autorização prévia soberana concedida | Homologado |
| **FINANCE-DOC-01.B.5** | Consolidação documental inicial nos três arquivos autorizados (`docs/ai/HANDOFF.md`, `README.md`, `ROADMAP.md`). | Diffs documentais elaborados e auditados em modo read-only. | Autorização condicional concedida | Concluído |
| **FINANCE-DOC-01.B.5-A** | Saneamento documental: distinção estrita dos catálogos de capturas, precisão técnica de Semantics e validação documental. | Diffs saneados; staging vazio; sem commit/push. | Autorização condicional concedida | Concluído |
| **FINANCE-DOC-01.B.5-B** | Retificação final da cronologia B.4-A/B.4-B, comprovação estrita do comando `git checkout` e gate de commit documental. | Diffs finais retificados; staging vazio; sem commit/push. | Em execução sob autorização humana | Em aprovação |

### Arquivos Homologados no Commit de Código Publicado (`da8545f`)
Exatamente 7 arquivos Flutter (4 em `lib` e 3 em `test`), sem arquivos de configuração ou evidências:
1. `apps/mobile/lib/features/accounts/account_card.dart`
2. `apps/mobile/lib/features/accounts/accounts_tab.dart`
3. `apps/mobile/lib/features/agreements/agreements_tab.dart`
4. `apps/mobile/lib/features/payables/payables_tab.dart`
5. `apps/mobile/test/features/accounts_test.dart`
6. `apps/mobile/test/features/agreements_tab_test.dart`
7. `apps/mobile/test/features/payables_test.dart`

### Detalhamento das Alterações Técnicas no Mobile

1. **Cartão de Contas e Privacidade Semântica (`account_card.dart`):**
   - Implementação de rótulo semântico condicional no nó raiz do cartão:
     `final semanticLabel = obscureBalance ? 'Conta ${account.name}, saldo oculto' : 'Conta ${account.name}, saldo ${account.balance.brl}';`
   - Configuração de `Semantics(label: semanticLabel, button: onTap != null, onTap: onTap, excludeSemantics: true, child: ...)`. A propriedade `excludeSemantics: true` poda nativamente todos os nós semânticos descendentes do cartão (como `RichText`, `Text` e `MoneyText`), impedindo que leitores de tela leiam valores parciais ou vazem o saldo quando o mascaramento de privacidade estiver ativo.
   - Remoção de espaçadores verticais fixos (`SizedBox(height: 18)` e `SizedBox(height: 16)`) no layout do cartão, prevenindo transbordamentos verticais quando a escala de texto aumenta.
2. **Aba de Contas (`accounts_tab.dart`):**
   - Altura do carrossel de cartões tornada responsiva e vinculada ao fator de escala do sistema:
     `final cardCarouselHeight = textScaler.scale(210.0).clamp(210.0, 440.0);`
   - Cabeçalhos de seção e botões de ação rápida ("Nova conta", "Ver arquivadas") refatorados com `Wrap` responsivo (`WrapAlignment.spaceBetween`, `spacing: AppTokens.p8`, `runSpacing: AppTokens.p8`), acomodando quebras de linha automáticas sem overflow em telas estreitas e fontes ampliadas.
3. **Aba de Contas a Receber (`agreements_tab.dart`):**
   - Header superior com título "Contas a receber" e botão "Nova conta a receber" refatorado com `Wrap`, permitindo que o botão passe para a linha seguinte em escalas elevadas de texto.
   - Bloco de métricas do `AgreementCard` (total contratado, recebido e restante) migrado de `Row` com `Expanded` rígido para `Wrap` adaptativo (`spacing: AppTokens.p16`, `runSpacing: AppTokens.p8`), eliminando transbordamentos laterais em larguras ensaiadas a partir de 320pt com 200% de escala.
4. **Aba de Contas a Pagar (`payables_tab.dart`):**
   - Header superior refatorado com `Wrap` responsivo.
   - Bloco de valores do `PayableCard` (restante a pagar / valor cancelado / total pago, pago líquido e valor total) migrado para `Wrap` adaptativo, alinhando as colunas de dados à esquerda com espaçamento fluido.
5. **Ampliação da Cobertura de Testes Automatizados (de 133 para 162 testes):**
   - `accounts_test.dart`: Testes de árvore semântica verificando que `AccountCard` com saldo oculto anuncia `'Conta ..., saldo oculto'` com nós internos excluídos; testes com saldo visível anunciando o valor canônico em BRL; testes de reflow em viewport de 320pt com escalas de 100%, 150% e 200% sem erros de layout.
   - `agreements_tab_test.dart`: Novos testes de widget para os requisitos AC-MOB-001, AC-MOB-004, AC-MOB-005 e AC-MOB-006 em largura de 320pt nas escalas 100%, 150% e 200%, garantindo ausência de overflow e acessibilidade dos botões de ação.
   - `payables_test.dart`: Testes de acessibilidade e reflow em 320pt nas escalas 100%, 150% e 200% sem overflow.

### Incidente de Governança Apple e Recuperação

- **Descrição do Incidente:** Durante a etapa preparatória do ciclo, ocorreu uma restauração não autorizada dos arquivos `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` e `apps/mobile/ios/Runner/Info.plist` no working tree através do comando `git checkout`, descartando transitoriamente as configurações locais de desenvolvimento do mantenedor.
- **Tratamento e Recuperação:** O evento foi formalmente identificado e catalogado como incidente de governança. Sob aprovação humana explícita, as configurações particulares do mantenedor foram recuperadas no working tree e blindadas para permanecerem estritamente fora da staging area e de qualquer commit ou push.

### Distinção dos Catálogos de Evidências Visuais

É fundamental distinguir categoricamente entre o catálogo oficial do repositório e o acervo local de ensaios de engenharia:

#### A. Catálogo Oficial Versionado do Repositório (15 Capturas)
Documentado formalmente em [`docs/screenshots.md`](../screenshots.md) e versionado diretamente em `prints/*.png`:
- **3 capturas de Acessibilidade:** Seletores adaptativos em 150% e 200% (`a11y_375px_scale_150_seletor.png`, `a11y_375px_scale_200_seletor.png`, `a11y_iphone17pro_scale_200_seletor.png`).
- **6 capturas de Tema Escuro:** Telas completas de Resumo PF/PJ, Carteira PF/PJ e Contas a Pagar (`dark_01_resumo_pf.png` a `dark_06_cadastro_pagar_recorrente.png`).
- **6 capturas de Tema Claro:** Telas completas de Resumo PF/PJ, Carteira PF/PJ e Contas a Pagar (`light_01_resumo_pf.png` a `light_06_cadastro_pagar_recorrente.png`).

#### B. Acervo de Evidências Locais de Engenharia FINANCE-MOB-01 (76 Capturas Não Versionadas)
Mantido no diretório local de ensaios `prints/finance-mob-01/` fora do controle de versão do Git, servindo como suporte de auditoria técnica para este ciclo. **Este acervo não substitui o catálogo oficial versionado** e classifica-se rigorosamente em:
1. **Históricas de Referência e Fluxo Geral (54 capturas):**
   - *Android Pixel 8 (16 capturas em `android/`):* Telas de login (sucesso, credenciais inválidas, erros de validação), menu de usuário, dashboard PF/PJ (claro, escuro, saldos ocultos), carteira de contas e listas operacionais em 100%, além do ensaio isolado em 100% (`android_pixel8_mob-b1_a11y100_pf.png`).
   - *iOS iPhone 17 / iPhone 17e / iPhone 17 Pro (38 capturas em `ios/`):* Modos claro e escuro, cartões de contas PF/PJ, telas compactas em 100%, configurações e seletores adaptativos em 375pt.
2. **Substituídas / Superadas (BEFORE — 6 capturas de diagnóstico de falha):**
   - *iOS (2 capturas em `ios/`):* `ios_iphone17e_mob-b1_agreements_overflow_200.png` e `ios_iphone17e_mob-b1_payables_overflow_200.png`, que documentavam falhas de overflow nas abas de acordos e despesas a 200%; **substituídas e superadas** pelas capturas AFTER correspondentes (`ios_iphone17e_mob-b2_agreements_after_200.png` e `ios_iphone17e_mob-b2_payables_after_200.png`).
   - *Android (4 capturas em `android/`):* `android_pixel8_mob-b1_a11y150_pf.png` (ensaio intermediário em 150%), `android_pixel8_mob-b1_a11y200_initial.png`, `android_pixel8_mob-b1_a11y200_scrolled.png` e `android_pixel8_mob-b1_a11y200_bottom.png` (ensaios em 200%), que documentavam limitações iniciais de escala no Dashboard PF; **substituídas e superadas conjuntamente pelo ensaio mais restritivo de 200%** registrado nas capturas AFTER correspondentes em `b2/android/` (`android_pixel8_mob-b2_dashboard_pf_200.png`, `android_pixel8_mob-b2_dashboard_pf_200_scrolled.png` e `android_pixel8_mob-b2_dashboard_pf_200_bottom.png`), complementadas pelo reflow das abas (`android_pixel8_mob-b2_accounts_pf_200.png`, `android_pixel8_mob-b2_agreements_pf_200.png` e `android_pixel8_mob-b2_payables_pf_200.png`).
3. **Validação de Reflow e Correção (AFTER — 16 capturas atuais e válidas):**
   - *Android Pixel 8 (6 capturas em `b2/android/`):* `android_pixel8_mob-b2_accounts_pf_200.png`, `android_pixel8_mob-b2_agreements_pf_200.png`, `android_pixel8_mob-b2_dashboard_pf_200.png`, `android_pixel8_mob-b2_dashboard_pf_200_bottom.png`, `android_pixel8_mob-b2_dashboard_pf_200_scrolled.png`, `android_pixel8_mob-b2_payables_pf_200.png`, comprovando reflow completo e ausência de erros visuais em 200%.
   - *iOS iPhone 17 / iPhone 17e (10 capturas em `b2/ios/`):* `ios_iphone17_mob-b2_accounts_pf_100.png`, `ios_iphone17_mob-b2_accounts_pj_100.png`, `ios_iphone17_mob-b2_dashboard_pf_dark_100.png`, `ios_iphone17_mob-b2_payables_pf_100.png`, `ios_iphone17_mob-b2_payables_pj_100.png`, `ios_iphone17e_mob-b2_accounts_after_200.png`, `ios_iphone17e_mob-b2_agreements_after_200.png`, `ios_iphone17e_mob-b2_dashboard_after_200.png`, `ios_iphone17e_mob-b2_dashboard_light_100.png`, `ios_iphone17e_mob-b2_payables_after_200.png`, atestando a correção dos transbordamentos anteriores.

### Homologação Remota na CI (GitHub Actions CI #23, Run ID `39365113034`)

- **Execução Geral:** [Run 39365113034](https://github.com/jeannlucas/bigdevz-finance/actions/runs/39365113034)
- **Commit Validado:** `da8545fdfef934c91c0ca764023043bf80a040e0`
- **Branch:** `dev` (disparo via `push`)
- **Status Geral:** **`success` (PASS)**
- **Job `api` ([ID 118440059583](https://github.com/jeannlucas/bigdevz-finance/actions/runs/39365113034/job/118440059583)):** Concluído com sucesso em 41 segundos.
  - Setup do container PostgreSQL 18-alpine na porta 5440.
  - Testes de Domínio PHP (`php tests/domain.php`): 13 testes aprovados (0 falhas).
  - Pint (`vendor/bin/pint --test`): 100% conforme.
  - Testes Laravel em PostgreSQL Real (`php artisan test`): 84 testes aprovados, 1.139 asserções (0 falhas).
- **Job `mobile` ([ID 118440059790](https://github.com/jeannlucas/bigdevz-finance/actions/runs/39365113034/job/118440059790)):** Concluído com sucesso em 2 minutos e 20 segundos.
  - Instalação das dependências com verificação estrita de lockfile (`flutter pub get --enforce-lockfile`).
  - Formatação Dart (`dart format --output=none --set-exit-if-changed`): 80 arquivos verificados, 0 modificados (0.69s).
  - Análise Estática Flutter (`flutter analyze`): 0 problemas encontrados (`No issues found!`, 14.2s).
  - Suíte de Testes Flutter (`flutter test`): 162 testes aprovados (0 falhas, 48s).

### Limitações Técnicas e Homologações Restantes

- **Ambiente de Ensaios:** O reflow responsivo foi verificado em simuladores iOS (iPhone 17 / iPhone 17e) e emulador Android (Pixel 8) nas escalas ensaiadas (100%, 150%, 200%).
- **Ausência de Build Nativo na CI Linux:** O workflow do GitHub Actions em runner Ubuntu valida análise estática e suíte de testes unitários/widget em Dart, mas não compila APK/IPA nem executa testes emulados Android ou simulados iOS na nuvem.
- **Certificação de Acessibilidade:** Os testes atestam ausência de overflow e semântica estrutural correta nas condições ensaiadas, mas **não equivalem a uma certificação formal de conformidade integral WCAG 2.1 AA/AAA**.
- **Hardware Físico:** A validação interativa com leitores de tela em aparelhos físicos reais (TalkBack em Android e VoiceOver em iPhone) permanece pendente de homologação manual.
- **Portão 2 Financeiro:** Nenhuma operação financeira com escrita foi executada; os fluxos de escrita permanecem sob bloqueio operacional aguardando autorização humana soberana.
- **Estado Operacional Documental:** **`DOCUMENTACAO_EDITADA_AGUARDANDO_APROVACAO_DO_DIFF`** (Checkpoint `FINANCE-DOC-01.B.5-B`). Três documentos editados localmente; zero arquivos em staging; commit e push documentais pendentes.

---

## 13. Checkpoint FINANCE-WEB-01 (01/11/2026) — Habilitação do Flutter Web, Desacoplamento Multiplataforma e Configuração de CORS

- **Objetivo**: Disponibilização da versão Web do BigDev.Z Finance sem atrito de lojas de aplicativos (Apple App Store / Google Play), reaproveitando 100% da lógica e telas existentes em Flutter, integrando com a mesma API Laravel e banco de dados PostgreSQL.
- **Modo**: IMPLEMENTAÇÃO CONTROLADA EM BRANCH `feature/flutter-web` + FAST-FORWARD MERGE PARA `dev`.
- **Branch Ativa**: `dev` (HEAD local: `506d187`).
- **Arquitetura & Refinamentos Concluídos**:
  1. **Desacoplamento de Plataforma em `api_client.dart`:** Remoção do `import 'dart:io'` e tratamento multiplataforma de `http.ClientException`, `TimeoutException` e desconexões.
  2. **Compatibilidade JavaScript com `dart2js` em `money.dart`:** Substituição de literais inteiros de 64 bits (`92233720368547758`) por parsing arbitrário via `BigInt`, eliminando a falha de compilação web e mantendo o limite estrito de R$ 999 bilhões e agregados.
  3. **Scaffolding Web Flutter (`apps/mobile/web/`):** Configuração de `index.html`, `manifest.json` e favicons oficiais da BigDev.Z com tema Azul Profundo (`#0A192F`).
  4. **Configuração de CORS na API Laravel (`apps/api/config/cors.php`):** Habilitação de requisições preflight `OPTIONS` e liberação dos cabeçalhos `Idempotency-Key`, `Authorization` e `Content-Type`.
  5. **Testes Automatizados Adicionados:**
     - `apps/mobile/test/core/api_client_test.dart`: 4 novos testes unitários (166 testes mobile aprovados).
     - `apps/api/tests/Feature/CorsPreflightTest.php`: 2 novos testes de integração (86 testes Laravel aprovados).
- **Resultados das Suítes Automatizadas (`scripts/check.sh --full`):**
  - Domínio Financeiro PHP: 13 testes aprovados (0 falhas).
  - Análise Estática Dart: 0 issues (`No issues found!`).
  - Laravel Pint: 108 arquivos conformes.
  - Formatação Dart: 80 arquivos conformes.
  - Suíte Flutter: 166 testes aprovados (0 falhas).
  - API Laravel em PostgreSQL Real: 86 testes aprovados (1.146 asserções, 0 falhas).
- **Validação Visual no Navegador:** Aplicativo executado localmente via servidor HTTP na porta 8085 e API na porta 8000, com login, alternância PF/PJ e privacidade demonstrados e aprovados pelo mantenedor Jeann Lucas.
- **Commit Local Integrado:** `506d187` (`feat(web): adicionar suporte ao flutter web e configuracao de cors`).

---

## 14. Checkpoint FINANCE-TRF-01 (04/11/2026) — Transferências entre Contas, Atomicidade Contábil e Suporte Multiplataforma (iOS, Android, Web)

- **Objetivo**: Implementação completa de transferências atômicas entre contas do mesmo espaço financeiro (PF ou PJ), garantindo precisão matemática sem float, locks pessimistas ordenados imunes a *deadlock*, idempotência e interface acessível multiplataforma.
- **Modo**: IMPLEMENTAÇÃO CONTROLADA EM BRANCH `feature/transferencias-entre-contas`.
- **Branch Ativa**: `feature/transferencias-entre-contas` (HEAD local: `0a23756`).
- **Arquitetura & Refinamentos Concluídos**:
  1. **Migration & Modelagem Contábil:** Criação da tabela `transfers` com restrições `CHECK`, FKs compostas e integração direta a `account_movements` (saída na origem e entrada no destino no mesmo commit) e `idempotency_keys`.
  2. **Action Atômica `TransferFunds`:** Bloqueio pessimista com `lockForUpdate` ordenado por ID (`min(id)` depois `max(id)`), eliminando qualquer risco de concorrência ou deadlock.
  3. **Regras de Negócio e Cheque Especial:** Suporte a saldo devedor na conta de origem até `-Money::MAX_CENTS` (conforme Decisão 0006), validação de marco de abertura e rejeição de contas arquivadas ou idênticas (HTTP 422).
  4. **Proteção Multi-Tenant & IDOR:** Operações em contas alheias respondem estritamente `404 Not Found`.
  5. **Interface Flutter Unificada:** `TransferFormScreen` com seleção de contas, máscara monetária sem float, dropdowns adaptativos com `isExpanded: true` e atalho integrado em `AccountsTab`.
- **Resultados das Suítes Automatizadas (`scripts/check.sh --full`):**
  - Domínio Financeiro PHP: 13 testes aprovados (0 falhas).
  - Análise Estática Dart: 0 issues (`No issues found!`).
  - Laravel Pint: 114 arquivos conformes (0 issues).
  - Formatação Dart: 82 arquivos conformes (0 pendências).
  - Suíte Flutter: 171 testes aprovados (0 falhas).
  - API Laravel em PostgreSQL Real: 87 testes aprovados (1.222 asserções, 0 falhas).
- **Commit Local Criado:** `0a23756` (`feat(transfers): implementar transferencia entre contas com atomicidade e idempotencia`).

---

## 15. Checkpoint FINANCE-EMP-01 (04/11/2026) — Módulo de Empréstimos Tomados e Concedidos, Desembolso Atômico e Amortização

- **Objetivo**: Implementação completa do módulo de empréstimos tomados e concedidos, com classificação bipolar (`taken` / `granted`), integração contábil atômica de desembolso (`account_movements`) e geração nativa de obrigações amortizáveis (`PayablePlan`/`Payable` para tomados; `Agreement`/`Installment` para concedidos).
- **Modo**: IMPLEMENTAÇÃO CONTROLADA EM BRANCH `feature/emprestimos` + FAST-FORWARD MERGE PARA `dev`.
- **Branch Ativa**: `dev` (HEAD local e remoto: `6bf986d`).
- **Arquitetura & Refinamentos Concluídos**:
  1. **Modelagem Patrimonial Exata:** Tabela `loans` com chaves estrangeiras compostas `(id, space_id)`, restrições `CHECK` contra valores não positivos ou excedentes a `Money::MAX_CENTS` e flags de desembolso imediato.
  2. **Atomicidade e Concorrência:** Action `CreateLoan` operando sob transação com locks pessimistas (`lockForUpdate`) na conta bancária de desembolso, garantindo consistência estrita de saldos e auditoria patrimonial.
  3. **Idempotência Persistida e Proteção IDOR:** Cabeçalho `Idempotency-Key` com deduplicação de requisições (`200` replayed / `409` conflict) e isolamento multi-tenant intransigente (`404 Not Found` para espaços não autorizados).
  4. **Interface Flutter Multiplataforma (iOS, Android, Web):**
     - `LoansScreen`: listagem com filtros por status (`active`, `settled`, `cancelled`) e tipo (`taken`, `granted`), cards com barra de progresso de amortização, tags coloridas e modal de detalhes completo.
     - `LoanFormScreen`: formulário adaptativo com suporte a taxas de juros, multas/encargos, cálculo dinâmico da parcela estimada e validação de acessibilidade em 320pt a 200% de escala de texto.
  5. **Especificação Permanente:** Documentada e ancorada em `specs/emprestimos/emprestimos.md`.
- **Resultados das Suítes Automatizadas (`scripts/check.sh --full`):**
  - Domínio Financeiro PHP: 13 testes aprovados (0 falhas).
  - Análise Estática Dart: 0 issues (`No issues found!`).
  - Laravel Pint: 120 arquivos conformes (0 issues).
  - Formatação Dart: 87 arquivos conformes (0 pendências).
  - Suíte Flutter: 176 testes aprovados (0 falhas).
  - API Laravel em PostgreSQL Real: 95 testes aprovados (1.355 asserções, 0 falhas).
- **Commit Integrado na `dev`:** `6bf986d` (`feat(loans): implementar modulo de emprestimos tomados e concedidos com desembolso e amortizacao`).

---

## 16. Checkpoint FINANCE-PROD-01 (04/11/2026) — Publicação em Produção (Go-Live na VPS), Flutter Web SPA e Health Check

- **Objetivo**: Publicação do BigDev.Z Finance em ambiente de produção na VPS com alta disponibilidade, segurança e monitoramento contínuo.
- **Ambiente de Produção (VPS `bigdevz` / `179.198.113.104`):**
  - **Domínio Canônico:** `https://finance.bigdevz.com` com certificado SSL Let's Encrypt gerenciado automaticamente pelo Caddy.
  - **Frontend:** Flutter Web SPA compilado em Release, servido via HTTP/2 com fallback de rotas SPA.
  - **Backend:** Laravel 13 em container Docker isolado (`127.0.0.1:8510`) com PHP 8.4 e dependências otimizadas (`config:cache`, `route:cache`).
  - **Banco de Dados:** PostgreSQL 17 dedicado em volume persistente `bigdevz-finance_postgres-data`.
- **Infraestrutura e Rotas Adicionadas:**
  - `GET /api/up`: Endpoint de health check com status HTTP 200 (`{"status":"ok"}`) para sondagem pelo Caddy e ferramentas de monitoramento.
  - `Artisan user:create`: Comando seguro no `console.php` para provisionamento inicial de usuários sem bypass de hash de senha ou regras de espaço.
  - `UpHealthCheckTest`: Teste de integração automatizado na suíte de testes da API.
- **Resultados das Suítes Automatizadas (`scripts/check.sh --full`):**
  - Domínio Financeiro PHP: 13 testes aprovados (0 falhas).
  - Análise Estática Dart: 0 issues (`No issues found!`).
  - Laravel Pint: 121 arquivos conformes (0 issues).
  - Formatação Dart: 87 arquivos conformes (0 pendências).
  - Suíte Flutter: 176 testes aprovados (0 falhas).
  - API Laravel em PostgreSQL Real: 96 testes aprovados (1.357 asserções, 0 falhas).
- **Estado Operacional:** `PRODUCAO_PUBLICADA_LIVE`. Monitoramento ativo com usuários em fase de testes reais.

---

## 17. Checkpoint FINANCE-PROD-02 (09/11/2026) — Deploy em Produção: Categorias, Baixa Múltipla, Filtros e Modais Adaptativos

- **Objetivo**: Publicação completa das features de Baixa Múltipla, Módulo de Categorias, Filtros por Categoria e Layouts Adaptativos na VPS de produção (`finance.bigdevz.com`).
- **Ambiente de Produção (VPS `bigdevz` / `179.198.113.104`):**
  - **Domínio Canônico:** `https://finance.bigdevz.com` com Caddy HTTP/2 e HTTPS.
  - **Frontend:** Flutter Web Release compilado com `API_BASE_URL=https://finance.bigdevz.com/api` e sincronizado em `/srv/finance/web/`.
  - **Backend:** Laravel 13 reconstruído via `vps-deploy.sh` em container `bigdevz-finance-api-1` com dependências cacheadas (`config:cache`, `route:cache`).
  - **Banco de Dados:** Migration `2026_11_07_100000_create_categories_table` executada com sucesso e categorias padrão pré-populadas em todos os espaços.
  - **Health Check:** `https://finance.bigdevz.com/api/up` respondendo HTTP 200 OK.
- **Resultados das Suítes Automatizadas:**
  - GitHub Actions CI (Run #42400872283): 100% verde na branch `main`.
  - Backpressure local: 216 testes Flutter, 121 testes API e 1.438 asserções aprovadas.
- **Estado Operacional:** `PRODUCAO_PUBLICADA_LIVE`.

---

## 18. Checkpoint FINANCE-PROD-03 (09/11/2026) — Deploy em Produção: Modo de Entrada Flexível de Parcelas e Seletor em Contas a Receber

- **Objetivo**: Publicação completa em produção (`finance.bigdevz.com`) do novo modo de entrada de parcelas ("Valor da parcela" vs "Valor total"), cálculo reativo com zero float, card visual discreto de resumo (`InstallmentSummaryCard`) e seletor `[ Avulsa | Parcelada ]` em Contas a Receber.
- **Ambiente de Produção (VPS `bigdevz` / `179.198.113.104`):**
  - **Domínio Canônico:** `https://finance.bigdevz.com` com Caddy HTTP/2 e HTTPS.
  - **Frontend:** Flutter Web Release compilado com `API_BASE_URL=https://finance.bigdevz.com/api` e sincronizado em `/srv/finance/web/`.
  - **Backend:** Laravel 13 conteinerizado com rotas e configurações em cache (`config:cache`, `route:cache`).
  - **Health Check:** `https://finance.bigdevz.com/api/up` respondendo HTTP 200 OK (`{"status":"ok"}`).
- **Resultados das Suítes Automatizadas:**
  - GitHub Actions CI (Run #42632730513): 100% verde na branch `main`.
  - Backpressure local: 219 testes Flutter, 121 testes API e 1.438 asserções aprovadas.
- **Estado Operacional:** `PRODUCAO_PUBLICADA_LIVE`.

---

<!-- bigdevz-cli:start -->
## Checkpoint automático do CLI

- Data UTC: 2026-10-25T19:08:20.916840+00:00
- Estado: idle
- Branch: `dev`
- Commit: `e8c1603f17e16e9f897ee563f29b2ad8a062121b`
- Estado dos arquivos: `.git/ia-cli-checkpoint.json` (ou diretório Git do worktree).
- Este registro não comprova testes nem substitui as decisões e o próximo passo descritos acima.
- Ao retomar: confira Git, este handoff, processos pendentes e o checkpoint. Não descarte alterações.
<!-- bigdevz-cli:end -->
