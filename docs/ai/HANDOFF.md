# Handoff Canônico Universal — BigDev.Z Finance

> **Autoridade Canônica de Continuidade:** BigDev.Z Finance<br>
> **Aplica-se a:** Google Antigravity e OpenAI Codex operando no projeto.<br>
> **Protocolo:** Handoff Universal Bidirecional BigDev.Z (GOV-03 / GOV-06.B).<br>
> **Registro Histórico Precedente:** [`HANDOFF.md`](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/HANDOFF.md) (preservado na raiz como histórico consolidado até 09/10/2026).

---

## 1. Contexto e Identidade do Projeto

- **Produto:** BigDev.Z Finance — Sistema financeiro pessoal e empresarial (multi-espaço PF/PJ) de alta integridade e precisão matemática.
- **Stack:**
  - **Mobile:** Flutter / Dart (3.x) modular por features em `apps/mobile/` (`features/accounts`, `payables`, `agreements`, `summary`).
  - **Backend:** Laravel 13 monólito modular em `apps/api/` com Actions dedicadas (`ReceiveInstallment`, `ReverseReceipt`).
  - **Banco de Dados:** PostgreSQL com restrições compostas `(id, space_id)` e advisory locks para controle de concorrência.
- **Modo do Repositório:** **DESENVOLVIMENTO ATIVO**.
- **Licença:** MIT Formalizada ([LICENSE](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/LICENSE)).
- **Diretrizes e Regras de Domínio:** Consolidadas em [`docs/project-guidelines.md`](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/docs/project-guidelines.md) e [`docs/architecture.md`](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/docs/architecture.md).

---

## 2. Estado Operacional Atual e Máquina de Estados

- **Estado Atual:** **`VALIDADO TECNICAMENTE`** / **`AGUARDANDO_APROVACAO`** (para futura promoção de `dev` para `main`).
- **Branch Ativa:** `dev` (apontando para commit `0f49606bf5ee57ce29256209ac51991f992cef89`).
- **Branch de Produção:** `main` (intocada, aguardando aprovação explícita do mantenedor).
- **Paridade Remota:** Branch local `dev` com histórico publicado e alinhado com `origin/dev`.
- **Integridade do Core Financeiro:** 100% verde em todas as suítes de testes automatizados (domínio, API, concorrência e mobile).

---

## 3. Decisões Arquiteturais e Histórico Preservado

Todas as decisões técnicas e arquiteturais consolidadas nas etapas anteriores permanecem válidas e vinculantes:

1. **Decisão 0001 (Monólito Modular no Backend):** Laravel 13 estruturado em camadas coesas (Domínio puro, Actions específicas e Controllers/Resources REST).
2. **Decisão 0002 (Integridade Monetária Inegociável):** Dinheiro exato sem `float`. Strings decimais com 2 casas na interface/API, inteiros na menor unidade (centavos) no núcleo e limite de `999999999999.99`. Distribuição determinística de centavos e preservação do dia de referência.
3. **Decisão 0003 (Isolamento Multi-Espaço PF/PJ):** Chaves estrangeiras compostas `(id, space_id)` em todas as tabelas transacionais. No mobile, isolamento absoluto de árvore de widgets via `KeyedSubtree` para alternância de contexto sem vazamento de estado.
4. **Decisão 0004 (Estornos e Idempotência Persistida):** Tabela `IdempotentOperation` associada a advisory locks por usuário/espaço/operação. Estornos registrados via `ReceiptReversal` sem apagar histórico efetivado.
5. **Decisão 0005 (Gestão e Correção de Contas):** Edição e arquivamento de contas financeiras sem violar integridade de lançamentos pretéritos.
6. **Decisão 0006 (Metodologia de Evidências em 375pt):** Harness de acessibilidade emulando viewport 375pt (iPhone SE / 12 mini) com safe area real preservada (`EdgeInsets.only(top: 59, bottom: 34)`), eliminando falsos positivos de sobreposição com a status bar do sistema.

> Detalhamento integral das causas raízes e auditorias históricas disponível em [`HANDOFF.md`](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/HANDOFF.md).

---

## 4. Alterações em Andamento e Working Tree

Inventário detalhado das alterações locais presentes no repositório:

| Arquivo | Tipo | Descrição e Finalidade |
| :--- | :--- | :--- |
| `HANDOFF.md` | Modificado | Handoff original na raiz com banner de transição para o canônico. |
| `AGENTS.md` | Modificado | Instruções locais atualizadas com referências canônicas globais e a docs/ai/HANDOFF.md. |
| `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` | Modificado | Configurações locais de build e assinatura do Runner iOS. |
| `apps/mobile/ios/Runner/Info.plist` | Modificado | Configurações de permissões e chaves locais do runner iOS. |
| `apps/mobile/lib/features/summary/summary_tab.dart` | Modificado | Refatoração e aprimoramento ergonômico da aba de resumo mobile. |
| `apps/mobile/devtools_options.yaml` | Não rastreado | Preferências locais de profiling do Flutter DevTools. |
| `apps/mobile/test/features/summary_test.dart` | Não rastreado | Testes de unidade e widgets para as alterações da aba de resumo. |
| `design/screenshots/` | Não rastreado | Diretório contendo captura histórica de referência (`simulator_state.png`). |
| `scripts/run-mobile.sh` | Não rastreado | Utilitário local para inicialização rápida do ambiente mobile. |
| `docs/ai/HANDOFF.md` | Criado | Este documento (canônico universal de governança). |

---

## 5. Catálogo de Evidências Visuais e Demonstração Real (GOV-04)

- **Diretório Oficial de Capturas:** [`prints/`](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/prints/) (15 capturas oficiais ativas, geradas no simulador iPhone 17 Pro e harness 375pt).
- **Diretório Histórico:** [`design/screenshots/simulator_state.png`](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/design/screenshots/simulator_state.png) (captura de referência técnica).
- **Regra de Plataforma:** **Validação em Android não convalida iOS; validação em iOS não convalida Android.**
- **Inventário de Evidências Oficiais:**
  - **Tema Escuro (Dark Mode - 402x874pt):**
    - `dark_01_resumo_pf.png`: Resumo financeiro PF no tema escuro.
    - `dark_02_resumo_pj.png`: Resumo financeiro PJ no tema escuro.
    - `dark_03_carteira_pf.png`: Carteira de contas PF no tema escuro.
    - `dark_04_carteira_pj.png`: Carteira de contas PJ no tema escuro.
    - `dark_05_novo_payable_pf.png`: Formulário de nova conta a pagar PF no tema escuro.
    - `dark_06_novo_payable_pj.png`: Formulário de nova conta a pagar PJ no tema escuro.
  - **Tema Claro (Light Mode - 402x874pt):**
    - `light_01_resumo_pf.png`: Resumo financeiro PF no tema claro.
    - `light_02_resumo_pj.png`: Resumo financeiro PJ no tema claro.
    - `light_03_carteira_pf.png`: Carteira de contas PF com dados estritamente de PF e cartão azul escuro.
    - `light_04_carteira_pj.png`: Carteira de contas PJ no tema claro.
    - `light_05_novo_payable_pf.png`: Formulário de nova conta a pagar PF no tema claro.
    - `light_06_novo_payable_pj.png`: Formulário de nova conta a pagar PJ no tema claro.
  - **Acessibilidade e Fontes Ampliadas (Harness 375pt):**
    - `a11y_375px_scale_150_formulario.png`: Formulário com texto ampliado em 150% (1.5x) sem sobreposição.
    - `a11y_375px_scale_150_seletor.png`: Seletor de contas/espaço com texto ampliado em 150%.
    - `a11y_375px_scale_200_scroll.png`: Comportamento de rolagem e legibilidade extrema com texto em 200% (2.0x).

---

## 6. Auditoria de QA, Testes e Verificação (25 Práticas)

Os comandos reais de verificação aprovados na última auditoria de consolidação:

1. **Testes de Domínio:** `make test-domain`
   - **Resultado:** 11 testes, 0 falhas (cálculo de centavos, bissextos, datas e tolerâncias).
2. **Testes de Integração e API:** `make test-api`
   - **Resultado:** 71 testes, 1.011 asserções aprovadas (PostgreSQL real `bigdevz_finance_test`, rollback, concorrência com subprocessos, estornos e idempotência).
3. **Smoke Tests:** `make smoke-api`
   - **Resultado:** 100% aprovado contra o container Docker da API.
4. **Padronização de Código PHP:** `make lint-api` (Laravel Pint)
   - **Resultado:** 100% de conformidade de estilo.
5. **Formatação Dart:** `dart format --output=none --set-exit-if-changed lib test integration_test`
   - **Resultado:** 75 arquivos formatados, 0 alterações pendentes.
6. **Análise Estática Dart:** `flutter analyze` em `apps/mobile/`
   - **Resultado:** `No issues found!`.
7. **Testes Unitários e Widgets:** `flutter test` em `apps/mobile/`
   - **Resultado:** 86 testes aprovados.

---

## 7. Governança Git, Soberania Humana e Segurança

- **Branch de Trabalho:** `dev`. Todo desenvolvimento ocorre exclusivamente nesta branch.
- **Branch de Produção:** `main`. Push direto é estritamente proibido. Promoção somente via merge fast-forward aprovado.
- **Soberania do Desenvolvedor Jeann Lucas:** Commits são preparados pelo agente mas criados e autorizados exclusivamente pelo Jeann. Proibido criar commits, tags ou branches autonomamente.
- **Segurança de Credenciais:** Proibido comitar `.env` real, tokens ou dados pessoais (PII). Variáveis de ambiente vivem exclusivamente em `.env` ignorado pelo Git, com templates em `.env.example`.
- **Deploy:** Nenhum deploy automático é realizado por agentes de IA.

---

## 8. Próximos Passos Imediatos e Retomada Multi-IA

Roteiro de continuidade para **Google Antigravity** e **OpenAI Codex**:

1. **Manutenção da Aba de Resumo:** Concluir a validação e testes unitários das alterações locais em `apps/mobile/lib/features/summary/summary_tab.dart` e `summary_test.dart`.
2. **Revisão de Staging:** Apresentar o diff limpo das alterações locais para revisão e commit pelo desenvolvedor Jeann Lucas.
3. **Acompanhamento de CI:** Monitorar a integridade dos workflows em `.github/workflows/ci.yml`.
4. **Atualização Contínua deste Documento:** Qualquer nova sessão com trabalho material deve encerrar atualizando as seções 2, 4 e 8 deste arquivo [`docs/ai/HANDOFF.md`](file:///Users/jeannlucasdev/Documents/Projetos/BigDev.Z%20Finance/docs/ai/HANDOFF.md).


## Registro de Homologação — Checkpoint FINANCE-QA-01 (15/10/2026)

- **Modo:** QA Nativo + Inspeção Visual + Auditoria Independente.
- **Branch Ativa:** `dev` (HEAD `0f49606bf5ee57ce29256209ac51991f992cef89`), staging vazio, nenhum commit ou push realizado.
- **Ambiente & Portas:** API Laravel e PostgreSQL mantidos na porta 8000 e 5440 via Docker Compose existente sem mutações de infraestrutura.
- **Execução Multiplataforma:**
  - **iOS:** Simulador `iPhone 17 Pro` (iOS 26.5), executando `generate_evidences_test.dart` e `inspection_test.dart` contra a API real.
  - **Android:** Emulador `emulator-5554` (`bigdevz_api36`, API 36 / Android 16), executando `inspection_test.dart` com túnel de rede e conectividade validada.
- **Suíte de Testes Automatizados:**
  - `apps/mobile/test/features/home_shell_test.dart`: 4 novos testes cobrindo alternância PF/PJ no HomeShell real, mudança dinâmica de tema (Azul Profundo ↔ Verde Esmeralda), integridade e ciclo de vida efêmero da privacidade do saldo.
  - `apps/mobile/test/features/summary_test.dart`: 11 testes cobrindo isolamento estrito de `spaceId`, descarte de respostas obsoletas, privacidade de valores monetários, recuperação de erro, pull-to-refresh e acessibilidade 150%/200% em 375pt.
  - **Total Flutter:** 101 testes unitários e de widgets aprovados (0 falhas).
  - **Análise Estática Dart:** `flutter analyze` com 0 issues (`No issues found!`).
  - **Domínio Financeiro PHP:** `make test-domain` com 11/11 testes aprovados (0 falhas).
- **Evidências Visuais Primárias:**
  - Diretório oficial preservado: `prints/` intacto sem mutações.
  - Novo diretório de evidências: `prints/qa-01/` com 15 capturas iOS e 13 capturas Android demonstrando o Dashboard modernizado nos modos claro/escuro para PF e PJ.
- **Auditoria Independente OpenAI Codex (CLI 0.160.0, `--sandbox read-only`):**
  - Parecer: **APROVADO COM RESSALVAS**.
- **Estado Operacional:** Pronto para decisão e homologação humana do mantenedor Jeann Lucas.

---

## Registro de Homologação — Checkpoint FINANCE-UX-01 (15/10/2026)

- **Missão:** Central de Configurações, Personalização de Aparência, Privacidade Financeira Compartilhada e Refinamento de UX.
- **Modo:** IMPLEMENTAÇÃO CONTROLADA + UX/UI + QA + AUDITORIA INDEPENDENTE.
- **Branch Ativa:** `dev` (HEAD `0f49606bf5ee57ce29256209ac51991f992cef89`), staging vazio, zero commits, zero pushes, zero deploys.
- **Arquitetura & Implementação:**
  1. `PreferencesController` (`apps/mobile/lib/features/settings/preferences_controller.dart`): controle de `ThemeMode` (`system`, `light`, `dark`), `hideValuesByDefault` e `obscureValues` volátil na sessão, persistido via `SessionStorage` de forma transparente e segura, com proteção `try/catch` contra falhas de storage.
  2. `SettingsScreen` (`apps/mobile/lib/features/settings/settings_screen.dart`): Central de Configurações acessível pelo menu "Conta" do `HomeShell`, com seções Aparência, Privacidade Financeira e Sobre o Aplicativo, acessibilidade para leitores de tela (`Semantics(selected: ..., inMutuallyExclusiveGroup: true)`) e suporte comprovado a texto ampliado a 200%.
  3. `ThemeMode` e Identidade Multi-Tenant: `Brightness` derivado da preferência global sem comprometer a identidade das cores dos espaços: PF = Azul Profundo (`#2459D4`), PJ = Verde Esmeralda (`#137A63`).
  4. Privacidade Financeira de Sessão: Máscara consistente (`R$ ••••••••`) no Dashboard (Master Card, cards secundários e totalizadores) e Carteira de Contas (`accounts_tab.dart` e `_AccountTile`), preservada durante a navegação entre abas e alternância de espaços PF/PJ.
  5. Ciclo de Vida do Logout e Expiração: Conexão no `bootstrap.dart` via listener de `SessionController` para resetar a privacidade para `hideValuesByDefault` estritamente quando `session.status == SessionStatus.signedOut` (logout confirmado ou expiração). O cancelamento do diálogo de logout preserva integralmente a privacidade da sessão ativa.
  6. Refinamentos de UX: Espaçamento vertical confortável (`const SizedBox(height: 12)`) após campos com `maxLength` em `PayableFormScreen` e indicadores limpos no carrossel de contas.
- **Suíte de Testes Automatizados (100% de Aprovação):**
  - `apps/mobile/test/features/preferences_test.dart`: 13 testes cobrindo a matriz A1-A12 e P1-P20, cancelamento de logout, expiração de sessão, resiliência de storage e semântica de acessibilidade.
  - `apps/mobile/test/features/home_shell_test.dart`: 4 testes atualizados validando persistência da privacidade através da navegação de abas e integridade dos atalhos rápidos.
  - **Total Flutter:** 114 testes aprovados (0 falhas).
  - **Análise Estática Dart:** `flutter analyze` com 0 issues (`No issues found!`).
  - **Domínio Financeiro PHP:** `make test-domain` com 11 testes aprovados (0 falhas).
- **Evidências Visuais Nativas Geradas (`prints/ux-01/`):**
  - `ux_01_settings_light.png`: Tela de Configurações no tema Claro.
  - `ux_02_settings_dark.png`: Tela de Configurações no tema Escuro.
  - `ux_03_dashboard_pf_hidden_balance.png`: Dashboard PF com saldo mascarado (`R$ ••••••••`).
  - `ux_04_accounts_pf_hidden_balance.png`: Carteira de Contas PF com saldos mascarados.
  - `ux_05_accounts_pj_hidden_balance.png`: Carteira de Contas PJ com saldos mascarados.
  - `ux_06_dashboard_pj_hidden_balance.png`: Dashboard PJ com saldos mascarados.
  - `ux_07_dashboard_pf_revealed_balance.png`: Dashboard PF com valores revelados e ícone semântico `view`.
- **Auditoria Independente OpenAI Codex CLI (0.160.0, `--sandbox read-only`):**
  - Parecer Inicial: REPROVADO (apontamento de reset precoce no cancelamento de saída).
  - Ajustes Executados: Remoção do reset antecipado, listener atômico em `SessionController`, `try/catch` de resiliência e semântica de rádio.
  - Parecer de Reavaliação Final: **APROVADO COM RESSALVAS** (confirmando resolução do defeito de privacidade, conexão efetiva de encerramento, e semântica de seleção).
- **Estado Final:** Concluído com sucesso. Aguardando revisão e autorização soberana do desenvolvedor Jeann Lucas para commit/versionamento.

---

## Registro de Homologação — Checkpoint FINANCE-UX-02 (15/10/2026)

- **Missão:** Refinamento Final de UX, Privacidade Financeira em Listagens de Consulta, Semântica Acessível e Homologação Android/iOS.
- **Modo:** IMPLEMENTAÇÃO CONTROLADA + QA + AUDITORIA INDEPENDENTE.
- **Branch Ativa:** `dev` (HEAD `0f49606bf5ee57ce29256209ac51991f992cef89`), staging vazio, zero commits, zero pushes, zero merges.
- **Arquitetura & Refinamentos Concluídos:**
  1. **Contraste Acessível no Tema Escuro (`settings_screen.dart`):** Substituído `Colors.black26` pelo valor semântico de alto contraste `theme.colorScheme.outline.withValues(alpha: 0.7)` no trailing do `_ThemeOptionTile`, garantindo distinção nítida dos indicadores desmarcados sem ofuscar o item ativo.
  2. **Acessibilidade e Semântica do Botão de Privacidade (`summary_tab.dart`):** Envolvido com `Semantics(button: true, label: obscureBalance ? 'Mostrar saldo' : 'Ocultar saldo')`, fornecendo anúncio correto para tecnologias assistivas (TalkBack/VoiceOver) alinhado aos ícones dinâmicos `AppIcons.view` e `AppIcons.viewOff`.
  3. **Privacidade Financeira em Listagens de Consulta:**
     - `agreements_tab.dart`: `AgreementCard` escuta `PreferencesController.obscureValues` e aplica máscara nos `MoneyText` principal e secundário, e sanitiza a string e o `semanticsLabel` do indicador de recebimento ('Recebido: ••••••' e 'Recebido da conta: oculto').
     - `payables_tab.dart`: `PayableCard` escuta `PreferencesController.obscureValues` e mascara os `MoneyText` de valor total, restante a pagar e pago líquido.
     - Preservação da conferência visual em formulários transacionais (`PayableFormScreen`, `ReceiptFormScreen`).
  4. **Exibição da Versão e Build do Aplicativo:** Novas constantes desacopladas `appVersion`, `appBuildNumber` e `appVersionLabel` em `config.dart`, alinhadas ao `pubspec.yaml` (`1.0.0+1`), exibidas dinamicamente na Central de Configurações sem sobrecarga de dependências desnecessárias.
  5. **Tema Automático (`ThemeMode.system`):** Homologado com acompanhamento dinâmico do brilho do sistema operacional.
- **Suíte de Testes Automatizados (100% de Aprovação):**
  - `apps/mobile/test/features/preferences_test.dart`: 15 testes aprovados (adicionados testes de versão real do app e mascaramento nas abas de A Receber e A Pagar).
  - Suíte completa do Flutter: **116 testes aprovados** (0 falhas).
  - Análise estática Dart: `flutter analyze` com **0 issues** (`No issues found!`).
  - Formatação Dart: `dart format --output=none --set-exit-if-changed` com **81 arquivos 100% conformes**.
  - Domínio Financeiro PHP: `make test-domain` com **11/11 testes aprovados** (0 falhas).
- **Evidências Visuais Nativas Geradas (`prints/ux-02/` - 20 Capturas Reais):**
  - **10 capturas iOS (iPhone 17 Pro):**
    - `ux_01_settings_light.png`: Configurações no tema Claro com versão e build reais.
    - `ux_02_settings_dark.png`: Configurações no tema Escuro com contraste corrigido no radio button.
    - `ux_02b_settings_auto_light.png`: Configurações com tema Automático ativo.
    - `ux_03_dashboard_pf_hidden_balance.png`: Dashboard PF com valores mascarados e botão semântico.
    - `ux_04_agreements_pf_hidden.png`: Aba A Receber com `AgreementCard` mascarado.
    - `ux_05_payables_pf_hidden.png`: Aba A Pagar com `PayableCard` mascarado.
    - `ux_06_accounts_pf_hidden_balance.png`: Carteira de Contas PF com saldos mascarados.
    - `ux_07_accounts_pj_hidden_balance.png`: Carteira de Contas PJ com privacidade preservada.
    - `ux_08_dashboard_pj_hidden_balance.png`: Dashboard PJ com valores mascarados.
    - `ux_09_dashboard_pf_revealed_balance.png`: Dashboard PF com valores revelados e ícone `viewOff`.
  - **10 capturas Android (Pixel / API 36):**
    - `android_ux_01_settings_light.png` a `android_ux_09_dashboard_pf_revealed_balance.png`: Homologação nativa idêntica no ecossistema Android Material 3.
- **Auditoria Independente OpenAI Codex CLI (0.160.0, `--sandbox read-only`):**
  - Parecer: **APROVADO COM RESSALVAS**.
  - Confirmação de integridade dos 20 PNGs, 11 testes PHP, governança Git estrita e conformidade das regras financeiras e sementes de espaço PF (`#2459D4`) e PJ (`#137A63`).
  - Ressalva anotada: execução Flutter bloqueada no ambiente sandbox Codex por cache do SDK somente leitura e recomendação de futura sincronização automatizada dos metadados de versão com o binário instalado.
- **Estado Operacional:** `VALIDADO TECNICAMENTE` / Homologação nativa concluída em Android e iOS.

---

## 5. Checkpoint FINANCE-COMMIT-01 (16/10/2026) — Auditoria de Versionamento e Consolidação Git

- **Objetivo**: Auditoria exaustiva de alterações, exclusão de segredos e configurações locais de ambiente, validação técnica pré-commit e criação do commit local na branch `dev`.
- **Branch**: `dev` (após o commit `0f49606bf5ee57ce29256209ac51991f992cef89`).
- **Governança Git Estrita**:
  - `git push`: NÃO EXECUTADO (proibido).
  - `git merge`: NÃO EXECUTADO (proibido).
  - Branch `main`: 100% INTOCADA.
  - Staging seletivo por arquivo: `git add <arquivo>` (PROIBIDO `git add .` ou `git add -A`).
- **Validação Técnica Executada**:
  - `dart format --output=none --set-exit-if-changed`: 81 arquivos verificados, 0 alterações pendentes.
  - `flutter analyze`: Resolvido sem issues (0 warnings/erros).
  - `flutter test`: 116 de 116 testes aprovados (100% verde).
  - `make test-domain`: 11 de 11 testes de domínio aprovados (0 falhas).
  - `git diff --check`: 0 erros de whitespace.
- **Auditoria Independente OpenAI Codex CLI (`--sandbox read-only`)**:
  - Parecer: **APROVADO COM RESSALVAS** para a proposta de commit local na `dev`.
  - Ausência de segredos reais, tokens ou chaves privadas.
  - Preservação estrita das configurações locais particulares de ambiente:
    - `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (Team ID local do mantenedor).
    - `apps/mobile/ios/Runner/Info.plist` (reordenação interna do Xcode).
    - `apps/mobile/devtools_options.yaml` (configurações locais de perfilamento).
    - `scripts/run-mobile.sh` (atalho local de simulação com UUID do device).
    - `apps/mobile/integration_test/ux_evidences_test.dart` (script dependente do `screenshot_server.py` local).
    - Diretórios temporários de capturas de tela dos checkpoints (`prints/qa-01/`, `prints/ux-01/`, `prints/ux-02/`, `design/screenshots/`).
- **Próximos Passos**: Apresentação do relatório consolidado e aguardo da decisão soberana do mantenedor para futuros checkpoints e eventual publicação remota.
