# Roadmap

| Etapa | Estado | Entrega |
| --- | --- | --- |
| Preparação | Concluída | Ferramentas, Git, dependências, PostgreSQL isolado e CI |
| 1 | Concluída | Login, PF/PJ, contas, venda parcelada, recebimentos e saldos |
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
| iPhone físico | Validado (teste de integração e roteiro manual) |
| Android | Validado em emulador (API 36, arm64); aparelho não testado |
| Repositório público e CI | Publicado; CI verde em `dev` e `main` |

Estado detalhado, comandos executados e evidências: `HANDOFF.md`.
Desenvolvimento segue no Simulador iOS; iPhone físico só quando o simulador
não comprovar o comportamento. Obra e empréstimo podem ser antecipados por decisão do
usuário. Licença em definição.
