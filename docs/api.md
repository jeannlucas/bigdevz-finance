# API do checkpoint 1

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
- **Erros**: `422` validação (`errors` por campo), `401` sessão inválida,
  `404` não encontrado, `409` chave idempotente reutilizada com outro conteúdo,
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
| GET | `/spaces/{space}/accounts/{account}` | Conta com saldo atual |
| GET, POST | `/spaces/{space}/agreements` | Lista / cria acordo e gera parcelas |
| GET | `/spaces/{space}/agreements/{agreement}` | Acordo com parcelas |
| GET | `/spaces/{space}/installments/{installment}` | Parcela com recebimentos |
| POST | `/spaces/{space}/installments/{installment}/receipts` | Registra recebimento |

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
             "replayed": false}}
```

Reenvio com a mesma chave e o mesmo conteúdo: `200`, mesmo `receipt.id`,
`replayed: true`, nenhuma nova movimentação. Mesma chave com outra conta,
valor, data ou parcela: `409`.

Regras do recebimento: conta obrigatoriamente do mesmo espaço (senão `422` em
`account_id`, sem revelar contas alheias); valor positivo e no máximo o restante
da parcela; data não futura e não anterior ao saldo inicial da conta; saldo
resultante dentro do limite monetário.
