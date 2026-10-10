# 0004 — Estorno e correção de recebimentos

Data: 05/10/2026. Estado: implementado na API, no PostgreSQL e no app, na
`dev`, sem commit; aguarda revisão.

## Modelo

- **Estorno** desfaz o efeito de um recebimento confirmado. **Correção** é um
  estorno com recebimento substituto, na mesma transação. Nada é apagado nem
  alterado: o recebimento original e sua movimentação ficam como estavam.
- `receipt_reversals`: original (`receipt_id`, único: um estorno por
  recebimento), substituto (`replacement_receipt_id`, opcional e único), conta
  original, autor (`user_id`), motivo (3 a 500 caracteres) e instante
  (`created_at`). Chaves estrangeiras compostas garantem que original e
  substituto são do mesmo espaço e da mesma parcela, e que a compensação sai
  da conta que recebeu o original.
- `account_movements` passa a aceitar saída: cada movimentação vem de um
  recebimento (positiva) ou de um estorno (negativa), nunca dos dois (CHECK).
- `installments.received_cents` é o recebido **líquido**: o estorno subtrai o
  original e a correção soma o substituto. Resumos, acordos, saldos e o estado
  quitado/parcial/em aberto já derivam desse valor e das movimentações, sem
  contar original e substituto em dobro.
- Um substituto ativo pode ser corrigido de novo; a cadeia fica em
  `replaces_receipt_id`. Original estornado não volta a ser estornado.

## Datas

Três informações separadas:

1. **Ocorrência** do recebimento (`received_on`): preservada no original; o
   substituto tem a sua.
2. **Instante** do estorno (`receipt_reversals.created_at`).
3. **Data efetiva da compensação**: a **data do original**.

O estorno corrige um lançamento errado; não é um evento financeiro novo. A
compensação neutraliza o lançamento na própria data, e o substituto entra na
data correta. Como o original já respeitava a data do saldo inicial da conta,
a compensação nunca fica antes da abertura, e nenhum movimento anterior à
abertura é afetado duas vezes. O substituto segue a regra de qualquer
recebimento: não futuro e não anterior ao saldo inicial da sua conta. Hoje o
saldo não depende de data (saldo inicial + soma das movimentações), então a
escolha só afeta o histórico e relatórios por período futuros.

## Saldo negativo

Não há regra de saldo mínimo no produto. Estornar não exige saldo: desfaz uma
entrada mesmo que o dinheiro já tenha saído. Hoje só existem entradas, então
o saldo não fica abaixo do saldo inicial; quando houver saídas (checkpoint 2),
um estorno poderá deixar a conta negativa, e isso é permitido. O limite
monetário superior continua valendo para o substituto. Substituto não entra em
conta arquivada; o estorno pode sair dela (decisão 0005).

## Idempotência

A decisão final de cada chave (concluída ou recusada) fica em
`idempotency_keys`, serializada por `pg_advisory_xact_lock` e gravada na mesma
transação do efeito. Substitui a prova anterior do `422`, que dependia de o
restante nunca aumentar e deixou de valer com estornos. Contrato em
`docs/api.md`.

## Concorrência

Ordem de locks em todas as escritas: chave, parcela, recebimento e contas por
id crescente. Testado com processos e conexões PostgreSQL reais: dois
estornos ou duas correções do mesmo recebimento, estorno com a mesma chave e
correção contra novo recebimento que, juntos, excederiam a parcela.
