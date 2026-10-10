# 0005 — Editar, corrigir abertura e arquivar contas

Data: 05/10/2026. Estado: implementado na API, no PostgreSQL e no app, na
`dev`, sem commit; aguarda revisão. Próximas etapas aprovadas: A pagar,
depois Hugeicons.

## Identificação

O único campo de identificação da conta é o nome. `PATCH .../accounts/{id}`
altera só o nome da mesma conta (id, espaço, dono, saldo e histórico ficam).
Enviar `space_id`, `opening_balance` ou `opening_balance_date` nesse pedido é
`422`: abertura tem fluxo próprio e a conta nunca muda de espaço. As telas
mostram o nome atual; nenhum dado financeiro anterior é reescrito. Não foram
criados campos bancários.

## Saldo inicial e data de abertura

Contrato mantido: saldo = saldo inicial + soma de todas as movimentações, sem
filtro de data; nenhum recebimento (nem substituto) antes da data de abertura
da conta; compensação de estorno na data do original (decisão 0004).

- Correção auditada em `account_opening_adjustments`: antes e depois de valor
  e data, motivo (3 a 500), autor e instante. A conta é atualizada na mesma
  transação; movimentações nunca mudam.
- O saldo muda exatamente pela diferença entre a abertura antiga e a nova. Não
  é recebimento nem despesa: não entra em `received_total`.
- Com movimentações, a nova data não pode ser posterior à primeira delas
  (nenhum recebimento ou compensação ficaria antes da abertura): recusa `422`.
  Data anterior é aceita. Sem movimentações, qualquer data válida, como no
  cadastro. Não há conversão de histórico.
- Saldo inicial continua entre 0 e o limite monetário; o saldo resultante
  também respeita o limite. Sem regra nova de saldo negativo.
- Idempotente (`opening_adjustment` em `idempotency_keys`): resposta perdida
  se resolve com a mesma chave, sem aplicar duas vezes.
- Concorrência: a conta é travada (`FOR UPDATE`); recebimentos e estornos
  travam a conta antes de gravar movimentações, então a data e o saldo são
  validados com dados atuais.

## Contas arquivadas

- `archived_at`. Arquivar e reativar não mudam dinheiro nem histórico; não há
  exclusão física. Repetir o pedido não muda nada.
- Arquivada não é destino de novos recebimentos nem de substitutos de
  correção (`422` em `account_id`, avaliado sob o lock da conta, serializado
  com o arquivamento). Estornar um recebimento dela continua possível, e a
  correção pode retirar dela e registrar o substituto numa conta ativa.
- O saldo da arquivada continua no saldo do espaço. O resumo informa
  `active_accounts_count` e `archived_accounts_count`; a lista separa ativas e
  arquivadas e diz que o total as inclui.
- Chaves: replay de operação concluída devolve o resultado original mesmo com
  a conta arquivada depois. Chave ainda não decidida que chega com a conta
  arquivada é recusada e a recusa fica registrada; reativar não muda essa
  decisão. O app guarda a tentativa até a decisão registrada e então a libera
  com a mensagem da API.

## Testes

PostgreSQL real de testes: `AccountManagementTest` e, em
`ConcurrentReceiptsTest`, disputa entre data de abertura e recebimento, saldo
inicial e estorno, arquivamento e recebimento (processos reais).
