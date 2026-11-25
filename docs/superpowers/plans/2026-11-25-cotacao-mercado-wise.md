# Consulta de Cotação de Mercado na Carteira Wise — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar funcionalidade para consultar cotação de mercado em tempo real via AwesomeAPI com cache no backend Laravel e botão de preenchimento automático no modal de cotação da Carteira Wise.

**Architecture:** Novo endpoint `GET /api/spaces/{space}/accounts/{account}/wise/currencies/{currency}/market-rate` no Laravel com cache de 15 minutos e timeout curto (5s) para consulta da AwesomeAPI (`https://economia.awesomeapi.com.br/last/{currency}-BRL`). No Flutter, método no `AccountsRepository` e botão com feedback visual no modal `_WiseEditor` que preenche o campo com a cotação comercial e define a data de hoje.

**Tech Stack:** Laravel 13, PHP 8.3+, Illuminate Http Client, Cache, Flutter / Dart 3.x, AwesomeAPI.

**Spec:** [docs/superpowers/specs/2026-11-25-cotacao-mercado-wise-design.md](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/docs/superpowers/specs/2026-11-25-cotacao-mercado-wise-design.md) e [specs/carteira-wise/carteira-wise.md](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/specs/carteira-wise/carteira-wise.md).

## Global Constraints

- Proibido uso de float ou double para cálculos ou armazenamento financeiro (strings decimais canônicas na API, inteiros no domínio).
- Isolamento multi-tenant por espaço (`space_id`) e validação de conta Wise ativa.
- Cache de 15 minutos no backend para evitar requisições excessivas à API externa.
- Falha graciosa: se a API externa oscilar ou a moeda não tiver cotação, retornar mensagem amigável sem bloquear o preenchimento manual no Flutter.
- Backpressure mandatória: `./scripts/check.sh --full` 100% verde antes de qualquer entrega.
- Commits e pushes sob autoridade exclusiva de Jeann Lucas.

## Review Focus

1. **Moeda com código em minúsculo ou maiúsculo:** a rota deve tratar e validar o código ISO da moeda de forma insensível a maiúsculas/minúsculas (`strtoupper`).
2. **Moeda não suportada pela API externa (ex: moeda exótica sem par BRL):** responder HTTP 422 com mensagem explicativa sem lançar exceção 500 não tratada.
3. **Timeout ou indisponibilidade da API externa:** captura de `ConnectionException` ou resposta sem sucesso tratada com mensagem amigável ("Cotação de mercado indisponível no momento. Digite manualmente.").
4. **Substituição de valor já digitado:** ao tocar em buscar cotação, o campo é preenchido com a taxa, mas permanece 100% editável pelo usuário antes de salvar.
5. **Permissão de usuário:** rota protegida garantindo que o usuário pertence ao espaço e tem permissão (`adjust_opening_balance`).

---

### Task 1: Atualização da Spec Permanente (L2)

**Files:**
- Modify: `specs/carteira-wise/carteira-wise.md:37-45`

**Interfaces:**
- Produces: Critério `AC-WISE-010 — Consulta de cotação de mercado` na documentação canônica de contratos.

- [ ] **Step 1: Adicionar critério AC-WISE-010 e atualizar matriz de rastreabilidade**
  Adicionar a especificação de consulta de cotação de mercado via endpoint autenticado e preenchimento assistido no modal da Carteira Wise.

- [ ] **Step 2: Verificar integridade do arquivo**
  Executar: `git diff specs/carteira-wise/carteira-wise.md`
  Verificar que apenas o novo critério e linha na matriz foram adicionados.

---

### Task 2: Backend — Endpoint de Cotação de Mercado com Cache

**Files:**
- Modify: `apps/api/routes/api.php`
- Modify: `apps/api/app/Http/Controllers/Api/WiseWalletController.php`
- Test: `apps/api/tests/Feature/WiseWalletTest.php`

**Interfaces:**
- Produces: `GET /api/spaces/{space}/accounts/{account}/wise/currencies/{currency}/market-rate` retornando:
  ```json
  {
    "data": {
      "currency": "EUR",
      "target": "BRL",
      "rate": "6.4457",
      "quoted_on": "2026-11-25"
    }
  }
  ```
- Consumes: `Illuminate\Support\Facades\Http`, `Illuminate\Support\Facades\Cache`, `App\Domain\Wise\Currency::SCALES`.

- [ ] **Step 1: Escrever teste de feature no backend que falha inicialmente**
  Em `apps/api/tests/Feature/WiseWalletTest.php`, adicionar métodos:
  - `test_market_rate_returns_quoted_rate_and_caches_response()`: com `Http::fake()`, validar retorno 200, formato da taxa e que segunda chamada não faz nova requisição HTTP (cache).
  - `test_market_rate_validates_currency_and_handles_api_failure()`: testar moeda inválida/BRL (422) e falha de conexão (422 com mensagem amigável).

- [ ] **Step 2: Executar teste para verificar falha**
  Executar: `cd apps/api && php artisan test --filter=WiseWalletTest`
  Resultado esperado: FAIL (rota `market-rate` inexistente / 404).

- [ ] **Step 3: Implementar rota e método `marketRate` em `WiseWalletController.php`**
  - Registrar a rota `GET /accounts/{account}/wise/currencies/{currency}/market-rate` em `apps/api/routes/api.php`.
  - No `WiseWalletController.php`:
    - Validar que a conta pertence ao espaço e tem `bank_id === 'wise'`.
    - Normalizar moeda para maiúsculo e validar que existe em `Currency::SCALES` e é diferente de `BRL`.
    - Verificar `Cache::remember("wise:rate:{$space->id}:{$currency}", now()->addMinutes(15), ...)` (ou cache por moeda).
    - Executar `Http::timeout(5)->get("https://economia.awesomeapi.com.br/last/{$currency}-BRL")`.
    - Extrair campo `bid` da chave `"{$currency}BRL"`. Se não existir ou falhar, lançar `ValidationException` com mensagem amigável.
    - Retornar JSON padronizado com `currency`, `target`, `rate` e `quoted_on`.

- [ ] **Step 4: Executar testes para verificar sucesso**
  Executar: `cd apps/api && php artisan test --filter=WiseWalletTest`
  Resultado esperado: PASS (todos os testes verdes).

---

### Task 3: Frontend — Cliente API e Repositório

**Files:**
- Modify: `apps/mobile/lib/features/accounts/accounts_repository.dart`
- Modify: `apps/mobile/lib/features/accounts/wise_currency.dart`
- Test: `apps/mobile/test/features/wise_dashboard_test.dart` (ou teste de repositório)

**Interfaces:**
- Produces: `WiseMarketRate` model e método `AccountsRepository.fetchWiseMarketRate(int spaceId, int accountId, String currency) -> Future<WiseMarketRate>`.
- Consumes: `ApiClient.get`.

- [ ] **Step 1: Escrever teste unitário para `fetchWiseMarketRate`**
  Verificar decodificação correta de `WiseMarketRate` a partir da resposta JSON e formatação do valor.

- [ ] **Step 2: Executar teste para verificar falha**
  Executar: `cd apps/mobile && flutter test test/features/wise_dashboard_test.dart`
  Resultado esperado: FAIL (método não existe).

- [ ] **Step 3: Implementar modelo `WiseMarketRate` e método em `AccountsRepository`**
  - Em `wise_currency.dart`: criar classe `WiseMarketRate(this.currency, this.rate, this.quotedOn)`.
  - Em `accounts_repository.dart`: implementar `fetchWiseMarketRate(int spaceId, int accountId, String currency)` chamando `client.get('/spaces/$spaceId/accounts/$accountId/wise/currencies/$currency/market-rate')`.

- [ ] **Step 4: Executar teste para verificar sucesso**
  Executar: `cd apps/mobile && flutter test test/features/wise_dashboard_test.dart`
  Resultado esperado: PASS.

---

### Task 4: Frontend — Botão de Busca de Cotação no Modal (`_WiseEditor`)

**Files:**
- Modify: `apps/mobile/lib/features/accounts/wise_wallet_panel.dart`
- Test: `apps/mobile/test/features/wise_wallet_panel_test.dart`

**Interfaces:**
- Produces: Botão *"Buscar cotação de mercado"* visível no modal quando `kind == _EditKind.quote`.
- Consumes: Callback `Future<WiseMarketRate> Function()? onFetchRate`.

- [ ] **Step 1: Escrever teste de widget para o botão no modal de cotação**
  Criar/atualizar teste verificando que ao abrir o modal de cotação:
  - O botão *"Buscar cotação de mercado"* está presente.
  - Ao ser clicado, chama o callback, preenche o `TextFormField` com a taxa e atualiza a data.

- [ ] **Step 2: Executar teste para verificar falha**
  Executar: `cd apps/mobile && flutter test test/features/wise_wallet_panel_test.dart`
  Resultado esperado: FAIL (botão não encontrado).

- [ ] **Step 3: Implementar botão e integração no `wise_wallet_panel.dart`**
  - Adicionar parâmetro `onFetchRate` em `_showEditor` e `_WiseEditor`.
  - No `_WiseWalletPanel`, ao abrir editor de `_EditKind.quote`, passar closure chamando `repository.fetchWiseMarketRate(spaceId, account.id, currency.code)`.
  - No `_WiseEditor`:
    - Adicionar estado `bool _fetchingRate = false;`.
    - Quando `kind == _EditKind.quote`, renderizar botão `OutlinedButton.icon` com ícone `Icons.trending_up` (ou `Icons.currency_exchange`), texto *"Buscar cotação de mercado"* e indicador `SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))` se `_fetchingRate`.
    - Ao tocar: chamar `onFetchRate()`, preencher `_value.text = rate.rate`, `_date = rate.quotedOn` (ou DateTime.now()) e limpar `_error`.
    - Em caso de exceção (`ApiException`), capturar e exibir mensagem amigável em `_error`.

- [ ] **Step 4: Executar teste de widget para verificar sucesso**
  Executar: `cd apps/mobile && flutter test test/features/wise_wallet_panel_test.dart`
  Resultado esperado: PASS.

---

### Task 5: Backpressure Completa e Validação Determinística

**Files:**
- Todo o repositório

**Interfaces:**
- Consumes: `make check` / `./scripts/check.sh --full`.

- [ ] **Step 1: Executar suíte completa de qualidade**
  Executar no terminal: `./scripts/check.sh --full`
  Verificar que todos os 6 checks rodam 100% verdes:
  1. Domínio financeiro PHP (`php tests/domain.php`)
  2. Pint (`vendor/bin/pint --test`)
  3. Flutter analyze (`flutter analyze`)
  4. Dart format (`dart format --output=none --set-exit-if-changed`)
  5. Testes Flutter (`flutter test`)
  6. Testes Laravel com PostgreSQL real (`php artisan test`)

- [ ] **Step 2: Apresentar relatório de entrega padronizado a Jeann Lucas**
  Apresentar o que foi feito, critérios atendidos, arquivos alterados e comprovação dos testes com zero erros, sem commit/push (aguardando autorização humana).
