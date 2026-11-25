# Design: Consulta de Cotação de Mercado na Carteira Wise

- **Data:** 25/11/2026
- **Status:** Proposto para aprovação
- **Autoridade:** Padrão Oficial BigDev.Z de Jeann Lucas
- **Domínio:** Carteira multimoeda Wise / Cotações para equivalente estimado em BRL

---

## 1. Contexto e Motivação
Na Carteira Wise do BigDev.Z Finance, moedas estrangeiras (como EUR e USD) mantêm saldos segregados e independentes do saldo em reais (BRL). Para calcular o **Equivalente estimado em BRL** da carteira ([AC-WISE-006](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/specs/carteira-wise/carteira-wise.md#L30-L36)), o usuário informa uma cotação manual.

Atualmente, o usuário precisa sair do app, pesquisar a cotação comercial do dia em fontes externas e digitar manualmente o valor unitário. O objetivo desta melhoria é fornecer um botão no próprio modal de cotação para consultar a cotação de mercado com um clique, preenchendo o formulário com a taxa do dia e mantendo a possibilidade de edição manual antes da confirmação.

---

## 2. Abordagens Consideradas

1. **Abordagem 1 (Escolhida pelo Mantenedor):** Endpoint no Backend Laravel com Cache + Botão no Modal
   - O backend expõe `GET /api/spaces/{space}/wise/rates/{currency}` e consulta a AwesomeAPI (`https://economia.awesomeapi.com.br/last/{currency}-BRL`).
   - Aplica cache de 15 minutos em memória/Redis para evitar requisições redundantes à API externa.
   - O Flutter chama este endpoint interno seguro e preenche o formulário.
   - *Por que foi escolhida:* Arquitetura limpa, desacoplamento do cliente contra mudanças em APIs de terceiros, controle de cache e segurança sob o ecossistema do BigDev.Z.

2. **Abordagem 2 (Descartada):** Chamada direta do Flutter para a AwesomeAPI via HTTP client-side
   - Descartada por expor e acoplar o aplicativo diretamente a fornecedores externos sem camada de governança e sem cache centralizado.

---

## 3. Metas e Não-Metas

### Metas (Goals)
- Criar endpoint `GET /api/spaces/{space}/wise/rates/{currency}` no Laravel, autenticado e autorizado.
- Integrar com a AwesomeAPI com timeout curto (5s) e cache de 15 minutos.
- Formatar a taxa de compra (`bid`) comercial como string decimal com precisão (ex: `"6.4457"`).
- Fornecer no Flutter um botão com feedback visual (*"Buscar cotação de mercado"* com indicador de carregamento) no modal de cotação.
- Ao obter a cotação, preencher o campo de valor e definir a data de referência como hoje.
- Se a cotação externa falhar ou a moeda não tiver cotação disponível, exibir mensagem amigável sem bloquear a digitação manual.
- Suíte automatizada com 100% de cobertura no backend (PHPUnit com `Http::fake()`) e frontend (Flutter test com mock).

### Não-Metas (Non-Goals)
- Não realiza conversão automática de saldos ou débitos/créditos em moedas.
- Não dispensa a revisão e confirmação humana: a cotação só é persistida quando o usuário clica em **Revisar** $\rightarrow$ **Confirmar**.
- Não cadastra cron jobs autônomos sem intervenção do usuário.

### Anti-Metas (Anti-Goals)
- Proibido bloquear a interface ou impedir o preenchimento manual caso o serviço externo esteja offline.
- Proibido usar float/double para representação ou cálculo financeiro.

---

## 4. Contratos de Dados e Comportamento

### 4.1 Backend (Laravel)
- **Rota:** `GET /api/spaces/{space}/wise/rates/{currency}`
- **Autorização:** Usuário autenticado com permissão `adjust_opening_balance` no espaço.
- **Validação:** `$currency` deve ser uma moeda suportada da Wise diferente de BRL (`EUR`, `USD`, `GBP`, `CAD`, `AUD`, `CHF`, `JPY`, etc.).
- **Resposta de Sucesso (HTTP 200):**
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
- **Resposta de Falha / Indisponibilidade (HTTP 422 / 503):**
  ```json
  {
    "message": "Cotação de mercado não disponível para esta moeda no momento."
  }
  ```

### 4.2 Frontend (Flutter)
- Em `AccountsRepository`: método `Future<WiseMarketRate> fetchWiseMarketRate(int spaceId, String currency)`.
- Em `_WiseEditor` ([wise_wallet_panel.dart](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/apps/mobile/lib/features/accounts/wise_wallet_panel.dart)):
  - Quando `kind == _EditKind.quote`:
    - Exibe botão tonal/outline com ícone: *"Buscar cotação de mercado"*.
    - Ao clicar, exibe estado de progresso (`_fetchingRate`).
    - No sucesso, preenche `_value.text` com a taxa formatada e `_date = DateTime.now()`.
    - No erro, exibe mensagem clara permitindo continuar digitando manualmente.

---

## 5. Rastreabilidade e Critério de Aceite (Spec Permanente)
- Será adicionado o critério **AC-WISE-010 — Consulta de cotação de mercado** em [specs/carteira-wise/carteira-wise.md](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/specs/carteira-wise/carteira-wise.md).
