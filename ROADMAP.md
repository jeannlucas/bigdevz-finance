# Roadmap

| Etapa | Estado | Entrega |
| --- | --- | --- |
| Preparação | Concluída | Ferramentas, Git, dependências, PostgreSQL isolado e CI |
| 1 | Em fechamento | Login, PF/PJ, contas, venda parcelada, recebimentos e saldos |
| 2 | Planejada | Despesas, recorrências, faturas, transferências e empréstimos |
| 3 | Planejada | Clientes, mensalidades e projetos por etapas |
| 4 | Planejada | Construção, orçamento, compromissos e comprovantes |
| 5 | Planejada | Extratos, relatórios, exportação e web refinada |

## Checkpoint 1

| Critério | Situação |
| --- | --- |
| API Laravel + PostgreSQL (cenários 1–9 e 11) | Funcionando localmente; suíte em PostgreSQL real |
| App Flutter integrado à API (cenário 10) | Funcionando localmente; testes Dart com backend simulado |
| Simulador iOS contra a API real | Validado |
| iPhone físico | Pendente |
| Android (emulador ou aparelho) | Pendente |
| Repositório público e CI | Ver `HANDOFF.md` |

Estado detalhado, comandos executados e evidências: `HANDOFF.md`.
O checkpoint só é dado como concluído com iPhone físico e Android validados
contra a API real. Obra e empréstimo podem ser antecipados por decisão do
usuário. Licença em definição.
