# Melhorias Financeiro e UX (Categorias, Recorrências, Instituições, Débito e Sininho) — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar as 6 melhorias do BigDev.Z Finance para espaços PF e PJ cobrindo API Laravel, Flutter mobile e desktop web: Subcategorias (1 nível hierárquico com agregação contábil), Ícones de categorias com cores predefinidas e seletor visual, Catálogo de instituições com Wise e DUCZ Benefícios, Conta recorrente com valor variável, Registro imediato de compra no débito em confirmação única idempotente, e Sininho de notificações com leitura e dispensa persistentes por usuário, espaço e ocorrência.

**Architecture:**
- **Subcategorias e Ícones:** No backend, coluna `parent_id` em `categories` com FK composta `(parent_id, space_id)`, validações de mesmo espaço/tipo, bloqueio de ciclos/3º nível e endpoint com hierarquia; agregação contábil em relatórios/sumário somando grupo e filhas (teste 30 + 50 = 80). No frontend, catálogo centralizado de ícones Material e paletas pré-definidas com seletor visual e exibição de caminho `Pai > Filha`.
- **Instituições (Wise e DUCZ Benefícios):** Expansão do `BankCatalog` com IDs `wise` e `ducz`, busca por nome no cadastro e edição, suporte a contas de benefícios nos tipos já existentes do projeto, preservação de saldo/histórico ao reclassificar contas cadastradas como "Outro" e fallback legível.
- **Recorrências Variáveis:** Suporte a `is_variable` em `recurrences` e valor estimado opcional; ocorrências geradas com `status = 'awaiting_amount'` exibindo "Aguardando valor"; confirmação de valor pontual ou pagamento direto informando o valor efetivo no mesmo fluxo sem alterar os demais meses.
- **Compra no Débito (Despesa Paga Imediata):** Ação unificada e atômica (`DirectExpenseAction` / endpoint) acionável pelo início ou extrato; cria a obrigação já quitada e o pagamento com saída bancária em uma única transação protegida por `Idempotency-Key` (409 em divergência de payload), permitindo estorno completo e recomposição de saldo.
- **Sininho Persistente:** Tabela `alert_states` segregada por `(user_id, space_id, alert_key)` persistindo estados de lido e dispensado; endpoints para marcar leitura e dispensa; contador do badge refletindo apenas alertas ativos não dispensados e não lidos; isolamento estrito entre usuários e espaços PF/PJ.

**Tech Stack:** Laravel 13, PostgreSQL 18 (bancos `bigdevz_finance` e `bigdevz_finance_test`), PHP 8.3 puro de domínio, Flutter 3.24+ (Dart, Provider, Material Design).

**Specs:** `specs/categorias/categorias.md`, `specs/financeiro/financeiro.md`, `specs/extrato/extrato.md`.

---

## Global Constraints

- Proibição estrita de float/double para dinheiro: centavos inteiros de 64 bits (`cents`) e strings decimais canônicas com 2 casas (`"2000.00"`).
- Isolamento multi-tenant intransponível por espaço (`space_id`), com restrições compostas de chave estrangeira no PostgreSQL e resposta `404 Not Found` para acessos indevidos.
- Imutabilidade contábil: lançamentos liquidados não sofrem `DELETE`; compensações ocorrem via estornos com trilha de auditoria.
- Idempotência transacional via `Idempotency-Key` e locks pessimistas ordenados (`lockForUpdate`).
- Nenhuma dependência externa nova sem autorização expressa do mantenedor.
- Backpressure mandatória: `make check` (ou `./scripts/check.sh --full`) 100% verde com zero erros no Mac antes de qualquer entrega.
- Soberania de Git: commits e pushes exigem autorização específica do mantenedor; zero commits na `main`.

---

## Review Focus

1. **Ciclo ou 3º nível em subcategorias:** Categoria filha não pode ter subcategoria nem apontar para si mesma ou categoria de tipo diferente.
2. **Reexecução do gerador de obrigações em recorrências variáveis:** Reexecutar `GenerateObligations` não pode duplicar ciclos nem sobrescrever ocorrências já confirmadas ou pagas.
3. **Idempotência concorrente no registro de compra no débito:** Duas requisições paralelas com a mesma chave processam exatamente uma vez; payload divergente retorna 409 Conflict.
4. **Isolamento de dispensa de alertas entre usuários e competências:** Dispensar alerta em um espaço/usuário não afeta o outro usuário nem o outro espaço; uma nova competência da mesma série gera seu próprio alerta.
5. **Reassociação de conta "Outro" para Wise ou DUCZ:** Alteração preserva integralmente id, movimentações passadas, correções de abertura e saldo da conta.

---

## Fases e Tarefas de Implementação

### Fase 1: Especificações Permanentes (L2) e Delta Provado

- [ ] **Task 1.1: Atualizar `specs/categorias/categorias.md` com Critérios de Subcategorias e Ícones**
  - **Arquivos:** `specs/categorias/categorias.md`
  - Adicionar critérios `AC-CAT-007` (Subcategorias de 1 nível com isolamento e validação de espaço/tipo), `AC-CAT-008` (Prevenção de ciclos, autorreferência e 3º nível), `AC-CAT-009` (Agregação hierárquica em relatórios com abertura de composição) e `AC-CAT-010` (Catálogo de ícones com paletas predefinidas e seletor visual).
  - Atualizar a matriz de rastreabilidade.

- [ ] **Task 1.2: Atualizar `specs/financeiro/financeiro.md` com Critérios das Novas Funcionalidades**
  - **Arquivos:** `specs/financeiro/financeiro.md`
  - Adicionar critérios `AC-FIN-025` (Conta recorrente com valor variável e ocorrências 'Aguardando valor'), `AC-FIN-026` (Registro direto de compra no débito em transação atômica e idempotente), `AC-FIN-027` (Instituições Wise e DUCZ Benefícios com preservação de histórico em reclassificações) e `AC-FIN-028` (Sininho de notificações com leitura e dispensa persistentes).
  - Atualizar a matriz de rastreabilidade.

---

### Fase 2: Backend — Subcategorias e Validações

- [ ] **Task 2.1: Migration de `parent_id` na tabela `categories`**
  - **Arquivos:** Criar `apps/api/database/migrations/2026_11_21_170000_add_parent_id_to_categories_table.php`
  - Adicionar coluna `parent_id` unsigned big integer nullable.
  - Adicionar chave estrangeira composta `FOREIGN KEY (parent_id, space_id) REFERENCES categories (id, space_id) ON DELETE RESTRICT`.
  - Índice em `(space_id, parent_id)`.

- [ ] **Task 2.2: Atualizar Model `Category` e Relacionamentos**
  - **Arquivos:** `apps/api/app/Models/Category.php`, `apps/api/app/Http/Resources/CategoryResource.php`
  - Adicionar `parent_id` em `$fillable` e casts.
  - Relacionamentos: `parent(): BelongsTo`, `children(): HasMany`.
  - No `CategoryResource`, retornar `parent_id`, `parent_name` (quando existir) e `children` (quando carregado).

- [ ] **Task 2.3: Atualizar `CategoryController` com Regras de Validação de Hierarquia**
  - **Arquivos:** `apps/api/app/Http/Controllers/Api/CategoryController.php`
  - Em `store` e `update`:
    - Validar `parent_id`: se informado, deve existir no mesmo espaço, mesmo tipo (`type`), não pode ter `parent_id` (máximo 1 nível), não pode ser a própria categoria (`parent_id != id`), e uma categoria que já possua filhos não pode ter `parent_id`.
    - Ao excluir categoria com filhas (`destroy`), bloquear a exclusão informando que existem subcategorias vinculadas.
  - Escrever testes que falham em `apps/api/tests/Feature/SubcategoriesTest.php` e rodar para comprovar o delta.

- [ ] **Task 2.4: Atualizar Agregação Contábil de Categorias no Resumo (`SpaceController`)**
  - **Arquivos:** `apps/api/app/Http/Controllers/Api/SpaceController.php`
  - Em `expenseCategoriesSummary`: agrupar valores por categoria principal (`parent_id ?? id`), calculando o total do grupo somando valores classificados diretamente na principal e valores em suas subcategorias; retornar a árvore/composição (`items` ou `children` com o valor direto e cada subcategoria).
  - Cobrir teste: R$ 30,00 em Moradia + R$ 50,00 em Moradia > Energia = Grupo R$ 80,00, Filha R$ 50,00, Total R$ 80,00.

---

### Fase 3: Backend — Recorrência com Valor Variável

- [ ] **Task 3.1: Migration de Modalidade e Estimativa em `recurrences` e `payables`**
  - **Arquivos:** Criar `apps/api/database/migrations/2026_11_21_171000_add_variable_amount_to_recurrences.php`
  - Em `recurrences`: `is_variable` (boolean, default false), `estimated_amount_cents` (nullable bigint).
  - Em `payables`: `estimated_amount_cents` (nullable bigint, para suporte a estimativa na ocorrência).
  - Ajustar constraints para permitir `amount_cents` nulo quando `kind = 'recurring'` e `is_variable = true`.

- [ ] **Task 3.2: Atualizar `CreatePayable` e `GenerateObligations` para Suporte a Recorrências Variáveis**
  - **Arquivos:** `apps/api/app/Actions/Payables/CreatePayable.php`, `apps/api/app/Actions/Payables/GenerateObligations.php`, `apps/api/app/Models/Recurrence.php`, `apps/api/app/Http/Resources/RecurrenceResource.php`
  - Se `is_variable = true`: `amount_cents` na recorrência é nulo (ou 0); ocorrências geradas recebem `amount_cents = null` e `estimated_amount_cents` preenchido se fornecido.
  - A ocorrência fica com status `awaiting_amount` até que o usuário defina o valor.
  - Testes em `apps/api/tests/Feature/VariableRecurrenceTest.php`: criação, geração de ocorrências, reexecução do gerador sem duplicação, e alteração de valor pontual de uma ocorrência sem afetar os outros meses.

- [ ] **Task 3.3: Suporte à Liquidação Direta com Definição de Valor Efetivo**
  - **Arquivos:** `apps/api/app/Actions/Payables/PayPayable.php`, `apps/api/app/Http/Controllers/Api/PaymentController.php`
  - Permitir que ocorrência em `awaiting_amount` receba o valor efetivo no payload de pagamento, atualizando `amount_cents` e efetuando a baixa na mesma transação atômica.

---

### Fase 4: Backend — Compra no Débito (Despesa Paga Imediata)

- [ ] **Task 4.1: Endpoint e Action Atômica de Despesa Paga**
  - **Arquivos:** Criar `apps/api/app/Actions/Payables/RegisterDirectExpense.php`, rota `POST /api/spaces/{space}/payables/direct-expense` em `apps/api/routes/api.php`, controller method em `apps/api/app/Http/Controllers/Api/PayableController.php`.
  - Payload: `account_id`, `amount`, `paid_on`, `description`, `category_id` (opcional), `payee` (opcional).
  - Operação atômica dentro de transação com locks:
    1. Lock na conta bancária;
    2. Criação do `Payable` com `kind = 'single'`, `amount_cents = $cents`, `paid_cents = $cents`, `due_date = $paidOn`;
    3. Criação do `Payment` debitando a conta;
    4. Criação do `AccountMovement` de saída (`-$cents`);
    5. Registro de alteração em `ObligationChange`.
  - Suporte a `Idempotency-Key`: repetição idêntica devolve `200 OK` / `201 Created` com `replayed = true`; payload divergente responde `409 Conflict`.
  - Suporte nativo a estorno: como o pagamento existe normalmente, `ReversePayment` recompõe o saldo da conta e abre a obrigação para cancelamento.
  - Testes em `apps/api/tests/Feature/DirectExpenseTest.php`: compra de R$ 35,90 em conta com R$ 100,00 resulta em saldo de R$ 64,10, 1 saída no extrato, 0 obrigações abertas; estorno recompõe R$ 100,00.

---

### Fase 5: Backend — Sininho com Persistência de Leitura e Dispensa

- [ ] **Task 5.1: Migration e Model `AlertState`**
  - **Arquivos:** Criar `apps/api/database/migrations/2026_11_21_172000_create_alert_states_table.php`, `apps/api/app/Models/AlertState.php`.
  - Colunas: `id`, `user_id`, `space_id`, `alert_key`, `read_at` (nullable timestamp), `dismissed_at` (nullable timestamp), timestamps.
  - Chave única composta: `UNIQUE (user_id, space_id, alert_key)`.
  - FKs para `users` e `spaces`.

- [ ] **Task 5.2: Controller e Endpoints de Alertas do Espaço**
  - **Arquivos:** Criar `apps/api/app/Http/Controllers/Api/AlertController.php`, rotas:
    - `GET /api/spaces/{space}/alerts`: lista alertas ativos (contas a pagar vencidas, contas a receber vencidas, faturas/recorrências aguardando valor, próximos vencimentos) com flags `is_read` e `is_dismissed`. Alertas com `is_dismissed = true` são filtrados da visualização ativa por padrão (ou via `include_dismissed=false`).
    - `POST /api/spaces/{space}/alerts/{key}/read`: marca como lido (`read_at = now()`).
    - `POST /api/spaces/{space}/alerts/{key}/dismiss`: marca como dispensado (`dismissed_at = now()`).
    - `GET /api/spaces/{space}/alerts/badge`: retorna a contagem de alertas ativos que não foram dispensados nem lidos (`unread_active_count`).
  - Testes em `apps/api/tests/Feature/AlertsTest.php`: persistência por usuário/espaço/chave; dispensar uma de duas contas vencidas preserva a outra; isolamento entre usuários e entre PF e PJ.

---

### Fase 6: Frontend — Subcategorias e Seletor Visual com Paletas

- [ ] **Task 6.1: Model `Category` e Catálogo Centralizado de Estilos e Ícones**
  - **Arquivos:** `apps/mobile/lib/features/categories/category.dart`, criar `apps/mobile/lib/features/categories/category_style_catalog.dart`.
  - Atualizar `Category` com `parentId` e `parentName`.
  - Em `category_style_catalog.dart`:
    - Mapeamento centralizado de identificadores para Material Icons (`home`, `bolt`, `water_drop`, `shopping_cart`, `restaurant`, `directions_car`, `medical_services`, `groups`, `description`, `computer`, etc.).
    - Cores predefinidas para cada ícone (azul, âmbar com alto contraste, ciano, verde, laranja, índigo, turquesa, violeta, ocre, azul-petróleo).
    - Suporte a fallback seguro para identificadores antigos ou desconhecidos.

- [ ] **Task 6.2: Seletor Visual de Ícone e Cor (`CategoryIconColorPicker`)**
  - **Arquivos:** Criar `apps/mobile/lib/features/categories/category_icon_color_picker.dart`.
  - Grid interativo de ícones com prévia de cor padrão e nomes em português; ao clicar em um ícone, a cor correspondente é sugerida automaticamente, permitindo ajuste manual.
  - Validação de contraste nos modos claro e escuro.

- [ ] **Task 6.3: Modal de Gerenciamento e Seletor de Categoria com Hierarquia**
  - **Arquivos:** `apps/mobile/lib/features/categories/category_picker_field.dart`, `apps/mobile/lib/features/categories/category_badge.dart`, tela/modal de categorias.
  - Exibição do caminho completo `Pai > Filha` quando houver ambiguidade.
  - Possibilidade de selecionar categoria pai ou filha no formulário.
  - No Dashboard/Resumo (`dashboard_charts.dart` e `summary_tab.dart`): suporte a expandir a categoria principal para visualizar a sua composição.

---

### Fase 7: Frontend — Catálogo de Instituições: Wise e DUCZ Benefícios

- [ ] **Task 7.1: Adicionar Wise e DUCZ Benefícios ao `BankCatalog`**
  - **Arquivos:** `apps/mobile/lib/features/accounts/bank_catalog.dart`, `apps/mobile/assets/banks/wise.png`, `apps/mobile/assets/banks/ducz.png`.
  - Adicionar `wise`: id `'wise'`, nome `'Wise'`, código `'362'`, cor `#163300` / `#9FE870`.
  - Adicionar `ducz`: id `'ducz'`, nome `'DUCZ Benefícios'`, código `'---'`, cor oficial DUCZ (roxo/magenta `#7B2CBF`).
  - Atualizar `findByAccountName` para reconhecer `'wise'` e `'ducz'`.
  - Gerar/posicionar assets PNG 256x256 oficiais locais padronizados com fundo transparente. Se indisponível, fallback com símbolo/iniciais e registro de pendência.

- [ ] **Task 7.2: Busca e Associação de Instituição no Cadastro e Edição de Contas**
  - **Arquivos:** `apps/mobile/lib/features/accounts/account_form_screen.dart`, `apps/mobile/lib/features/accounts/account_edit_screen.dart`.
  - No cadastro: busca por "Wise" e "DUCZ Benefícios" localiza e exibe o card correto.
  - Na edição: permitir associar a instituição (ou renomear mantendo o prefixo) para contas cadastradas anteriormente como "Outro", preservando o saldo, ID e histórico.
  - Testes em `apps/mobile/test/features/bank_catalog_test.dart` e `account_form_test.dart`.

---

### Fase 8: Frontend — Recorrência Variável e Compra no Débito

- [ ] **Task 8.1: Interface de Recorrência com Opção Variável**
  - **Arquivos:** `apps/mobile/lib/features/payables/payable_form_screen.dart` (ou modal de cadastro de conta a pagar).
  - Seletor de modalidade de valor: "Fixo" ou "Variável".
  - Se variável: campo de valor torna-se "Estimativa opcional"; aviso explicativo de que as ocorrências serão geradas com "Aguardando valor".
  - Na agenda/lista de contas a pagar (`payables_tab.dart`): exibição clara do badge "Aguardando valor" para ocorrências variáveis e distinção entre confirmado e estimado.

- [ ] **Task 8.2: Ação Rápida "Registrar Despesa Paga"**
  - **Arquivos:** `apps/mobile/lib/features/statement/statement_tab.dart`, `apps/mobile/lib/features/home/home_shell.dart`, criar modal `apps/mobile/lib/features/payables/direct_expense_modal.dart`.
  - Botão visível "Registrar despesa paga" no início e no extrato.
  - Ao abrir a partir do extrato com uma conta filtrada, pré-selecionar ou destacar a conta em contexto.
  - Formulário enxuto em confirmação única: Conta bancária, Valor, Data, Descrição, Categoria (opcional).
  - Feedback imediato: recarrega extrato e saldo da conta.

---

### Fase 9: Frontend — Sininho com Leitura e Dispensa Persistentes

- [ ] **Task 9.1: Painel de Notificações com Ações de Ler e Dispensar**
  - **Arquivos:** `apps/mobile/lib/features/home/notifications_modal.dart`, `apps/mobile/lib/features/home/home_shell.dart`, repositório de alertas.
  - Conectar o modal de notificações ao endpoint `GET /api/spaces/{space}/alerts`.
  - Cada card exibe botão de "Marcar como lido" e "Dispensar".
  - Alerta lido ganha indicador visual de lido (estilo mais suave), permanecendo consultável.
  - Alerta dispensado é removido da lista ativa com animação suave e confirmação.
  - O badge no sininho da barra superior consome a contagem de não lidos ativos e some ao chegar em zero.
  - Testes em `apps/mobile/test/features/notifications_modal_test.dart`.

---

### Fase 10: Backpressure, Validação Visual, Handoff e Entrega

- [ ] **Task 10.1: Executar Suíte de Testes Automatizados Completa**
  - Comandos:
    - `php tests/domain.php`
    - `vendor/bin/pint --test`
    - `flutter analyze`
    - `dart format --output=none --set-exit-if-changed`
    - `flutter test`
    - `php artisan test` (em PostgreSQL real descartável `bigdevz_finance_test`)
    - `./scripts/check.sh --full` (ou `make check`)
  - Garantir 100% de checks verdes com zero erros.

- [ ] **Task 10.2: Auditoria Visual Multiplataforma e Chrome DevTools**
  - Validar no Mobile 375px e Desktop widescreen:
    - Seletor de ícones e cores em tema claro e escuro.
    - Relatório com categoria principal e subcategoria expandida.
    - Seleção de Wise e DUCZ Benefícios.
    - Registro de despesa paga no extrato.
    - Modal de notificações com dispensa e leitura.
  - Capturar evidências e relatar até 3 oportunidades de design.

- [ ] **Task 10.3: Atualizar `docs/ai/HANDOFF.md` e Formatar Entrega**
  - Atualizar o handoff operacional com o estado final da branch.
  - Apresentar o relatório final estruturado no formato oficial do `AGENTS.md`.
