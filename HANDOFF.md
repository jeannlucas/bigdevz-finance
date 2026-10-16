# Handoff Histórico — 09/10/2026 (Auditoria de Segurança, Commits Lógicos e Publicação em origin/dev)

> [!NOTE]
> **AVISO DE TRANSIÇÃO DE GOVERNANÇA (CHECKPOINT GOV-06.B):**<br>
> Este documento é o **registro histórico imutável** consolidado das sessões até 09/10/2026.<br>
> A partir do Checkpoint GOV-06.B, a **autoridade canônica operacional ativa** para continuidade entre Google Antigravity e OpenAI Codex reside exclusivamente em [`docs/ai/HANDOFF.md`](docs/ai/HANDOFF.md).
> Todas as seções, auditorias, decisões e evidências históricas abaixo foram integralmente preservadas.

Publicação da branch `dev` realizada com sucesso no GitHub (`origin/dev`) após auditoria completa de segurança, integridade financeira e validação formal do histórico Git. Todos os testes automatizados, formatadores e suítes de validação estão 100% aprovados e verdes. A divergência de hashes documentada em relatórios anteriores foi investigada e resolvida (hash real `42a3e397d3921777cb952c96e0de03d7d6e20f0c`). A licença MIT foi formalizada no repositório. Seis commits atômicos e descritivos foram criados e enviados para `origin/dev` via fast-forward limpo, mantendo a branch `main` estritamente intocada.

Branch local: `dev` sincronizada com `origin/dev` no commit `5aa5d6becf591ccce0dd4b535a1b82a75e0a6221`. Branch `main` preservada em `42a3e397d3921777cb952c96e0de03d7d6e20f0c`. Preservadas alterações locais de ambiente de desenvolvimento (`project.pbxproj`, `Info.plist`, `devtools_options.yaml`, `scripts/run-mobile.sh` e `design/screenshots/`).

---

## 1. Diagnóstico e Causa Raiz das Pendências Anteriores

| # | Item | Causa Raiz Identificada | Correção Aplicada e Situação Atual |
| :--- | :--- | :--- | :--- |
| **1** | `light_03_carteira_pf.png` mostrava dados PJ | No script de teste de integração anterior, a navegação para "Contas" no tema claro foi feita sem selecionar explicitamente o espaço PF após a captura do Resumo PJ, herdando o espaço ativo. | Em [generate_evidences_test.dart](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/apps/mobile/integration_test/generate_evidences_test.dart), implementada a seleção obrigatória e explícita via `selectSpace('PF')`, com validação do `SessionController` e asserções estritas (`expect('Conta financeira PF', findsWidgets)` e `expect('Banco Fictício PJ', findsNothing)`). Captura regerada com o cartão azul escuro e dados PF. |
| **2** | Título "Nova conta a pagar" invadia área do relógio/status bar em 150% | **Defeito no harness de teste, não no app**. A tela de produto usa `Scaffold` com `AppBar` nativa e respeita a SafeArea. O harness de teste isolado injetava um `MediaQuery` sem `padding` ou `viewPadding` (`top = 0`). | Injetados insets reais da Safe Area do iPhone (`EdgeInsets.only(top: 59, bottom: 34)`). O título fica posicionado perfeitamente abaixo da status bar e Dynamic Island. |
| **3** | Rótulos truncados em 200%: "Beneficiário (opcional)" e "Primeiro vencimento (dia de referência)" | 1. O floating label do Material ficava restrito a uma linha.<br>2. O label de vencimento continha texto explicativo longo embutido no título. | 1. Criado [AccessibleFieldWrapper](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/apps/mobile/lib/ui/widgets.dart), que sob escalas ampliadas (`scale > 1.2`) apresenta o rótulo multilinhas acima do campo.<br>2. Em [date_field.dart](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/apps/mobile/lib/ui/date_field.dart), o rótulo foi simplificado para "Primeiro vencimento" e a explicação movida para `helperText: 'O dia escolhido será usado como referência nos meses seguintes.'` com até 3 linhas. |
| **4** | Ausência da seta de retorno nas capturas A11y 150%/200% | **Mecanismo de teste isolado**. O harness montava `PayableFormScreen` como `home:` do `MaterialApp`. Na rota raiz (`/`), `Navigator.canPop(context)` é `false`, logo o `AppBar` nativo não renderiza o botão de voltar. | **Comprovado**: na tela real do produto (aberta via `Navigator.push`), `canPop` é `true` e a seta de retorno `<` é renderizada normalmente e com total acessibilidade (como comprovado nas capturas reais nativas `dark_06` e `light_06`). |
| **5** | Relatório anterior com caminhos em branco e sem explicação técnica de 375px | Relatório continha placeholders e omitia a metodologia técnica de insets e viewport. | Catálogo completo com todos os caminhos absolutos, dimensões lógicas, físicas e insets devidamente documentados. |

---

## 2. Metodologia Técnica: 375px Lógicos vs Simulador Nativo

- **Simulador iPhone 17 Pro (Nativo)**: 402 pt de largura lógica por 874 pt de altura lógica (escala 3x = 1206 x 2622 px físicos). Utilizado para as 12 capturas dos fluxos normais (`dark_01` a `dark_06` e `light_01` a `light_06`).
- **Harness de Acessibilidade (Viewport 375pt)**: Executado dentro do simulador iPhone 17 Pro via `generate_evidences_test.dart` com `MediaQueryData(size: Size(375.0, 874.0), padding: EdgeInsets.only(top: 59, bottom: 34), textScaler: TextScaler.linear(1.5 ou 2.0))`. Reproduz fielmente a largura do iPhone 12 mini / iPhone SE preservando os insets reais do topo e da base.

---

## 3. Catálogo Completo das Evidências Visuais Oficiais

Todas as 15 capturas ativas oficiais estão gravadas exclusivamente na pasta oficial [prints/](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/prints/). As 15 duplicatas redundantes em `design/screenshots/` foram removidas, preservando estritamente a captura histórica de referência `design/screenshots/simulator_state.png`.

| Arquivo | Tela / Espaço | Tema | Largura x Altura Lógica | Escala Texto | Safe Area Insets (T/B/L/R) | Ambiente / Método | Caminho Completo (Pasta Principal) |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `dark_01_resumo_pf.png` | Resumo / PF | Escuro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/dark_01_resumo_pf.png` |
| `dark_02_resumo_pj.png` | Resumo / PJ | Escuro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/dark_02_resumo_pj.png` |
| `dark_03_carteira_pf.png` | Carteira / PF | Escuro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/dark_03_carteira_pf.png` |
| `dark_04_carteira_pj.png` | Carteira / PJ | Escuro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/dark_04_carteira_pj.png` |
| `dark_05_a_pagar_pf.png` | A pagar / PF | Escuro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/dark_05_a_pagar_pf.png` |
| `dark_06_cadastro_pagar_recorrente.png` | Novo A pagar / PF | Escuro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/dark_06_cadastro_pagar_recorrente.png` |
| `light_01_resumo_pf.png` | Resumo / PF | Claro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/light_01_resumo_pf.png` |
| `light_02_resumo_pj.png` | Resumo / PJ | Claro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/light_02_resumo_pj.png` |
| `light_03_carteira_pf.png` | Carteira / PF | Claro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/light_03_carteira_pf.png` |
| `light_04_carteira_pj.png` | Carteira / PJ | Claro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/light_04_carteira_pj.png` |
| `light_05_a_pagar_pf.png` | A pagar / PF | Claro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/light_05_a_pagar_pf.png` |
| `light_06_cadastro_pagar_recorrente.png` | Novo A pagar / PF | Claro | 402 x 874 pt | 100% (1.0x) | 59 / 34 / 0 / 0 pt | Simulador iPhone 17 Pro | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/light_06_cadastro_pagar_recorrente.png` |
| `a11y_375px_scale_150_seletor.png` | Novo A pagar / PF | Escuro | 375 x 874 pt | 150% (1.5x) | 59 / 34 / 0 / 0 pt | Test Harness (Viewport 375pt) | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/a11y_375px_scale_150_seletor.png` |
| `a11y_375px_scale_200_seletor.png` | Novo A pagar / PF | Escuro | 375 x 874 pt | 200% (2.0x) | 59 / 34 / 0 / 0 pt | Test Harness (Viewport 375pt) | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/a11y_375px_scale_200_seletor.png` |
| `a11y_iphone17pro_scale_200_seletor.png` | Novo A pagar / PF | Escuro | 402 x 874 pt | 200% (2.0x) | 59 / 34 / 0 / 0 pt | Test Harness (Viewport 402pt) | `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/prints/a11y_iphone17pro_scale_200_seletor.png` |

Arquivo histórico preservado: `/Users/jeannlucasdev/Documents/Projetos/BigDev.Z Finance/design/screenshots/simulator_state.png`.

---

## 4. Auditoria de Execução e Testes Automatizados

Resultados reais obtidos nesta verificação de consolidação:

1. **`make test-domain`**:
   - `11 testes; 0 falhas` (dinheiro exato sem float, centavos determinísticos, datas canônicas, preservação de bissexto).
2. **`make test-api`**:
   - `71 testes, 1011 asserções aprovadas` (PostgreSQL real `bigdevz_finance_test`, rollback automático, concorrência multiprocesso, idempotência, estornos e planos).
3. **`make smoke-api`**:
   - 100% aprovado (roteiro HTTP completo contra container Docker).
4. **`make lint-api` (Pint)**:
   - `{"tool":"pint","result":"passed"}` (100% de conformidade de estilo PHP).
5. **`dart format --output=none --set-exit-if-changed lib test integration_test`**:
   - `Formatted 75 files (0 changed)` — código Dart 100% formatado e aderente ao passo exigido no GitHub Actions CI.
6. **`flutter analyze` em `apps/mobile`**:
   - `No issues found! (ran in 2.7s)`
7. **`flutter test` em `apps/mobile`**:
   - `86 testes aprovados` (`All tests passed!`), cobrindo:
     - Cabeçalho respeitando a Safe Area sob insets de status bar (59pt) em 100%, 150% e 200%.
     - Rótulos completos em 375px e texto em 150% e 200% sem reticências ou overflow.
     - Rolagem do formulário completa com texto em 200% e teclado virtual simulado (`viewInsets: bottom: 336`).
     - Preservação dos dados digitados ao alternar entre modalidades Avulsa, Parcelada e Recorrente.
     - Alinhamento vertical da carteira PF e PJ.
8. **Build e Execução no Simulador iOS**:
   - `Runner.app` compilado com sucesso e lançado no iPhone 17 Pro via `xcrun simctl launch ... com.bigdevz.finance` (PID 53182), com sessão, Keychain e banco preservados.

---

## 5. Auditoria do Git e Classificação das Alterações Locais

- **Branch ativa**: `dev` (apontando para commit `42a3e39`, em paridade com `origin/dev` e `origin/main`).
- **Arquivos modificados**: 57
- **Arquivos excluídos**: 1 (`ReceiptOutcome.php`)
- **Arquivos não rastreados**: 87
- **Arquivos em staging**: 0 (`git diff --cached` vazio).

### Classificação por Responsabilidade:
1. **Backend & API**:
   - Controllers, Actions, Models e Resources de A Pagar, Cartões, Estornos, Idempotência e Ajustes de Abertura.
2. **Banco de Dados & Migrations**:
   - Migrations de estornos, idempotência, arquivamento de contas, ajustes de abertura, criação de payables e recorrências.
3. **Mobile & Funcionalidades Financeiras**:
   - Módulos de Contas (edição/arquivamento), Acordos (correção de recebimento, tentativas incertas), e A Pagar (avulsa, parcelada, recorrente, cartões).
4. **Design System & Componentes**:
   - Tokens visuais (`app_tokens.dart`), cores/temas (`theme.dart`), marca (`app_brand.dart`), ícones (`app_icons.dart`) e assets oficiais da marca.
5. **Acessibilidade**:
   - `AccessibleFieldWrapper`, `DateField` adaptativo e `_KindSelector` adaptativo.
6. **Testes Automatizados**:
   - Suítes de domínio, testes de concorrência e features da API (71 testes); suítes Dart (86 testes).
7. **Testes de Integração**:
   - `app_test.dart`, `generate_evidences_test.dart`, `inspection_test.dart`.
8. **Documentação**:
   - `docs/project-guidelines.md` (referência canônica central das regras permanentes, financeiras, de arquitetura e design system).
   - `HANDOFF.md`, `README.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `AGENTS.md`.
   - `docs/architecture.md`, `docs/api.md`, `docs/decisions/` (decisões 0001 a 0006) e `docs/archive/` (prompts e históricos de sessões anteriores).
9. **Evidências Visuais**:
   - 15 capturas ativas oficiais em `prints/`; `simulator_state.png` histórico em `design/screenshots/`.
10. **Arquivos de Configuração Local da Máquina (NÃO PUBLICAR)**:
    - `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (contém `DEVELOPMENT_TEAM = 2X74SUJ4CB;` e upgrade do Xcode).
    - `apps/mobile/ios/Runner/Info.plist` (ajustes locais de rede).
    - `apps/mobile/devtools_options.yaml` (preferências do DevTools local).

---

## 6. Auditoria Técnica de Engenharia de Software e Matriz de Qualidade

Auditoria independente realizada com foco em arquitetura, integridade financeira, segurança, concorrência e preparação open source.

### Matriz de Qualidade (15 Dimensões):

| Dimensão | Classificação | Justificativa Técnica |
| :--- | :--- | :--- |
| **1. Arquitetura Backend** | Excelente | Monólito modular no Laravel 13.34 com separação estrita de Domínio, Actions e Controllers. |
| **2. Arquitetura Mobile** | Excelente | Modular por features (`features/accounts`, `payables`, `agreements`), `KeyedSubtree` para isolamento total de estado PF/PJ. |
| **3. Clean Code e SOLID** | Excelente | SRP respeitado via Actions focadas (`ReceiveInstallment`, `ReverseReceipt`). DTOs e Resources bem definidos. |
| **4. Modelagem de Dados** | Excelente | PostgreSQL com FKs compostas `(id, space_id)`, restrições de integridade e enumerações validadas. |
| **5. Integridade Financeira** | Excelente | Centavos inteiros em todas as operações; `Money` sem floats; arredondamento bancário determinístico; proteção contra saldo negativo. |
| **6. Concorrência e Locks** | Excelente | `pg_advisory_xact_lock` no PostgreSQL protege transações críticas; concorrência multiprocesso validada por testes reais. |
| **7. Idempotência e Estornos** | Excelente | `IdempotentOperations` com hash seguro de fingerprint, bloqueio transacional e decisões persistidas em banco. Estornos por contrapartida espelho. |
| **8. Isolamento PF / PJ** | Excelente | Proteção dupla: backend rejeita acessos cruzados via middleware/queries com `space_id`; mobile recria árvores de widgets na alternância. |
| **9. Segurança (OWASP)** | Excelente | Proteção contra IDOR via verificação de tenancy; sanitização de inputs; tokens Bearer via Sanctum; zero vulnerabilidades no `composer audit`. |
| **10. Performance** | Bom | Agregações no PostgreSQL (`withSum`, `withMin`), índices compostos. Recomenda-se paginação em endpoints de listagem volumosos (P2). |
| **11. Qualidade dos Testes** | Excelente | Pirâmide equilibrada: testes de domínio sem framework, testes de API com concorrência multiprocesso real e testes mobile com widgets e integração. |
| **12. CI/CD e Automação** | Excelente | GitHub Actions executa Pint, testes de domínio, testes de API contra PostgreSQL real, `dart format` e `flutter analyze`. |
| **13. Observabilidade** | Bom | Trilha de auditoria financeira persistida em `AccountMovement` e `ReceiptReversal`. Logs de scheduler estruturados e sanitizados contra PII. |
| **14. Acessibilidade (A11y)** | Excelente | Conformidade comprovada em 150% e 200% de escala, Safe Area preservada, rótulos multilinhas e rolagem com teclado virtual. |
| **15. Prontidão Open Source** | Excelente | Código e documentação de alto nível; arquivo `LICENSE` (Licença MIT) formalizado e publicado. |

---

## 7. Histórico dos Commits Criados e Publicados em `origin/dev`

Os 6 commits atômicos foram criados e publicados em `origin/dev` via push fast-forward direto (base `42a3e397d3921777cb952c96e0de03d7d6e20f0c` -> HEAD `5aa5d6becf591ccce0dd4b535a1b82a75e0a6221`):

1. **`a5dcc120a21e54fb6d82f72b3dc9aca315cb855a`**: `feat(finance): implementar estornos e idempotência persistida`
   - Migrations, models (`ReceiptReversal`, `IdempotentOperation`), actions (`ReverseReceipt`), controllers, resources e testes da API relacionados a estornos e decisões de idempotência persistidas (Decisão 0004). (20 arquivos alterados)
2. **`204fb06d7b27e3d90c01c080d52c38c06db1105c`**: `feat(accounts): adicionar gestão e correção de contas financeiras`
   - Migrations e endpoints de contas, telas mobile de edição/arquivamento e testes correspondentes (Decisão 0005). (12 arquivos alterados)
3. **`477f5a6a78297d5548cb6c2e30a5c417ccd99d1c`**: `feat(payables): implementar pagamentos, cartões e recorrências`
   - Migrations e endpoints de payables/cards/recurrences, telas e repositórios mobile de A pagar e testes (Decisão 0006). (32 arquivos alterados)
4. **`ed58d6c4756e67851ec47cc3094bb586c0d94f97`**: `feat(mobile): aplicar identidade fintech e acessibilidade`
   - Assets da marca, tokens visuais fintech, tema, `AccessibleFieldWrapper`, `date_field.dart`, Safe Area nativa e suporte a 150%/200% de escala de texto. (65 arquivos alterados)
5. **`b75b6a8ee01cf71ffd4d1c11033665fd238aeaa7`**: `test(mobile): adicionar integração e evidências visuais`
   - Teste de integração de evidências visuais (`generate_evidences_test.dart`), scripts auxiliares e catálogo com as 15 capturas oficiais em `prints/`. (20 arquivos alterados)
6. **`5aa5d6becf591ccce0dd4b535a1b82a75e0a6221`**: `docs: consolidar documentação e apresentação do projeto`
   - Consolidação das diretrizes em `docs/project-guidelines.md`, `README.md` reformulado, `LICENSE` (MIT), `HANDOFF.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `docs/archive/` e decisões arquiteturais. (24 arquivos alterados)

---

## 8. Situação Atual e Próximos Passos

- **Branch remota `origin/dev`**: Sincronizada com `dev` em `5aa5d6becf591ccce0dd4b535a1b82a75e0a6221`.
- **Branch remota `origin/main`**: Intocada em `42a3e397d3921777cb952c96e0de03d7d6e20f0c`.
- **Arquivos locais preservados**:
  - `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (alterações locais de assinatura)
  - `apps/mobile/ios/Runner/Info.plist` (configurações locais de runner)
  - `apps/mobile/devtools_options.yaml` (ferramentas locais de depuração)
  - `scripts/run-mobile.sh` (script utilitário local de execução rápida)
  - `design/screenshots/` (captura histórica `simulator_state.png`)
- **Próximas Etapas Sugeridas**:
  - Monitoramento da pipeline de CI no GitHub Actions (`.github/workflows/ci.yml`).
  - Futuro Pull Request de `dev` para `main` quando aprovado pelo mantenedor.
