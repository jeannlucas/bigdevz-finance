# 0006 — A pagar

Data: 05/10/2026. Estado: implementado na API, no PostgreSQL e no app, na
`dev`, sem commit; aguarda revisão. Próxima etapa aprovada: Hugeicons, com a
coleção gratuita Stroke Rounded como referência visual
(https://hugeicons.com/icons/stroke-rounded); nada instalado ainda.

Fora do escopo: empréstimos, transferências, orçamento da obra, anexos e
integrações bancárias. Despesas da obra entram como despesas comuns, com
descrição e beneficiário.

## Modelo

- **Obrigação** (`payables`): avulsa, parcela, ocorrência recorrente ou
  fatura de cartão. Descrição, beneficiário opcional, valor exato e
  vencimento. Não movimenta conta; só pagamentos movimentam. `paid_cents` é o
  pago líquido.
- **Pagamento** (`payments`): saída (movimentação negativa) de uma conta do
  mesmo espaço, escolhida explicitamente. **Estorno** (`payment_reversals`):
  compensação positiva na conta original, na data do pagamento, reabrindo o
  restante; o original fica. **Correção**: estorno + substituto na mesma
  transação. Mesma política de datas da decisão 0004, aplicada com o sinal
  invertido.
- Movimentação: exatamente uma origem (recebimento, estorno de recebimento,
  pagamento, estorno de pagamento), com o sinal de cada uma garantido no banco.
- Trilha em `obligation_changes` (antes/depois, motivo, autor, instante) para
  edição, cancelamento, alteração de futuras, encerramento e cartões.

## Situação e vencimento

`open`, `partial`, `paid`, `cancelled` e `awaiting_amount` (fatura sem total).
**Vencida** é derivada: não cancelada, com restante e vencimento antes de hoje
no fuso do produto (`America/Sao_Paulo`); coexiste com parcial. Fatura sem
total não é "vencida" nem entra em totais: aparece como pendente de
informação.

## Edição e cancelamento

- Editar esta obrigação: descrição, beneficiário, valor e vencimento, com
  motivo opcional na trilha. O valor nunca fica abaixo do pago líquido.
  Editada uma ocorrência recorrente, ela passa a ser individual (`edited_at`).
- Cancelar: motivo obrigatório; só sem pagamento ativo (pago líquido zero,
  também CHECK no banco). Estorne os pagamentos antes. Cancelada não é paga,
  não é editada e não volta a ser gerada.

## Parceladas

Total, número de parcelas e primeiro vencimento; cronograma do núcleo
(`InstallmentSchedule`: soma exata, centavos nas primeiras parcelas, dia de
referência, 31 → último dia do mês, bissexto). Prévia sem gravar
(`POST .../payables/preview`), exigida pelo app antes de confirmar. Criação
idempotente: repetir a chave não duplica parcelas; `UNIQUE (plan_id,
installment_number)`.

## Recorrências

- Valor mensal fixo, início (dia de referência = dia do início) e término
  opcional. Ocorrências por ciclo mensal, do início até o **horizonte: mês
  atual + 12**, com `UNIQUE (recurrence_id, cycle)` e `ON CONFLICT DO NOTHING`.
  Início no passado gera os ciclos desde o início (débitos reais).
- **Alterar futuras**: valor, descrição e beneficiário da recorrência e das
  ocorrências com vencimento de hoje em diante, sem pagamento, não canceladas
  e não editadas individualmente. Pagas, parciais, vencidas e editadas ficam.
- **Encerrar** em uma data: não gera mais ciclos depois dela e cancela as
  ocorrências seguintes sem pagamento. Não estorna pagamentos nem apaga
  débitos; ocorrência posterior com pagamento parcial continua.

## Cartões e faturas

- Cartão: nome e dia de vencimento (1–31). Nenhum dado do cartão. Não é conta
  e não tem saldo.
- Fatura = a própria obrigação a pagar (não há obrigação paralela), única por
  cartão e ciclo. Gerada do mês atual até o horizonte, **sem valor**; o total é
  informado pelo usuário e nunca copiado da anterior. Sem total não pode ser
  paga. Total não pode ficar abaixo do pago líquido.
- Cartão arquivado não gera novas faturas (nem retroativas ao reativar); as
  existentes continuam consultáveis e pagáveis.

## Saldo negativo

Não há regra de saldo mínimo: um pagamento pode deixar a conta negativa, e o
app mostra o saldo resultante na revisão. Na saída, valores de saldo passam a
aceitar sinal (`"-250.00"`, até `-999999999999.99`); valores informados
continuam positivos (decisão 0002).

## Concorrência, idempotência e recuperação de cadastros

Ordem de locks: chave (lock consultivo), obrigação, pagamento, contas por id.
Recebimentos travam parcela e conta; correção de abertura e arquivamento,
a conta. Operações com chave: `payable`, `recurrence`, `payment`,
`payment_reversal`, `payment_correction`, com decisão final persistida junto
do efeito (recusas incluídas). Edição, cancelamento, encerramento e cartões
são definição de estado (repetir não muda nada), sem chave.

Recuperação de cadastro de A pagar (`payable` e `recurrence`): chave e payload
exatos são gravados no armazenamento seguro antes do envio. Em caso de resposta
perdida (queda de rede após commit no backend), o cadastro pendente fica travado
no app e um aviso persistido na aba A pagar e na tela de cadastro permite
**Verificar cadastro** com a mesma chave. A API devolve o conjunto original já
criado com `replayed: true` sem criar novas obrigações.
Para recorrências iniciadas no passado, a criação exige revisão prévia
(`POST /payables/recurrence-preview`) e aprovação explícita de ocorrências já
vencidas (`confirm_past`), com `initial_until` delimitando o conjunto inicial.

## Geração automática

`php artisan payables:generate` gera ocorrências e faturas até o horizonte;
agendado de hora em hora (`routes/console.php`). No Compose, o serviço
`scheduler` roda `php artisan schedule:work`. Verificar:

- `docker compose logs scheduler`: linhas `Running ['artisan' payables:generate] ... DONE`;
- `apps/api/storage/logs/payables-generate.log`: contagens e horizonte de
  cada execução (sem dados financeiros);
- `docker compose exec scheduler php artisan schedule:list`.

## Resumo

`payables`: em aberto, vencido (valor e quantidade), próximos 30 dias
(incluindo hoje), pago líquido (realizado) e faturas sem total. Obrigações não
reduzem o saldo bancário; não há projeção de saldo nesta etapa.
