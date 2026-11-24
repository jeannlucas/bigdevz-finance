# Carteira multimoeda da Wise

Status: implementação local em homologação.

A conta Wise já existe no catálogo de instituições. A carteira reúne o saldo
em reais da conta atual e os saldos em moeda estrangeira vinculados a ela.
As operações são registros manuais de eventos já efetivados.

## Critérios de aceite

- **AC-WISE-001 — Carteira por conta e moeda.** Uma conta ativa associada à
  Wise pode cadastrar moedas com código ISO 4217 e saldo inicial opcional.
  O par conta/moeda é único. BRL corresponde à conta existente, com o
  histórico preservado. APIs e UI bloqueiam o cadastro em outras instituições.
  A disponibilidade de moedas vem de um catálogo local com a escala da unidade
  menor, incluindo moedas sem centavos e com três casas.
- **AC-WISE-002 — Saldos independentes.** Cada moeda mostra o saldo efetivo e
  o histórico em unidades menores inteiras. A API serializa valores como
  strings decimais na escala daquela moeda. O saldo BRL do espaço continua
  contemplando somente movimentações efetivadas em reais.
- **AC-WISE-003 — Transferências em reais.** A transferência manual de um
  banco do mesmo espaço para a Wise em BRL reutiliza o fluxo atual entre
  contas. A transação debita a origem e credita o saldo BRL da Wise, com
  vínculo único, data efetiva e estorno pelo fluxo atual.
- **AC-WISE-004 — Conversão manual.** A conversão informa data, moeda e
  valor debitado, moeda e valor creditado e, se houver, valor e moeda da
  tarifa. A interface indica se a tarifa integra o débito informado.
  A API valida moedas distintas, saldo suficiente, datas e escalas.
  O débito, o crédito, a tarifa e o vínculo da operação são persistidos
  atomicamente, com locks em ordem estável e chave de idempotência por espaço.
- **AC-WISE-005 — Auditoria.** A correção de uma conversão efetivada ocorre
  por estorno auditável e preserva as movimentações originais. Criações e
  estornos validam o usuário, o espaço, o estado da conta e a integridade
  dos vínculos de cada saldo. Um replay não duplica lançamentos.
- **AC-WISE-006 — Equivalente estimado.** Quando todas as moedas com saldo
  diferente de zero tiverem cotação manual válida, a carteira exibe o
  equivalente estimado em BRL e as datas de referência das cotações. A
  conversão utiliza aritmética inteira ou decimal exata, com arredondamento
  ao centavo apenas para apresentação. A estimativa fica fora do saldo
  disponível do espaço. Sem cotação, a interface indica a moeda pendente.
- **AC-WISE-007 — Interface.** O detalhe da conta lista saldos por moeda,
  mostra as ações pertinentes e permite consultar os lançamentos no
  desktop e mobile. Moeda e valor aparecem explicitamente em todos os
  passos, inclusive na confirmação e no estado vazio.

- **AC-WISE-008 — Dashboard.** O Dashboard do espaço atual lista as
  moedas estrangeiras cadastradas por conta, inclusive as zeradas. Os
  valores respeitam o controle de privacidade do Dashboard e permanecem
  separados do saldo disponível em BRL.

- **AC-WISE-009 — Identificação visual.** A carteira e o Dashboard
  exibem bandeiras locais ao lado da moeda. O cadastro permite pesquisar
  por nome em português ou código ISO, inclusive sem acentos. A lista
  permanece contida no formulário em desktop e mobile.

## Matriz de rastreabilidade

| Critério | Área | Verificação esperada |
| --- | --- | --- |
| AC-WISE-001, AC-WISE-002 | Persistência, API de contas e detalhe da Wise | Migração preserva contas existentes, valida duplicidade, escala e isolamento, exibe o saldo correto por moeda |
| AC-WISE-003 | Transferências entre contas | Transferir R$ 360 altera somente os saldos em reais e permite estorno |
| AC-WISE-004, AC-WISE-005 | Conversão e estorno | Atomicidade, concorrência, idempotência e validação da tarifa |
| AC-WISE-006 | Apresentação de patrimônio | Cotação ausente e datada, arredondamento exato, saldo BRL preservado |
| AC-WISE-007 | Interface web e mobile | Fluxos completos com teclado e por toque |
| AC-WISE-008 | `WiseDashboardCard`, `SummaryTab` | `wise_dashboard_test.dart` |
| AC-WISE-009 | `WiseCurrencyPicker`, `WiseCurrencyFlag` | `wise_currency_picker_test.dart` |
