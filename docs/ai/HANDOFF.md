# BigDev.Z Finance — Transição Operacional (Handoff)

> **Data de Atualização:** 15/11/2026
> **Branch Atual:** `feature/gaps-pagamentos-categorias-encargos` (a partir da `dev`)
> **Status de Qualidade:** ✅ BACKPRESSURE 100% VERDE (`./scripts/check.sh --full` e `make check`)
> **Autorização de Publicação:** Concedida formalmente por Jeann Lucas para execução controlada da pipeline até a VPS.

---

## 1. Contexto Imediato e Escopo Concluído

Atendendo às solicitações de auditoria independente e implementação dos gaps funcionais, foram validadas e testadas diretamente as frentes:

1. **Estorno e Correção de Pagamentos de Contas a Pagar (`AC-PAY-REV-001..006`):**
   - Histórico audível completo com listagem na Web Desktop e Mobile.
   - Diálogo com prévia de impacto (crédito no banco e reabertura do principal na obrigação).
   - Justificativa obrigatória (mínimo 3 caracteres).
   - Bloqueio de estorno duplicado e idempotência persistida (`Idempotency-Key`).
   - Imutabilidade contábil: proibição de exclusão física (`DELETE`), estorno gera contra-movimentação positiva.

2. **Edição de Categoria de Contas a Pagar (`AC-PAY-CAT-001..006`):**
   - Endpoint `PATCH /api/spaces/{space}/payables/{payable}` aceita `category_id` (inteiro ou `null` para desvincular).
   - Validação estrita de `space_id` e tipo `expense`. Categorias inexistentes, inativas ou de receita retornam `404 Not Found`.
   - Histórico em `obligation_changes` registrando `category_id` anterior e novo.
   - Permitido editar antes ou depois da liquidação, sem tocar em saldos ou movimentações bancárias passadas.

3. **Juros, Multa e Desconto no Pagamento (`AC-PAY-INT-001..007`):**
   - Matemática financeira estrita em centavos inteiros de 64 bits (zero `float`/`double`).
   - `PaymentSettlement.php`: Total = Principal + Juros + Multa - Desconto (com teto de desconto no subtotal).
   - Tabela `payments` com colunas migradas e 6 constraints CHECK no PostgreSQL.
   - Baixa e estorno testados: R$ 100,00 principal + R$ 15,00 juros = R$ 115,00 debitados do banco e R$ 100,00 amortizados; estorno credita R$ 115,00 e reabre R$ 100,00.

4. **Padronização de Linguagem e UX Writing (`AC-UX-WRITING-001`):**
   - Eliminação de jargões técnicos: "obrigação" substituído por "conta a pagar", "baixa" por "registrar pagamento", "reversão" por "estorno", "principal" por "valor original".
   - Alinhamento consistente em telas Web, Mobile, mensagens de erro e respostas da API.

5. **Bootstrap e Reproduzibilidade Local:**
   - Comando oficial do Laravel Artisan (`user:create`) para inicialização idempotente com normalização de e-mail e geração segura de credenciais de desenvolvimento sem manipulação manual de banco.

---

## 2. Resultado das Verificações Automatizadas (Quality Gate)

O comando `./scripts/check.sh --full` rodou no terminal do Mac e retornou código de saída 0:

- **Domínio Financeiro PHP (`tests/domain.php`):** 14/14 testes passaram.
- **Linter Laravel Pint (`apps/api`):** 161 arquivos em conformidade.
- **Análise Estática Dart (`flutter analyze`):** 0 issues encontrados.
- **Formatação Dart (`apps/mobile`):** 158 arquivos validados (0 alterações pendentes).
- **Suíte Flutter (`flutter test`):** 295 testes executados, 295 aprovados (0 falhas).
- **Suíte de Integração Laravel (`php artisan test`):** 195 testes executados, 1821 asserções aprovadas (0 falhas) em banco PostgreSQL real.

---

## 3. Lote de Commits Atômicos

1. `9983077` — `feat(financeiro): suporta encargos e descontos em pagamentos`
2. `fddead9` — `feat(api): permite reclassificar categoria de conta a pagar`
3. `f534c61` — `feat(api): aprimora login case-insensitive e comando de usuario de desenvolvimento`
4. `0a82a2d` — `feat(mobile): disponibiliza historico, encargos, estorno e reclassificacao de categoria`
5. `0433dd8` — `refactor(ux): padroniza linguagem financeira em pt-BR eliminando jargoes tecnicos`
6. `docs: atualiza especificacoes financeiras e handoff operacional`

---

## 4. Ambiente Local e Bootstrap Reproduzível

- **API Base:** `http://127.0.0.1:8000/api`
- **Web Frontend:** `http://127.0.0.1:8085` (ou `http://localhost:8085`)
- **Criação de Usuário de Desenvolvimento:**
  ```bash
  docker exec finance-api-dev php artisan user:create SEU_EMAIL_DE_DESENVOLVIMENTO --name="Nome do Desenvolvedor" --password="SUA_SENHA_LOCAL"
  ```
