# Contrato da API (BigDev.Z Finance)

Base local: `http://127.0.0.1:8000/api`. JSON em todas as respostas. Rotas em
`apps/api/routes/api.php`; testes de contrato em `apps/api/tests/Feature`.

## Convenções

- **Dinheiro**: string com ponto e duas casas (`"2000.00"`), de `"0.00"` a
  `"999999999999.99"`. Números JSON, vírgula ou mais casas são recusados (422).
  Decisão 0002.
- **Datas de calendário**: `AAAA-MM-DD`, sem fuso. "Hoje" usa
  `America/Sao_Paulo` (`FINANCE_TIMEZONE`).
- **Autenticação**: `Authorization: Bearer <token>` emitido no login (Sanctum).
- **Isolamento**: todo recurso fica sob `/spaces/{space}`. Espaço, conta, acordo
  ou parcela de outro usuário, ou de outro espaço, responde `404` sem dados.
- **Erros**: `422` validação (`errors` por campo; com `idempotency.status:
  rejected` quando a recusa ficou registrada para a chave), `401` sessão
  inválida, `404` não encontrado, `409` chave idempotente reutilizada com outro
  conteúdo,
  `429` excesso de tentativas de login (5 por minuto por e-mail e IP).

## Endpoints

| Método | Caminho | Descrição |
| --- | --- | --- |
| POST | `/auth/login` | `{email, password, device_name}` → `{token, user}` |
| POST | `/auth/logout` | Revoga o token atual (`204`) |
| GET | `/me` | Usuário autenticado |
| GET | `/spaces` | Espaços PF e PJ do usuário |
| GET | `/spaces/{space}/summary` | Saldo efetivado, a receber, recebido, vencidas |
| GET, POST | `/spaces/{space}/accounts` | Lista / cria conta com saldo inicial |
| GET | `/spaces/{space}/accounts/{account}` | Conta com saldo atual e correções de abertura |
| PATCH | `/spaces/{space}/accounts/{account}` | Renomeia (`{name}`); abertura e espaço não mudam aqui |
| POST | `/spaces/{space}/accounts/{account}/opening-adjustment` | Corrige saldo inicial/data de abertura (`{opening_balance, opening_balance_date, reason}`, com `Idempotency-Key`) |
| POST | `/spaces/{space}/accounts/{account}/archive` | Arquiva (sem mudar dinheiro) |
| POST | `/spaces/{space}/accounts/{account}/unarchive` | Reativa |
| GET, POST | `/spaces/{space}/payables` | Lista (`?status=all\|open\|overdue\|paid\|cancelled\|awaiting_amount`) / cadastra com `Idempotency-Key`: `kind` `single` (`amount`, `due_date`), `installment` (`total`, `installment_count`, `first_due_date`) ou `recurring` (`amount`, `start_date`, `end_date?`) |
| POST | `/spaces/{space}/payables/preview` | Cronograma parcelado, sem gravar |
| GET, PATCH | `/spaces/{space}/payables/{payable}` | Detalhe com pagamentos e `changes` / edita esta obrigação (em fatura, informa o total) |
| POST | `/spaces/{space}/payables/{payable}/cancel` | Cancela (`{reason}`), só sem pagamento ativo |
| POST | `/spaces/{space}/payables/{payable}/payments` | Pagamento (`{account_id, amount, paid_on}`, com `Idempotency-Key`) |
| POST | `/spaces/{space}/payments/{payment}/reversal` / `correction` | Estorno / correção de pagamento (mesmo contrato dos recebimentos) |
| GET, PATCH | `/spaces/{space}/recurrences[/{recurrence}]` | Lista / altera ocorrências futuras |
| POST | `/spaces/{space}/recurrences/{recurrence}/end` | Encerra (`{end_date?}`) |
| GET, POST | `/spaces/{space}/cards` | Lista / cadastra (`{name, due_day}`) |
| POST | `/spaces/{space}/cards/{card}/archive` / `unarchive` | Para / retoma a geração de faturas |
| GET, POST | `/spaces/{space}/agreements` | Lista / cria acordo e gera parcelas |
| GET | `/spaces/{space}/agreements/{agreement}` | Acordo com parcelas |
| GET | `/spaces/{space}/installments/{installment}` | Parcela com recebimentos |
| POST | `/spaces/{space}/installments/{installment}/receipts` | Registra recebimento |
| POST | `/spaces/{space}/receipts/{receipt}/reversal` | Estorna recebimento (`{reason}`) |
| POST | `/spaces/{space}/receipts/{receipt}/correction` | Corrige: estorno + substituto (`{reason, account_id, amount, received_on}`) |

## Exemplos (dados fictícios)

Criar conta:

```http
POST /api/spaces/1/accounts
{"name": "Banco Fictício PF", "opening_balance": "1000.00", "opening_balance_date": "2026-01-01"}

201 {"data": {"id": 3, "space_id": 1, "name": "Banco Fictício PF", "opening_balance": "1000.00",
             "opening_balance_date": "2026-01-01", "balance": "1000.00"}}
```

Criar acordo (parcelas geradas pelo núcleo `InstallmentSchedule`):

```http
POST /api/spaces/1/agreements
{"description": "Venda de veículo", "total": "24000.00", "installment_count": 12, "first_due_date": "2026-02-10"}

201 {"data": {"id": 5, "total": "24000.00", "received": "0.00", "remaining": "24000.00",
             "paid_installments": 0, "installments": [{"id": 21, "number": 1, "due_date": "2026-02-10",
             "amount": "2000.00", "received": "0.00", "remaining": "2000.00", "status": "pending",
             "overdue": true}, "..."]}}
```

Registrar recebimento (cabeçalho `Idempotency-Key` obrigatório, até 100
caracteres, único por espaço):

```http
POST /api/spaces/1/installments/22/receipts
Idempotency-Key: 6f1c0a9e2b7d4c35a8e19f0b3d2c7e41
{"account_id": 3, "amount": "500.00", "received_on": "2026-03-10"}

201 {"data": {"receipt": {"id": 9, "amount": "500.00", "received_on": "2026-03-10", "...": "..."},
             "installment": {"received": "500.00", "remaining": "1500.00", "status": "partial", "...": "..."},
             "agreement": {"remaining": "21500.00", "paid_installments": 1, "...": "..."},
             "account": {"balance": "3500.00", "...": "..."},
             "replayed": false},
     "idempotency": {"key": "6f1c0a9e2b7d4c35a8e19f0b3d2c7e41", "status": "completed", "replayed": false}}
```

## Idempotência: decisão por chave

Recebimento, estorno e correção exigem `Idempotency-Key` (até 100 caracteres,
único por espaço). A API guarda em `idempotency_keys` a **decisão final** de
cada chave, vinculada à operação, ao alvo e ao conteúdo enviado:

- `completed`: a operação foi aplicada; repetir devolve `200`, `replayed:
  true`, o mesmo registro e a situação atual dele (um recebimento estornado
  volta como `status: "reversed"`, sem recriar dinheiro).
- `rejected`: a operação foi recusada (formato, data futura, valor acima do
  restante, recebimento já estornado...); repetir devolve o mesmo `422`, com
  `replayed: true`, **mesmo que as condições tenham mudado depois** (um estorno
  reabrindo a parcela, a data passando a ser válida).
- Mesma chave com outro conteúdo ou outra operação: `409`.

A correção de abertura de conta (`opening_adjustment`) segue o mesmo
contrato. Toda resposta de operação com chave válida traz
`"idempotency": {"key", "status", "replayed"}`. Requisições com a mesma chave
são serializadas por `pg_advisory_xact_lock` antes de qualquer outro lock, e a
decisão é gravada na mesma transação do efeito: falha no meio não deixa nem
efeito nem decisão (o reenvio executa normalmente).

Ficam **sem decisão** (e portanto não provam nada): `401`, `404` de espaço,
parcela ou recebimento inacessível, `409`, `5xx`, e o `422` sem chave válida
(sai sem o campo `idempotency`).

Resposta incerta no app: a verificação é o próprio reenvio idêntico. Não há
endpoint de consulta por chave, porque "não encontrado" com o original em
processamento não provaria nada. O app só libera correção e nova chave com
`422` cujo `idempotency.status` é `rejected` para a mesma chave do pedido.

A prova anterior ("um 422 é definitivo porque o restante nunca aumenta") foi
removida: estornos aumentam o restante, e ela deixava uma chamada recusada e
atrasada ser aceita depois (reproduzido em teste antes da correção).

Recebimentos gravados antes de `idempotency_keys` continuam reconhecidos pela
chave e impressão guardadas no próprio recebimento.

## Contas: identificação, abertura e arquivamento (decisão 0005)

- Contas trazem `archived_at` e `first_movement_date`; o detalhe traz
  `opening_adjustments` (antes/depois, motivo, autor, `adjusted_at`).
- `PATCH` só aceita `name`; `space_id`, `opening_balance` e
  `opening_balance_date` no pedido dão `422`.
- Correção de abertura: o saldo muda pela diferença exata; a nova data não pode
  passar da primeira movimentação (`422` em `opening_balance_date`); igual à
  atual é `422`. Idempotente como recebimentos (operação `opening_adjustment`).
- Conta arquivada: `422` em `account_id` como destino de recebimento ou
  substituto; estorno de recebimento dela continua aceito; o saldo continua
  no resumo, que traz `active_accounts_count` e `archived_accounts_count`.

## A pagar (decisão 0006)

- Obrigação traz `amount`/`remaining` nulos em fatura sem total (nunca
  `"0.00"`), `status` (`open`, `partial`, `paid`, `cancelled`,
  `awaiting_amount`) e `overdue` (pode coexistir com `partial`).
- Cadastro com `Idempotency-Key`: avulsa, parcelada ou recorrente (com
  `approved_until` e `confirm_past`). Perda de resposta após gravação não
  duplica o conjunto criado: o reenvio da mesma chave devolve o conjunto
  original criado com `replayed: true`.
- Pagamento: conta ativa do mesmo espaço, data não futura e não anterior à
  abertura, valor até o restante; saldo pode ficar negativo e sai com sinal
  (`"balance": "-250.00"`). Estorno/correção: mesmas regras e contrato
  idempotente dos recebimentos; substituto não entra em conta arquivada.
- Resumo: `payables.{open_total, open_count, overdue_total, overdue_count,
  due_next_30_days_total, paid_total, awaiting_amount_count, today}`.

## Estorno e correção

```http
POST /api/spaces/1/receipts/9/correction
Idempotency-Key: 0b9e...
{"reason": "Conta errada", "account_id": 4, "amount": "500.00", "received_on": "2026-03-10"}

201 {"data": {"reversal": {"id": 1, "kind": "correction", "receipt_id": 9, "replacement_receipt_id": 10,
                           "reason": "Conta errada", "user_id": 1, "reversed_at": "2026-03-11T10:00:00-03:00"},
             "original": {"id": 9, "status": "reversed", "...": "..."},
             "replacement": {"id": 10, "account_id": 4, "status": "active", "replaces_receipt_id": 9, "...": "..."},
             "installment": {"remaining": "1500.00", "...": "..."}, "agreement": {"...": "..."},
             "accounts": [{"id": 3, "balance": "3000.00"}, {"id": 4, "balance": "500.00"}],
             "replayed": false},
     "idempotency": {"key": "0b9e...", "status": "completed", "replayed": false}}
```

- O original e sua movimentação nunca mudam. O estorno grava uma
  movimentação **negativa** na conta original, com a **data do original**
  (decisão 0004), e devolve o valor ao restante da parcela.
- A correção estorna e cria o substituto **na mesma transação**; o substituto
  pode ser corrigido de novo (cadeia em `replaces_receipt_id`), o original
  estornado não (`422` em `receipt`).
- Substituto: conta do mesmo espaço, data não futura e não anterior ao saldo
  inicial da conta, valor até `restante + valor estornado`; corrigir sem mudar
  conta, valor ou data é `422`.
- Motivo obrigatório (3 a 500 caracteres). Autor (`user_id`) e instante
  (`reversed_at`) registrados.
- Recebimento de outro espaço ou usuário: `404`, sem decisão registrada.

Regras do recebimento: conta obrigatoriamente do mesmo espaço (senão `422` em
`account_id`, sem revelar contas alheias); valor positivo e no máximo o restante
da parcela; data não futura e não anterior ao saldo inicial da conta; saldo
resultante dentro do limite monetário.
