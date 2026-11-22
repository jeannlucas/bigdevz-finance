# BigDev.Z Finance — Transição Operacional (Handoff)

> **Atualizado em:** 2026-11-21 21:50 (UTC-03:00)  
> **Branch ativa:** `feature/melhorias-financeiro-categorias-recorrencias-ux`  
> **Base branch:** `dev`  
> **Status Operacional:** ✅ HOMOLOGAÇÃO MULTIPLATAFORMA NATIVA E BACKPRESSURE 100% VERDES (iOS Nativo, Android Nativo, Safari Móvel, Emulação Chrome e Chrome Desktop com asserções estritas e `./scripts/check.sh --full` aprovado com zero erros)  
> **Soberania Git:** Commits, pushes e merges sob autoridade exclusiva de Jeann Lucas. Nenhuma alteração publicada sem autorização prévia e explícita.

---

## 1. Resumo Executivo das Correções Operacionais Concluídas

### 1.1 Asserções Estritas em `six_features_homologation_test.dart`
O teste nativo de homologação (`apps/mobile/integration_test/six_features_homologation_test.dart`) foi refatorado para eliminar condições permissivas ou condicionais não legítimas. O teste falha estritamente se qualquer elemento, ação, saldo ou estado divergir:
1. **Fluxo Wise e Débito Direto:**
   - Conferência inicial do saldo da Wise na aba Contas: validação estrita de `WISE GLOBAL` e `R$ 100,00`.
   - Acionamento do botão obrigatório `"Registrar despesa paga (débito em conta)"`.
   - Seleção da conta de origem Wise e exibição do teclado nativo do sistema com captura obrigatória (`ios_real_02_wise_debit_keyboard_open.png` e `android_real_02_wise_debit_keyboard_open.png`).
   - Preenchimento estrito de `35,90`, descrição e seleção da subcategoria `ENERGIA`.
   - Confirmação e verificação de fechamento do modal.
   - Conferência de saldo pós-débito na aba Contas: validação estrita de `R$ 64,10`.
   - Conferência no Extrato: saída única de `R$ 35,90` com badge `[⚡ ENERGIA]` (`findsOneWidget`).
   - Estorno pela interface: navegação até A Pagar > Pagas, abertura do detalhamento da conta, clique em `"Estornar"`, preenchimento da justificativa e confirmação.
   - Conferência de estorno: lançamento contábil compensatório no Extrato e recomposição imediata do saldo da Wise para `R$ 100,00`, sem obrigação em aberto (`cancelled_at` registrado no backend).
2. **Fluxo DUCZ Benefícios (PJ):**
   - Transição para o espaço PJ, abertura da Carteira de Contas e validação da conta `"BENEFÍCIOS DA EMPRESA"` vinculada à DUCZ Benefícios com saldo de `R$ 500,00` e logotipo oficial.
3. **Fluxo Recorrência Variável (PJ):**
   - Navegação até A Pagar, ativação do filtro `"Valor a informar"` e validação de faturas variáveis.
4. **Fluxo Central de Avisos e Persistência Pós-Login:**
   - Retorno ao espaço PF e validação do contador ativo no sininho de notificações (`Badge` com contador pendente).
   - Abertura do modal `"Notificações e Vencimentos"`, execução da ação de dispensar aviso (`"Dispensar aviso"`), fechamento e validação de decremento do contador.
   - Logout formal via `SessionController.logout()`, conferência da reabertura da tela de login, novo login autenticado (`dev@bigdevz.com`) e validação da persistência do estado no backend (o aviso dispensado não retorna ao contador).
5. **Temas Claro e Escuro:**
   - Alternância de aparência no simulador/emulador com validação visual e contraste de layout.

---

### 1.2 Blindagem e Validação do Servidor de Captura (`scripts/screenshot_server.py`)
O servidor de homologação foi blindado conforme exigências do mantenedor:
- **Binding estrito:** Escuta exclusivamente na interface loopback (`127.0.0.1:9876`).
- **Validação de Parâmetros:** Whitelist de alvos permitidos (`{'ios', 'android'}`) e validação de nome de arquivo por regex (`^[a-zA-Z0-9_-]{1,120}$`).
- **Prevenção de Path Traversal:** Resolução canônica de caminhos com `os.path.realpath` garantindo gravação estrita em `prints/homologacao/`.
- **Validação Binária de PNG:** Checagem de código de saída das ferramentas (`simctl` e `adb`), verificação de magic bytes PNG (`\x89PNG\r\n\x1a\n`), tamanho mínimo e integridade estrutural via `PIL.Image.open().verify()`. Responde HTTP 200 somente em caso de PNG íntegro e HTTP 500 com deleção de arquivos corrompidos/parciais em falhas.
- **Fail-Closed no Teste:** O teste Flutter sinaliza falha fatal imediatamente se qualquer captura obrigatória falhar ou retornar status diferente de 200.

---

## 2. Execuções Nativas Sequenciais (Memória Isolada)

Para evitar sobrecarga de memória no Mac do desenvolvedor, os ambientes foram executados rigorosamente um por vez:

1. **iOS Simulator (`iPhone 18 Pro`, UDID `27E240C5-8C09-4606-B0DE-4512BA0154BC`, iOS 27.2):**
   - Dispositivo inicializado via `xcrun simctl boot`.
   - Suíte `six_features_homologation_test.dart` executada: **100% verde (`All tests passed!`)**.
   - Todas as 12 capturas obrigatórias validadas (`ios_real_00` até `ios_real_11`).
   - Simulador desligado imediatamente após a conclusão (`xcrun simctl shutdown`).

2. **Android Emulator (`Medium_Phone_API_37.0`, `emulator-5554`, Android 17 / API 37):**
   - Dispositivo iniciado sem snapshot e sem áudio.
   - Port forwarding reverso configurado via ADB (`adb reverse tcp:9876 tcp:9876` e `adb reverse tcp:8000 tcp:8000`).
   - Suíte `six_features_homologation_test.dart` executada: **100% verde (`All tests passed!`)**.
   - Todas as 12 capturas obrigatórias validadas (`android_real_00` até `android_real_11`), incluindo o teclado GBoard nativo aberto na tela.
   - Emulador encerrado imediatamente após a conclusão (`adb emu kill`).

---

## 3. Matriz de Homologação Multiplataforma Segregada

| Fluxo / Melhoria | Chrome Desktop (1280x800) | Safari Móvel (iOS Simulator) | Emulação Chrome (375x812) | App iOS Instalado (iPhone 18 Pro) | App Android Instalado (API 37) | Evidências Capturadas |
|---|---|---|---|---|---|---|
| **1. Categorias e Subcategorias** | ✅ Aprovado | ℹ️ Abertura da aplicação | ✅ Aprovado | ✅ Aprovado (Asserção estrita) | ✅ Aprovado (Asserção estrita) | [`seq_05_report_distribution.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/seq_05_report_distribution.png), [`ios_real_04_statement_with_wise_debit.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/ios_real_04_statement_with_wise_debit.png) |
| **2. Ícones e Cores Predefinidas** | ✅ Aprovado | ℹ️ Abertura da aplicação | ✅ Aprovado | ✅ Aprovado (Asserção estrita) | ✅ Aprovado (Asserção estrita) | [`real_18_category_icon_color_selector.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/real_18_category_icon_color_selector.png), [`ios_real_10_theme_light_overview.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/ios_real_10_theme_light_overview.png) |
| **3. Wise e DUCZ Benefícios** | ✅ Aprovado | ℹ️ Abertura da aplicação | ✅ Aprovado | ✅ Aprovado (Asserção estrita) | ✅ Aprovado (Asserção estrita) | [`ios_real_06_accounts_list_pj.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/ios_real_06_accounts_list_pj.png), [`android_real_06_accounts_list_pj.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/android_real_06_accounts_list_pj.png) |
| **4. Recorrência Variável** | ✅ Aprovado | ℹ️ Abertura da aplicação | ✅ Aprovado | ✅ Aprovado (Asserção estrita) | ✅ Aprovado (Asserção estrita) | [`real_12_variable_recurrence_awaiting_amount.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/real_12_variable_recurrence_awaiting_amount.png), [`ios_real_07_payables_variable_recurrence.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/ios_real_07_payables_variable_recurrence.png) |
| **5. Compra no Débito com Teclado Aberto** | ✅ Aprovado | ℹ️ Abertura da aplicação | ✅ Aprovado | ✅ Aprovado (Teclado aberto) | ✅ Aprovado (GBoard aberto) | [`android_real_02_wise_debit_keyboard_open.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/android_real_02_wise_debit_keyboard_open.png), [`ios_real_02_wise_debit_keyboard_open.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/ios_real_02_wise_debit_keyboard_open.png) |
| **6. Sininho de Notificações e Persistência** | ✅ Aprovado | ℹ️ Abertura da aplicação | ✅ Aprovado | ✅ Aprovado (Persistência validada) | ✅ Aprovado (Persistência validada) | [`ios_real_08_notifications_modal.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/ios_real_08_notifications_modal.png), [`ios_real_09_bell_persisted_after_fresh_login.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/ios_real_09_bell_persisted_after_fresh_login.png) |

> **Nota sobre o Safari Móvel:** Conforme instrução do mantenedor, o alcance observado no Safari móvel é registrado estritamente como **“abertura da aplicação”** ([`real_21_ios_simulator_safari.png`](file:///Users/jeannlucasdev/Documents/Projetos/Desenvolvimento/bigdevz-finance/prints/homologacao/real_21_ios_simulator_safari.png)), mantendo a execução completa e aprofundada dos 6 fluxos nos aplicativos nativos instalados (iOS e Android), no Chrome Desktop e na emulação Chrome mobile.

---

## 4. Comprovação de Backpressure Final (`./scripts/check.sh --full`)

Comando executado:
```bash
./scripts/check.sh --full
```
Resultado: **100% VERDE COM ZERO ERROS**
- **Domínio Financeiro PHP:** 15 testes, 0 falhas (PASS).
- **Análise Estática Dart (`flutter analyze`):** `No issues found!` (0 alertas, 0 erros).
- **Linter PHP (Laravel Pint):** 180 arquivos validados (PASS).
- **Formatação Dart (`dart format`):** 173 arquivos verificados (0 changed).
- **Suíte Flutter (`flutter test`):** **358 testes PASS (100% verde)**.
- **Suíte API Laravel (`php artisan test`):** **224 testes PASS (2.126 asserções)** em PostgreSQL real.
- **Testes de Governança SemVer, Hardening SSH e Deploy VPS:** 21 testes PASS (100% verde).

---

## 5. Estado do Repositório e Próximos Passos (Soberania Git)

- **Branch Atual:** `feature/melhorias-financeiro-categorias-recorrencias-ux`
- **Status:** Todas as 6 melhorias, testes unitários, testes de integração, migrações, suítes nativas com asserções estritas no iOS Simulator e no Android Emulator, servidor de screenshot blindado em loopback e qualidade Backpressure concluídos com 100% de sucesso.
- **Bloqueio de Soberania:** O agente aguarda autorização específica e expressa de Jeann Lucas para:
  1. Realizar o commit dos arquivos alterados na branch `feature/melhorias-financeiro-categorias-recorrencias-ux`.
  2. Fazer o checkout para a branch `dev` e realizar o merge local da feature.
  3. Reexecutar a validação integrada na `dev` integrada.
  4. Executar o `git push origin dev`.
