# Roadmap

| Etapa | Estado | Entrega |
| --- | --- | --- |
| Preparação | Concluída | Ferramentas, Git, dependências, PostgreSQL isolado e CI |
| 1 | Concluída | Login, PF/PJ, contas, venda parcelada, recebimentos e saldos |
| 2 | Em andamento | Concluídos: A pagar, parcelamentos, recorrências, faturas de cartão, estornos e gestão de contas. Próximos: transferências e empréstimos |
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
| Confirmação do recebimento (revisão, tentativa incerta travada até verificar) | Concluída e integrada na `main` via PR #1; validada no Simulador iOS |
| Estorno e correção de recebimentos, decisões idempotentes persistidas | Concluídos e integrados na `main` via PR #1 (decisão 0004); validados no Simulador iOS |
| Editar, corrigir abertura e arquivar contas | Concluídos e integrados na `main` via PR #1 (decisão 0005); validados no Simulador iOS |
| Editar e arquivar contas — validação manual | Confirmada pelo usuário |
| A pagar (avulsas, parceladas, recorrentes, faturas pelo total, pagamentos, estornos, correções) | Concluído e integrado na `main` via PR #1 (decisão 0006); validado no Simulador iOS |
| Redesenho fintech e design system da marca | Concluído e integrado na `main` via PR #1; cartões PF/PJ, tokens e temas claro/escuro |
| Acessibilidade do formulário e seletor adaptativo | Concluído e integrado na `main` via PR #1; validado em 150%/200%, rótulos multilinhas e SafeArea |
| Catálogo de evidências visuais oficiais | 15 capturas reais em `prints/` geradas e auditadas; `simulator_state.png` histórico em `design/screenshots/` |
| Hugeicons (Stroke Rounded, gratuitos) | Integrados e em uso no app; referência https://hugeicons.com/icons/stroke-rounded |

Estado detalhado, comandos executados e evidências: `HANDOFF.md`.
Desenvolvimento segue no Simulador iOS; iPhone físico só quando o simulador
não comprovar o comportamento. Obra e empréstimo podem ser antecipados por decisão do
usuário. Licença MIT formalizada ([LICENSE](LICENSE)).
