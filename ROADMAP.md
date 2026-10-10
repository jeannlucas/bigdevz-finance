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
| Confirmação do recebimento (revisão, tentativa incerta travada até verificar) | Implementada em `dev`, validada no Simulador iOS; ainda não publicada |
| Estorno e correção de recebimentos, decisões idempotentes persistidas | Implementados em `dev`, validados no Simulador iOS (teste e manual do usuário); ainda não publicados (decisão 0004) |
| Editar, corrigir abertura e arquivar contas | Implementados em `dev`, validados no Simulador iOS; ainda não publicados (decisão 0005) |
| Editar e arquivar contas — validação manual | Confirmada pelo usuário |
| A pagar (avulsas, parceladas, recorrentes, faturas pelo total, pagamentos, estornos, correções) | Implementado em `dev`, validado no Simulador iOS; ainda não publicado (decisão 0006) |
| Redesenho fintech e design system da marca | Implementado em `dev`, aprovado pelo usuário; cartões PF/PJ, tokens e temas claro/escuro |
| Acessibilidade do formulário e seletor adaptativo | Implementado em `dev`, validado com 150%/200%, rótulos multilinhas e SafeArea íntegra |
| Catálogo de evidências visuais oficiais | 15 capturas reais em `prints/` geradas e auditadas; `simulator_state.png` histórico em `design/screenshots/` |
| Hugeicons (Stroke Rounded, gratuitos) | Próxima etapa aprovada; referência https://hugeicons.com/icons/stroke-rounded |

Estado detalhado, comandos executados e evidências: `HANDOFF.md`.
Desenvolvimento segue no Simulador iOS; iPhone físico só quando o simulador
não comprovar o comportamento. Obra e empréstimo podem ser antecipados por decisão do
usuário. Licença MIT formalizada ([LICENSE](LICENSE)).
