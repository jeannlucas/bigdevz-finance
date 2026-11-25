# BigDev.Z Finance — Registro de Pendências, Correções e Melhorias

> **Finalidade:** Registro permanente e contínuo de inconsistências, bugs visuais, melhorias de UX e refatorações identificadas durante o uso real e testes operacionais de Jeann Lucas.  
> **Formato:** Cada item possui identificador único (`PEND-XXX`), severidade, localização exata no código, diagnóstico da causa-raiz e proposta de solução.

---

## Índice de Itens

| ID | Data | Módulo / Tela | Severidade | Descrição Resumida | Status |
|:---:|:---:|:---:|:---:|---|:---:|
| `PEND-001` | 22/11/2026 | Dashboard / Fluxo de Caixa | Média (Visual/Cálculo) | Dupla contagem de obrigações vencidas no card de Fluxo de Caixa | Concluído / Validado ✅ |
| `PEND-002` | 22/11/2026 | A Pagar / Recorrência Variável | Alta (Fricção de UX) | Primeira ocorrência nasce sem valor mesmo quando usuário informou valor no cadastro | Concluído / Validado ✅ |
| `PEND-003` | 22/11/2026 | A Pagar / Formulário Recorrente | Baixa (Visual/Layout) | Truncamento de texto no label do campo de valor de recorrência variável | Concluído / Validado ✅ |
| `PEND-004` | 22/11/2026 | Formulários (A Pagar / Receber / Contas) | Média (Usabilidade / UX) | Identificação visual de campos obrigatórios com asterisco vermelho (*) e validação padronizada | Concluído / Validado ✅ |
| `PEND-005` | 22/11/2026 | Web Desktop / Todas as Telas | Alta (Layout Widescreen) | Telas comprimidas por `maxWidth: 1040` restrito (Dashboard, Extrato, A Pagar, A Receber e Contas) | Concluído / Validado ✅ |
| `PEND-006` | 22/11/2026 | Categorias / Seletor de Ícones | Média (Visual/Fonte) | Glifos de ícones `*_rounded` invisíveis no Flutter Web (ficam em branco com apenas a bolinha colorida) | Concluído / Validado ✅ |
| `PEND-007` | 22/11/2026 | A Pagar / Parcelamentos e Carnês | Média (Funcional / Negócio) | Suporte a carnês com vencimento em dias úteis e parcelas com valores reajustáveis (correção monetária) | Concluído / Validado ✅ |
| `PEND-008` | 23/11/2026 | Categorias / Seletor de Categorias | Alta (UX / Visual) | Dropdown de categorias exibe lista plana desordenada sem hierarquia em árvore (pai/filho) | Concluído / Validado ✅ |
| `PEND-009` | 23/11/2026 | A Receber / Recorrências de Receitas | Alta (Funcional / Negócio) | Módulo A Receber só possui Avulso e Parcelado, sem suporte a Recorrências (fixas ou variáveis) | Concluído / Validado ✅ |
| `PEND-010` | 23/11/2026 | Dashboard / Botão de Despesa Paga | Média (Design / Layout) | Botão "Registrar despesa paga (débito em conta)" esticado de ponta a ponta no widescreen com label longo | Concluído / Validado ✅ |
| `PEND-011` | 24/11/2026 | A Pagar / Cronograma de Parcelas | Média (Validação / UX) | Campo de valor das parcelas no cronograma aceita letras e caracteres não numéricos | Publicado / Validado ✅ |
| `PEND-012` | 24/11/2026 | Categorias / Flutter Web | Alta (UX / Visual) | Grade de ícones em Nova Categoria exibe apenas pontos de cor em produção | Publicado / Validação visual pendente ⏳ |
| `PEND-013` | 24/11/2026 | Contas / Wise | Alta (Funcional / Negócio) | Carteira multimoeda com saldos separados e conversões manuais | Publicado / Validado ✅ (v1.6.0) |
| `PEND-014` | 25/11/2026 | Contas / Wise | Média (Funcional / UX) | Consulta assistida de cotação de mercado em tempo real via API com cache | Concluído / Validado ✅ |

---

## Detalhamento dos Registros

### `PEND-001`: Dupla contagem de obrigações vencidas no card de Fluxo de Caixa
* **Data de Identificação:** 22/11/2026
* **Módulo / Componente:** Frontend Flutter — [dashboard_charts.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/summary/dashboard_charts.dart#L380-L388) (`CashFlowThermometerCard`).
* **Sintoma Observado:**
  Ao possuir obrigações a pagar em aberto com parcelas vencidas (ex: Copel de Outubro vencida em 10/11 por R$ 520,29 e Copel de Novembro a vencer em 10/12 por R$ 439,59, totalizando R$ 959,88 reais), o card "Fluxo de Caixa" do Dashboard exibe "Saídas & Compromissos: R$ 1.480,17" e alerta "Atenção: vai faltar R$ 1.480,17", inflando a dívida em R$ 520,29.
* **Causa Raiz:**
  Na linha 382 de [dashboard_charts.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/summary/dashboard_charts.dart#L382-L385), o cálculo do fluxo de saída soma:
  ```dart
  final totalOutflowCents =
      summary.payables.paidTotal.cents +
      summary.payables.openTotal.cents +
      summary.payables.overdueTotal.cents;
  ```
  No backend (`SpaceController.php`), o campo `open_total` já representa o universo completo de contas em aberto (tanto as vencidas quanto as vincendas). Ao somar `overdueTotal` novamente, as contas vencidas são computadas em duplicidade no termômetro visual.
* **Solução Proposta:**
  Ajustar a fórmula para somar estritamente o realizado mais o total em aberto:
  ```dart
  final totalOutflowCents =
      summary.payables.paidTotal.cents +
      summary.payables.openTotal.cents;
  ```
  Isso garantirá que o total de saídas no fluxo de caixa reflita com precisão exata os R$ 959,88 em aberto.
* **Status:** Concluído / Validado ✅ (Corrigido na branch `fix/fluxo-caixa-dupla-contagem` com suíte `make check` 100% verde, teste `AC-FIN-030` e homologação visual web desktop e mobile).

---

### `PEND-002`: Primeira ocorrência nasce sem valor mesmo quando usuário informou valor no cadastro
* **Data de Identificação:** 22/11/2026
* **Módulo / Componente:** Backend — [CreatePayable.php](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/api/app/Actions/Payables/CreatePayable.php#L113-L138) / [GenerateObligations.php](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/api/app/Actions/Payables/GenerateObligations.php#L66-L75) e Frontend de Recorrência.
* **Sintoma Observado:**
  Ao cadastrar uma conta recorrente com **Valor Variável**, o usuário digita no formulário o primeiro vencimento (ex: `09/11/2026`) e já preenche o valor daquela primeira fatura que tem em mãos (ex: `R$ 362,05`). Porém, ao salvar a recorrência, a primeira ocorrência (09/11) nasce com status `"Valor a informar"` (`amount_cents = null`), obrigando o usuário a localizá-la na lista de contas e redigitar o mesmo valor de `R$ 362,05` que havia acabado de preencher.
* **Impacto no Usuário (UX):**
  Fricção desnecessária, frustração e sensação de retrabalho ou falha do sistema ("acabei de digitar isso, por que tenho que digitar de novo?").
* **Causa Raiz:**
  Em `GenerateObligations.php`:
  ```php
  $amount = $recurrence->is_variable ? null : $recurrence->amount_cents;
  ```
  O gerador assume de forma cega que **todas** as ocorrências de uma recorrência variável devem nascer com `amount = null`, ignorando o fato de que a primeira ocorrência (ou ciclo inicial ativo) pode ter tido seu valor real informado pelo usuário no momento da criação.
* **Solução Proposta:**
  1. No fluxo de criação da recorrência (`CreatePayable::recurrence`), se o usuário informou um valor inicial no campo de valor, aplicar esse valor como `amount_cents` confirmado na primeira ocorrência (`cycle == start_date/cycle`), deixando apenas as ocorrências futuras (`cycle > start_date`) como `amount_cents = null` (aguardando valor).
  2. Alternativamente, no modal de **Revisar Ocorrências** do frontend, permitir que o usuário veja e confirme o valor das ocorrências que já possuem valor definido antes de salvar.
* **Status:** Concluído / Validado ✅ (Corrigido na branch `fix/recorrencia-variavel-valor-inicial` com `GenerateObligations.php` atribuindo o valor inicial informado à primeira ocorrência `due_date == start_date`, spec `AC-FIN-031`, suíte `make check` 100% verde com `VariableRecurrenceTest` e homologação visual Flutter Web desktop e mobile).

---

### `PEND-003`: Truncamento do label/placeholder de Valor Mensal em Recorrência Variável
* **Data de Identificação:** 22/11/2026
* **Módulo / Componente:** Frontend Flutter — [payable_form_screen.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/payables/payable_form_screen.dart#L554-L557).
* **Sintoma Observado:**
  Na tela de cadastro de conta recorrente com valor variável, o rótulo do campo de valor exibe o texto longo `"Valor mensal (opcional / a definir)"`, que estoura a largura do campo de texto e é truncado com reticências (`"Valor mensal (opcional / a de..."`), prejudicando a leitura e a estética visual.
* **Solução Proposta:**
  Simplificar a string de label para:
  ```dart
  _isVariable ? 'Valor mensal (opcional)' : 'Valor mensal'
  ```
  Isso elimina o overflow em qualquer resolução de tela (mobile e desktop) e mantém a intenção clara.
* **Status:** Concluído / Validado ✅ (Corrigido na branch `fix/recorrencia-variavel-valor-inicial` com rótulo conciso 'Valor da primeira ocorrência (opcional)', spec `AC-UI-007`, teste em `payable_form_modal_test.dart` e homologação visual Flutter Web desktop e mobile sem truncamento).

---

### `PEND-004`: Padronização visual de campos obrigatórios com asterisco (*) e validações consistentes
* **Data de Identificação:** 22/11/2026
* **Módulo / Componente:** Frontend Flutter — Todos os formulários modais (`payable_form_screen.dart`, `agreement_form_screen.dart`, `account_form_screen.dart`, etc.) compartilhados entre PF e PJ.
* **Sintoma Observado:**
  Os formulários atualmente misturam campos obrigatórios e opcionais sem uma convenção visual evidente (alguns usam "(opcional)" no label, mas os obrigatórios não possuem indicador explícito como `*`). Isso gera dúvida no usuário sobre o que é estritamente exigido antes de tentar salvar.
* **Melhoria e Padrão Sugerido:**
  1. **Convenção Universal (PF & PJ):**
     * Campos estritamente obrigatórios recebem um asterisco estilizado no label: ex: `Descrição *`, `Vencimento *`, `Valor *`. O asterisco pode ser realçado na cor primária de destaque ou vermelho suave (`#E57373` / `AppTokens.expense`).
     * Campos opcionais mantêm o sufixo suave: `Beneficiário (opcional)`, `Categoria (opcional)`.
  2. **Validação Inline e Erro Imediato:** Quando o usuário tentar avançar ou submeter sem preencher um campo obrigatório, o foco automático deve rolar até o primeiro campo inválido com mensagem clara de erro inline abaixo da caixa (ex: *"Informe a descrição da conta"*).
  3. **Reutilização Compartilhada:** Como os componentes de formulário são compartilhados tanto para Pessoa Física (PF) quanto Pessoa Jurídica (PJ), a melhoria beneficiará automaticamente ambos os contextos de uso com consistência absoluta.
* **Status:** Concluído / Validado ✅ (Implementado na branch `fix/validacao-formularios-financeiros`: convenção universal de asterisco `*` nos campos obrigatórios em A Pagar, A Receber e Contas; diferenciação dinâmica de modos fixa vs variável; validação inline com mensagem de erro adjacente; auto-scroll e foco automático no primeiro campo inválido via `focusAndEnsureVisible` em `widgets.dart`; critério de aceite `AC-UI-010` em `specs/financeiro/financeiro.md`, 12 testes de regressão em `form_validation_and_required_indicators_test.dart`, suíte Flutter com 370 testes 100% verde, backpressure completo verde e homologação no Flutter Web Chrome DevTools Desktop e Mobile com zero erros de console).

---

### `PEND-005`: Reformulação e Ergonomia Widescreen Desktop Web de Todas as Telas Principais
* **Data de Identificação:** 22/11/2026 (Expandido em 23/11/2026)
* **Módulo / Componente:** Frontend Flutter — [summary_tab.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/summary/summary_tab.dart#L81), [statement_tab.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/statement/statement_tab.dart#L127), [payables_tab.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/payables/payables_tab.dart#L330), [agreements_tab.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/agreements/agreements_tab.dart#L397), [accounts_tab.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/accounts/accounts_tab.dart) e [financial_desktop_table.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/ui/financial/financial_desktop_table.dart).
* **Sintoma Observado:**
  Em monitores desktop widescreen (1080p, 1440p, 4K), as 5 telas centrais do sistema sofrem com desproporção e falta de adaptação ergonômica:
  1. **A Pagar e A Receber:** Ficam travadas em `maxWidth: 1040`, deixando um vazio enorme nas laterais e comprimindo as colunas essenciais ("Descrição / Favorecido" e "Categoria"), que sofrem truncamento precoce com reticências.
  2. **Dashboard:** Travado em `maxWidth: 1040`, espremendo os cards de resumo e gráficos em coluna única ou comprimida no centro do monitor.
  3. **Extrato:** Travado em `maxWidth: 1040`, com transações financeiras e detalhes de conciliação comprimidos.
  4. **Contas:** Na tela de contas, os cards de bancos e carteiras não utilizam grid responsivo multi-colunas no desktop (ficam em lista vertical única ou esticados sem controle).
* **Causa Raiz:**
  Os containers de topo de todas as abas foram fixados com `constraints: const BoxConstraints(maxWidth: 1040)` herdados de uma concepção inicial mobile/tablet, em vez de aproveitar o espaço widescreen desktop homologado pelo ADR 0007.
* **Solução Proposta:**
  1. **Padronização do Grid Widescreen:** Expandir o container central para `maxWidth: 1280px` ou `1360px` (com padding lateral responsivo de 24px a 32px).
  2. **Tabelas Analíticas (A Pagar / A Receber / Extrato):** Redistribuir a proporção dos `flex` no `financial_desktop_table.dart` para dar prioridade à Descrição (`flex: 5`), Favorecido e Categoria (`flex: 3`), eliminando reticências em concessionárias e contratos.
  3. **Contas em Grid Multi-Colunas:** Na aba de Contas, renderizar as contas bancárias em grid de 2 a 3 colunas em telas largas (`GridView` responsivo), tornando a visualização da carteira muito mais limpa e executiva.
  4. **Dashboard Responsivo:** Organizar os cards em grid executivo balanceado (KPIs superiores, gráficos de fluxo lado a lado e resumo de compromissos).
* **Status:** Concluído / Validado ✅ (Implementado na branch `fix/layout-widescreen-e-despesa-paga`: padronização de `maxWidth: 1280` nas 5 telas, padding responsivo de 24px em desktop e 16px em mobile, colunas flex redistribuídas na `financial_desktop_table.dart` para 5 descrição, 3 categoria e 2 tipo, layout balanceado de compromissos e carteira lado a lado no Dashboard, e grid de 2 colunas para contas em desktop. Spec `AC-UI-008`, suíte de testes `widescreen_and_direct_expense_test.dart` e homologação real no Chrome DevTools sem erros no console).

---

### `PEND-006`: Glifos de ícones `*_rounded` invisíveis no Flutter Web (seletor de categorias)
* **Data de Identificação:** 22/11/2026
* **Módulo / Componente:** Frontend Flutter — [category_style_catalog.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/categories/category_style_catalog.dart#L32-L100) e [category_icon_color_picker.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/categories/category_icon_color_picker.dart).
* **Sintoma Observado:**
  No modal de criação/edição de categorias ("Ícone e Símbolo"), vários ícones aparecem invisíveis/em branco, exibindo apenas o pontinho colorido inferior de seleção (ex: raio de energia elétrica, gota de água, saúde, equipe/pessoas, tributos e monitor). O segundo bloco de 10 ícones (pasta, finanças, porquinho, cartão, escola, pets, posto, academia, recibo e categorias) funciona perfeitamente.
* **Causa Raiz:**
  No catálogo [category_style_catalog.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/categories/category_style_catalog.dart), foram utilizados identificadores da família `Icons.*_rounded` mais recente (ex: `Icons.bolt_rounded`, `Icons.water_drop_rounded`, `Icons.medical_services_rounded`, `Icons.groups_rounded`, `Icons.description_rounded`, `Icons.computer_rounded`). No Flutter Web, o arquivo de fontes `MaterialIcons-Regular.otf` gerado pelo build não possui os glifos dessas variantes específicas ou eles foram podados por tree-shaking, enquanto os ícones da segunda fileira utilizam codepoints clássicos do Material Icons que funcionam universalmente.
* **Solução Proposta:**
  1. Mapear os ícones do catálogo para seus equivalentes universais que possuem glifos garantidos no Flutter Web:
     * `bolt_rounded` -> `Icons.bolt` ou `Icons.flash_on` (ou SVG nativo `AppIcons`).
     * `water_drop_rounded` -> `Icons.water_drop` ou `Icons.opacity`.
     * `medical_services_rounded` -> `Icons.local_hospital` ou `Icons.healing`.
     * `groups_rounded` -> `Icons.group` ou `Icons.people`.
     * `description_rounded` -> `Icons.receipt` ou `Icons.article`.
     * `computer_rounded` -> `Icons.computer` ou `Icons.laptop`.
  2. Alternativamente, padronizar o seletor com o catálogo SVG do projeto (`AppIcons`).
* **Status:** Concluído / Validado ✅ (Corrigido na branch `fix/icones-categorias-flutter-web` com mapeamento universal no `category_style_catalog.dart` para base MaterialIcons, ajuste de `mainAxisExtent: 52` e container `height: 248` com scrollbar no `category_icon_color_picker.dart`, spec `AC-CAT-011`, testes em `category_style_catalog_web_test.dart` e homologação real no Flutter Web desktop e mobile sem erros de console).

---

### `PEND-007`: Suporte a carnês com vencimento em dias úteis e parcelas com valores reajustáveis (correção monetária)
* **Data de Identificação:** 22/11/2026
* **Módulo / Componente:** Backend (`InstallmentSchedule.php` / `MonthlyDate.php`) e Frontend Flutter (`payable_form_screen.dart` - Prévia de Parcelas).
* **Sintoma Observado:**
  Ao cadastrar um carnê de parcelamento (como contratos públicos, tributos municipais ou carnês bancários), dois fatores reais se manifestam:
  1. **Vencimento em Dia Útil:** O contrato possui uma data base (ex: dia 15). Quando o dia 15 cai em sábado, domingo ou feriado (como 15/11), o boleto impresso traz o primeiro dia útil seguinte (ex: 16/11 ou 17/05). O gerador atual fixa cegamente o dia 15 em todos os meses.
  2. **Correção Monetária / Juros Mensais:** As parcelas de carnês pré-impressos frequentemente aumentam alguns centavos/reais mês a mês (ex: 5/18 = R$ 135,17; 6/18 = R$ 136,44; 7/18 = R$ 137,73). O gerador atual divide um valor total estático em partes iguais.
* **Causa Raiz:**
  `InstallmentSchedule::generate` projeta datas civis puras (`MonthlyDate::in`) sem considerar calendário bancário/dias úteis e assume valor fixo linear para todas as parcelas.
* **Solução Proposta:**
  1. Na tela de **Prévia de Parcelas**, permitir ao usuário editar inline o valor e a data de cada parcela individual antes de salvar o plano no banco de dados.
  2. Adicionar opção no cadastro: `"Ajustar vencimento para o próximo dia útil se cair em fim de semana/feriado"` (opcional/configurável).
* **Status:** Concluído / Validado ✅ (Implementado na branch `feature/carnes-parcelas-editaveis` com edição individual inline de vencimentos e valores na prévia de parcelamento em `PayableFormScreen`, recálculo em tempo real do total na badge, validação backend de consistência da soma exata de centavos e integridade sequencial/temporal em `PayableController`, persistência das parcelas customizadas em `CreatePayable` preservando a geração determinística padrão quando omitidas, specs `AC-FIN-032`, `AC-UI-011` e `AC-FIN-033` [ajuste de dias úteis com decisão pendente para Jeann Lucas], suítes de teste `EditableInstallmentPlanTest.php` e `editable_installment_schedule_test.dart`, validação completa `./scripts/check.sh --full` 100% verde e homologação no Flutter Web real com Chrome DevTools MCP em Desktop 1280x800 e Mobile 375x812 com zero erros no console).

---

### `PEND-008`: Dropdown de categorias exibe lista plana desordenada sem hierarquia visual em árvore
* **Data de Identificação:** 23/11/2026
* **Módulo / Componente:** Frontend Flutter — [category_picker_field.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/categories/category_picker_field.dart#L235-L297) e Backend [CategoryController.php](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/api/app/Http/Controllers/Api/CategoryController.php#L19).
* **Sintoma Observado:**
  Ao abrir o seletor de categorias em qualquer formulário financeiro (contas a pagar, a receber, etc.):
  1. As categorias são apresentadas em uma lista plana, com pais misturados no topo e subcategorias abaixo repetindo a string `"CATEGORIA PAI > NOME DA SUBCATEGORIA"`.
  2. As subcategorias não estão agrupadas logo abaixo de seus respectivos pais nem ordenadas por árvore (ex: `ÁGUA E SANEAMENTO` ficou isolada no final da lista, após `EMPRÉSTIMOS E FINANCIAMENTOS > MERCADO PAGO`).
  3. Não há recuo visual ou indentação (`margin-left` ou `↳`) para expressar hierarquia.
  4. Quando uma subcategoria é selecionada, o texto longo estoura a largura do campo de input e é truncado com reticências (ex: `EMPRÉSTIMOS E FINANCIAMENTOS > MERCADO PAG...`).
* **Causa Raiz:**
  * O backend faz uma ordenação alfabética simples (`orderBy('name')`), sem montar a árvore pai-filho.
  * O frontend no `DropdownMenuItem` renderiza diretamente `cat.fullName` em vez de agrupar por categoria pai e identar as subcategorias.
* **Solução Proposta:**
  1. **Ordenação Hierárquica:** No backend ou no repository Flutter, estruturar a lista sempre em árvore: Categoria Pai ➔ seguida imediatamente de suas subcategorias ordenadas alfabeticamente.
  2. **Hierarquia Visual no Menu:**
     * Categorias Pai recebem destaque visual (negrito ou fundo sutil/divisor de grupo).
     * Subcategorias exibem apenas o seu nome próprio com recuo/indentação de 20px e um marcador sutil (ex: `↳ Mercado Pago`), sem poluir repetindo o nome do pai.
  3. **Exibição Elegante no Campo Fechado:** Quando selecionada uma subcategoria, exibir com destaque o nome da subcategoria e, como subtítulo suave ou tag discreta, o nome do pai (ex: **`MERCADO PAGO`** • `Empréstimos e Financiamentos`), evitando truncamento precoce.
* **Status:** Concluído / Validado ✅ (Corrigido na branch `fix/seletor-categorias-hierarquico` com ordenação e agrupamento em árvore em `CategoryPickerField.organizeHierarchy`, recuo visual de 20px com marcador `↳`, nome próprio em subcategorias, formatação elegante em `selectedItemBuilder` no campo fechado, spec `AC-CAT-012`, teste de regressão em `category_picker_hierarchy_test.dart` e homologação real no Flutter Web desktop e mobile sem erros de console).

---

### `PEND-009`: Suporte a Recebimentos Recorrentes (fixos e variáveis) no módulo A Receber
* **Data de Identificação:** 23/11/2026
* **Módulo / Componente:** Backend (`AgreementController.php` / `Recurrence.php`) e Frontend Flutter (`agreement_form_screen.dart`).
* **Sintoma Observado:**
  No módulo de **Contas a Pagar** (`Payables`), o sistema possui o tipo **Recorrente** completo, com suporte a valores fixos e variáveis (ex: contas de luz, água, internet). No entanto, no módulo de **Contas a Receber** (`Agreements`), só existem as opções **Avulsa** e **Parcelada**. Para salários recorrentes, contratos mensais de prestação de serviços ou receitas variáveis de negócios, não há mecanismo de recorrência em A Receber, forçando o usuário a lançar contratos parcelados artificiais ou contas avulsas todo mês.
* **Causa Raiz:**
  O modelo `Recurrence` e a action `GenerateObligations` foram concebidos originalmente no escopo de contas a pagar (`payables`). O módulo `agreements` opera exclusivamente com planos parcelados de acordos (`installments`).
* **Solução Proposta:**
  1. Expandir o conceito de Recorrência para o universo de Receitas (`income`), permitindo cadastrar receitas mensais recorrentes (salário, aluguel recebido, honorários) com valor fixo ou valor variável (`amount = null` a definir).
  2. No frontend, adicionar a aba **Recorrente** no `AgreementFormScreen` com a mesma ergonomia do contas a pagar.
* **Status:** Concluído / Validado ✅ (Implementado na branch `feature/receitas-recorrentes` com suporte a receitas recorrentes fixas e variáveis com valor inicial opcional para a 1ª ocorrência, geração sob demanda e horizonte de planejamento de 12 meses via `GenerateReceivables`, idempotência persistida por chave única por espaço, liquidação e estorno atômicos via `ReceiveInstallment` e contra-movimentação contábil, critérios formais `AC-FIN-034`, `AC-FIN-035`, `AC-FIN-036` e `AC-UI-012`, 10 testes de feature da API, 4 novos testes de widget e formulário Flutter, suíte completa de Backpressure 100% verde com ZERO erros e homologação visual real no Flutter Web em desktop 1280x800 e mobile 375x812 com ZERO erros de console).

---

### `PEND-010`: Redesenho do botão "Registrar despesa paga (débito em conta)" no Dashboard
* **Data de Identificação:** 23/11/2026
* **Módulo / Componente:** Frontend Flutter — [summary_tab.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/summary/summary_tab.dart#L562-L578) (`_QuickActionsGroup`).
* **Sintoma Observado:**
  No Dashboard, o botão de ação rápida para registrar compra imediata no débito:
  1. **Estiramento Desengonçado:** O botão possui `minimumSize: const Size.fromHeight(40)` sem restrição de largura máxima, ficando esticado de ponta a ponta na tela widescreen (efeito de "linguiça" horizontal vazia).
  2. **Rótulo Longo e Burocrático:** O texto `"Registrar despesa paga (débito em conta)"` é cansativo e técnico demais para uma ação cotidiana e rápida.
  3. **Estilo Isolado:** A borda fina vermelha com fundo transparente escuro parece desconectada do resto dos botões de ação do Dashboard.
* **Causa Raiz:**
  Foi inserido como um `OutlinedButton.icon` isolado logo abaixo da linha de botões de atalho, herdando a largura total da coluna pai.
* **Solução Proposta:**
  1. **Encurtar o Rótulo:** Simplificar o texto para uma linguagem direta e concisa: `"Registrar despesa paga"`.
  2. **Controle de Largura Widescreen:** Limitar a largura máxima (`maxWidth: 320px`) em desktop alinhado à esquerda na seção de ações rápidas, e largura total com altura mínima ergonômica de 44px em mobile.
  3. **Design Integrado:** Transformar o botão em uma ação integrada com estilo tonal moderno (`FilledButton.tonalIcon` com tintura suave coral/despesa e ícone `Icons.receipt_long_rounded`).
* **Status:** Concluído / Validado ✅ (Implementado na branch `fix/layout-widescreen-e-despesa-paga`: botão transformado em `FilledButton.tonalIcon` com `maxWidth: 320` alinhado à esquerda no desktop e full width 44px no mobile, label "Registrar despesa paga", ícone de recibo tonal, spec `AC-UI-009`, teste `widescreen_and_direct_expense_test.dart` e homologação no Chrome DevTools sem erros de console).

---

### `PEND-011`: Campo de valor das parcelas no cronograma aceita letras e caracteres não numéricos
* **Data de Identificação:** 24/11/2026
* **Módulo / Componente:** Frontend Flutter — [payable_form_screen.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/payables/payable_form_screen.dart) (Prévia do Cronograma de Parcelas / Carnês `schedule-amount-N`).
* **Sintoma Observado:**
  Ao abrir a prévia de parcelamento ("Ver cronograma" / carnê de parcelas customizáveis) no formulário de Contas a Pagar, o campo de texto para ajuste do valor individual da parcela permite a inserção livre de letras e caracteres alfabéticos arbitrários (ex: "abc", "reais"), em vez de restringir estritamente a números e centavos válidos de moeda brasileira (`R$`).
* **Causa Raiz:**
  Nos campos `TextFormField` com chaves `schedule-amount-${item.number}` em `payable_form_screen.dart`, foi definido apenas `keyboardType: const TextInputType.numberWithOptions(decimal: true)`. No Flutter Web e em navegadores desktop com teclado físico, `keyboardType` não bloqueia a entrada de caracteres alfabéticos sem um `inputFormatter` ativo (como `MoneyInputFormatter` ou `FilteringTextInputFormatter.digitsOnly`). Além disso, se o usuário digitar letras, o parser de centavos pode falhar silenciosamente ou zerar o valor.
* **Solução Proposta:**
  1. Adicionar máscara monetária ou filtro de entrada estrito (`inputFormatters: [MoneyInputFormatter()]` ou formatador numérico de centavos compatível) nos `TextFormField` de valor da parcela no cronograma.
  2. Garantir que apenas dígitos válidos sejam digitados e que a formatação visual reflita valores em Real (`R$ 0,00`) com atualização em tempo real do badge de total.
  3. Adicionar teste automatizado de widget garantindo que caracteres não numéricos sejam rejeitados nos inputs do cronograma.
* **Status:** Publicado / Validado ✅ (v1.5.1). O teste AC-UI-015 confirmou que o campo descarta letras e conserva o total exato.

---

### `PEND-012`: Ícones invisíveis no modal Nova Categoria em produção

* **Data de Identificação:** 24/11/2026.
* **Ambiente:** Web em produção, release `v1.5.0`, em **Categorias Financeiras → Nova Categoria → Ícone e Símbolo**.
* **Sintoma Observado:** A captura mostra os pontos de cor e o contorno da seleção, com os símbolos da grade invisíveis. Isso impede distinguir as opções visualmente.
* **Evidência Técnica:** A fonte pública `/assets/fonts/MaterialIcons-Regular.otf` da release contém os glifos de Moradia, Energia elétrica e Água e saneamento. A URL é fixa e a resposta usa `Cache-Control: public, max-age=31536000, immutable`.
* **Hipótese a Confirmar:** O navegador pode estar reutilizando uma versão antiga da fonte. Comparar a mesma tela no perfil afetado e em uma janela anônima ou perfil limpo e verificar a resposta da fonte na aba Rede.
* **Solução Proposta:** Se o cache for confirmado, versionar a URL da fonte por build ou por hash de conteúdo para que a próxima publicação carregue o arquivo correspondente. Validar em perfil limpo e em perfil com cache da versão anterior, verificando a grade ao criar e editar uma categoria.
* **Relação:** Sintoma relacionado a `PEND-006`, com hipótese de causa distinta e ainda em investigação.
* **Status:** Publicado na v1.5.1 / Validação visual pendente ⏳. A fonte e o manifesto versionados carregaram com HTTP 200 em produção após uma recarga normal no Chrome, a partir de um perfil que havia carregado a v1.5.0.

---

### `PEND-013`: Carteira multimoeda para contas Wise

* **Escopo:** Cadastro de moedas sob a conta Wise, saldos iniciais por moeda, transferências em BRL, conversões manuais auditáveis e equivalente estimado em BRL com data da cotação.
* **Catálogo:** A instituição Wise e seu ícone já constam no catálogo (AC-FIN-027).
* **Status:** Implementado localmente na branch `feature/carteira-wise`. Critérios `AC-WISE-001` a `AC-WISE-008`, incluindo os saldos por moeda no Dashboard. Suíte e build Web aprovados. Publicado na v1.6.0, com migrações concluídas e API e Web verificados em produção.

---

### `PEND-014`: Consulta de cotação de mercado em tempo real na Carteira Wise

* **Escopo:** Endpoint `GET /api/spaces/{space}/accounts/{account}/wise/currencies/{currency}/market-rate` no Laravel com cache de 15 minutos e consumo da AwesomeAPI. Botão com feedback de progresso no modal de cotação da Wise (`_WiseEditor`) no Flutter, preenchendo valor e data automaticamente sem bloquear edição manual.
* **Critério:** `AC-WISE-010`.
* **Status:** Concluído e homologado com `./scripts/check.sh --full` 100% verde (398 testes Flutter e 234 testes Laravel). Aprovado por Jeann Lucas para release v2.2.0.
