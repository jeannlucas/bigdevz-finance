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
| Repositório público e CI | Publicado; CI verde em `dev` (Run ID 39365113034: 162 testes mobile e 84 testes de API) e `main` |
| Confirmação do recebimento (revisão, tentativa incerta travada até verificar) | Concluída e integrada na `main` via PR #1; validada no Simulador iOS |
| Estorno e correção de recebimentos, decisões idempotentes persistidas | Concluídos e integrados na `main` via PR #1 (decisão 0004); validados no Simulador iOS |
| Editar, corrigir abertura e arquivar contas | Concluídos e integrados na `main` via PR #1 (decisão 0005); validados no Simulador iOS |
| Editar e arquivar contas — validação manual | Confirmada pelo usuário |
| A pagar (avulsas, parceladas, recorrentes, faturas pelo total, pagamentos, estornos, correções) | Concluído e integrado na `main` via PR #1 (decisão 0006); validado no Simulador iOS |
| Redesenho fintech e design system da marca | Concluído e integrado na `main` via PR #1; cartões PF/PJ, tokens e temas claro/escuro |
| Acessibilidade do formulário e seletor adaptativo | Concluído e integrado na `main` via PR #1; validado em 150%/200%, rótulos multilinhas e SafeArea |
| Acessibilidade e reflow responsivo (Contas, A receber e A pagar) | Homologado em simuladores iOS (iPhone 17/17e) e emulador Android (Pixel 8) em 100%, 150% e 200%; validado na CI (162 testes); pendente de leitores de tela em dispositivo físico |
| Catálogo de evidências visuais | 15 capturas oficiais versionadas em `prints/` ([docs/screenshots.md](docs/screenshots.md)); 76 evidências locais do ciclo MOB-01 (BEFORE/AFTER) preservadas fora do Git em `prints/finance-mob-01/` |
| Hugeicons (Stroke Rounded, gratuitos) | Integrados e em uso no app; referência https://hugeicons.com/icons/stroke-rounded |
| Dashboard modernizado com Hero Card e ações rápidas | Concluído e homologado em iOS e Android; isolamento PF/PJ e métricas financeiras |
| Central de Configurações e temas (Automático, Claro, Escuro) | Concluído com persistência segura de preferências no dispositivo |
| Privacidade financeira expandida e mascaramento semântico de valores | Concluído no Dashboard, Contas, A receber e A pagar via MoneyText; acessibilidade semântica com `excludeSemantics` validada no AccountCard (Contas); 162 testes na CI; pendente de hardware físico |
| Homologação nativa cruzada Android (API 36) e iOS (iPhone 17 Pro) | Validada tecnicamente com catálogo de evidências visuais |

Estado detalhado, comandos executados e evidências: `docs/ai/HANDOFF.md`.
Desenvolvimento segue no Simulador iOS e Emulador Android; iPhone físico só quando o simulador
não comprovar o comportamento. Obra e empréstimo podem ser antecipados por decisão do
usuário. Licença MIT formalizada ([LICENSE](LICENSE)).
