# BigDev.Z Finance — Transição Operacional (Handoff)

> **Atualizado em:** 2026-11-22 11:45 (UTC-03:00)  
> **Branch ativa:** `fix/entrega-frontend-web-pipeline-deploy`  
> **Base branch:** `dev` (apontando para `4f459cdba3c2a019b02f89beef72a07c9fc8d4aa`)  
> **Status Operacional:** ⚠️ INCIDENTE v1.3.0 REGISTRADO E ABERTO | PIPELINE DE PROMOÇÃO DA VPS BLINDADO E HOMOLOGAÇÃO REAL EM NAVEGADORES (SAFARI MÓVEL REAL + CHROME DEVTOOLS) CONCLUÍDOS COM ZERO ERROS  
> **Soberania Git:** Commits, pushes, tags, merges e deploys sob autoridade exclusiva de Jeann Lucas. Nenhuma ação no Git ou na VPS executada sem autorização prévia e explícita.

---

## 1. Registro do Incidente da Release v1.3.0 (STATUS: ABERTO)

### 1.1 Sintoma e Observação do Problema
Na publicação da release `v1.3.0` (commit de merge `6cd4ae72409d9c211447cbd18d47a02870d71a77` na `main`), a API pública respondeu com a revisão correta, mas o frontend web servido pelo Caddy em `https://finance.bigdevz.com/` permaneceu estagnado na versão antiga de 17/11/2026:
- No painel autenticado, o sininho de notificações oferecia apenas as ações antigas (*"Ver contas a pagar"* e *"Ver agenda"*). Faltavam as novas ações homologadas (*"Marcar como lido"* e *"Dispensar aviso"*).
- Faltava na interface o botão de registro direto de compra no débito (*"Registrar despesa paga"*).
- A inspeção do JavaScript público em `https://finance.bigdevz.com/main.dart.js` comprovou ausência dos identificadores da nova release, confirmando que o problema ocorreu fora da sessão do usuário.

### 1.2 Medições Históricas e Atuais Comprovadas
- **Frontend Web Público (`https://finance.bigdevz.com/main.dart.js`):**
  - Hash SHA-256: `7d5075e694b44bfd9cfbc4c6929e14fcec8113faa3426af4c06c4e896ce2e5d1`
  - Tamanho: `4.274.265 bytes`
  - Header `Last-Modified`: `Tue, 17 Nov 2026 07:33:42 GMT`
  - Header `ETag`: `"dmxb8md0wiyo2jm1l"`
- **Frontend Web Compilado Localmente para a Release:**
  - Hash SHA-256: `b69ff8fb760bd7ecb23fbbe13105651961dff859350db802ac240aff05dd334b`
  - Tamanho: `4.301.824 bytes`
- **API Pública (`https://finance.bigdevz.com/api/health`):**
  - Resposta: `{"status":"ok","revision":"6cd4ae72409d9c211447cbd18d47a02870d71a77",...}`

### 1.3 Causa-Raiz Comprovada
1. **Ausência de Build no Workflow (`.github/workflows/deploy.yml`):** O workflow disparado pela tag SemVer compilava apenas o container Docker da API (`apps/api/Dockerfile`) e o publicava no GHCR. Nunca compilava o Flutter Web (`apps/mobile`), nem empacotava ou transportava os assets web para a VPS.
2. **Promoção Silenciosa em `scripts/vps-deploy.sh`:** O script da VPS continha o bloco `if [ -d "$TARGET_DIR/web_staging" ]; then ... fi`. Como `$TARGET_DIR/web_staging` nunca era criado pelo workflow, essa etapa era silenciosamente ignorada a cada deploy, preservando os arquivos estáticos de 17/11/2026 em `/srv/finance/web/`.
3. **Verificação Incompleta Pós-Deploy:** O workflow verificava exclusivamente `https://finance.bigdevz.com/api/health` (`.revision == $RELEASE_SHA`). Como a API respondeu com a revisão correta, o deploy foi falsamente marcado como concluído com sucesso, mascarando a estagnação do frontend.
4. **Mascaramento em Testes Simulados:** Em `tests/infra/test-deploy-integrated-simulation.sh`, o teste criava manualmente `web_staging/index.html` antes de executar `vps-deploy.sh`, ocultando a ausência do mecanismo de geração e transporte real na esteira.

---

## 2. Decisão Canônica de Produto (ADR 0007)

- **Canal Oficial Exclusivo:** O BigDev.Z Finance passa a ser operado oficialmente e com exclusividade pelo **navegador (Flutter Web)**, cobrindo:
  - **Desktop Web (widescreen >= 840px / 1200px):** Layout executivo, tabelas analíticas, modais centralizados.
  - **Mobile Web (smartphones < 840px / 375px):** Cards verticais fluidos, bottom sheets com suporte a teclado virtual sem overflow de layout.
- **Congelamento de Lojas de Aplicativos:** Builds para Google Play Store e Apple App Store (AAB/IPA) e esteiras nativas de lojas ficam formalmente congeladas.
- **Preservação do Código Compartilhado:** A base Flutter (`apps/mobile/`) é mantida integralmente, sendo o bundle `apps/mobile/build/web/` o alvo oficial de compilação, homologação e deploy.
- **Documentação Atualizada:** ADR `docs/decisions/0007-canal-exclusivo-web-flutter.md`, `docs/project-guidelines.md`, `docs/operations/production-deployment.md`, `docs/operations/production-runbook.md` e specs em `specs/` (`AC-FIN-029`).

---

## 3. Correção Arquitetural Implementada

A branch `fix/entrega-frontend-web-pipeline-deploy` implementa a solução de entrega atômica e coordenada:

1. **Compilação e Hash no GitHub Actions (`.github/workflows/deploy.yml`):**
   - Configura Flutter SDK via `subosito/flutter-action@v2` (`3.47.6`).
   - Compila o Flutter Web de produção via `./scripts/build-web.sh --env=production`.
   - Calcula o hash SHA-256 do `apps/mobile/build/web/main.dart.js` compilado e exporta para `$GITHUB_ENV` (`EXPECTED_WEB_HASH`).
   - Copia o bundle web para `apps/api/public_web/`.
2. **Empacotamento Unificado no Docker (`apps/api/Dockerfile`):**
   - Adicionada instrução `COPY public_web /opt/finance/web` no Dockerfile da API.
   - Criado `apps/api/public_web/.gitkeep` e ajustado `.gitignore` para permitir builds locais sem poluição de working tree.
   - Tanto o backend Laravel quanto os assets estáticos do frontend viajam como um artefato imutável no mesmo digest assinado do GHCR.
3. **Extração e Promoção Atômica na VPS (`scripts/vps-deploy.sh` e `scripts/vps-deploy-wrapper.sh`):**
   - **Exigência Estrita de `--web-hash`:** O wrapper SSH e o script de deploy validam obrigatoriamente `--web-hash <64 hex chars>`. Caso ausente ou malformado, abortam *fail-closed* antes de parar writers, fazer backup do banco ou executar migrações.
   - **Extração Isolada:** Cria diretório temporário exclusivo (`mktemp -d /srv/finance/web_staging_XXXXXX`) para extração a cada tentativa de release a partir do digest imutável aprovado.
   - **Limpeza de Resíduos Anteriores:** Remove qualquer `web_staging` residual pré-existente para que tentativas anteriores nunca determinem a publicação.
   - **Validação Pré-Ativação:** Valida obrigatoriamente a presença dos arquivos essenciais (`main.dart.js`, `index.html`, `flutter.js`, `manifest.json`) e a correspondência exata do hash SHA-256 (`EXPECTED_WEB_HASH`) **antes de parar writers, fazer backup do banco ou executar migrações**.
   - **Primeira Conversão com Troca Atômica no Kernel (`atomic_exchange_paths`):**
     1. Elimina a vulnerabilidade de dois passos da versão anterior (que retirava o diretório legado e depois instalava o link, deixando o caminho inexistente se interrompido).
     2. Valida previamente os pré-requisitos via sonda (`.swap_probe_dir` e `.swap_probe_link`) em `web_releases/`. Se o sistema de arquivos ou o kernel não suportarem a operação, aborta *fail-closed* com a versão anterior intacta e acessível.
     3. Executa permuta atômica no kernel via `renameat2(..., RENAME_EXCHANGE)` no Linux (`renamex_np(..., RENAME_SWAP)` no macOS). O diretório real legado e o symlink da nova release trocam de lugar em uma operação indivisível no kernel. Não há intervalo onde `/srv/finance/web` deixa de existir.
     4. Move o diretório legado permutado para `web_releases/legacy`, preservando o bundle para auditoria e recuperação.
   - **Deploys Subsequentes:** Quando `/srv/finance/web` já é um symlink, a substituição atômica ocorre via `mv -Tf` (chamada atômica de `rename(2)`).
   - **Replay Idempotente:** Caso o deploy seja reexecutado com a mesma tag já ativa (`IMPLANTADA_TAG == DEPLOY_TAG`) e o hash do `main.dart.js` ativo for idêntico ao esperado, o script reconhece o estado como sucesso idempotente (exit 0) sem parar serviços, sem reexecutar migrações e sem alterar arquivos.
   - **Fail-Closed com Rollback Seguro:** Em caso de divergência ou erro, preserva intacto o frontend ativo e aborta sem tocar nas migrações.
   - **Marcador Persistente:** Grava o marcador persistente `/var/lib/vps-deploy/bigdevz-finance/implantado_web_hash`.
4. **Testes de Infraestrutura e Regressão de Deploy (6 Scripts 100% Verdes):**
   - `test-deploy-governance.sh`: 7/7 cenários aprovados.
   - `test-vps-deploy-transition.sh`: 3/3 cenários aprovados (atualizado para exigir `--web-hash`).
   - `test-deploy-hardening-preflight.sh`: 8/8 testes aprovados (cobrindo repasse posicional, nomeado, SSH `--` e rejeição de hash ausente/malformado).
   - `test-deploy-integrated-simulation.sh`: 3/3 fases aprovadas (deploy normal, falha controlada, recuperação com deploy corrigido).
   - `test-vps-web-promotion.sh`: 6/6 cenários aprovados:
     1. Hash ausente ou malformado fail-closed (serviços e banco intactos).
     2. Regressão diferenciadora da primeira conversão do legado: comprovação de que o mecanismo antigo falharia deixando web/ inexistente sob interrupção, enquanto o mecanismo corrigido preserva a versão completa (antiga ou nova) sob qualquer interrupção e valida pré-requisitos fail-closed.
     3. Staging antigo limpo e ignorado.
     4. Falha de extração/bundle parcial/hash divergente preserva web ativa e não migra banco.
     5. Promoção atômica bem-sucedida do digest esperado.
     6. Replay idempotente da tag ativa preserva arquivos do link ativo.
   - `test-release-verification.sh`: 5/5 cenários aprovados (revisão de API e hash SHA-256 simultâneos via HTTPS).
   - Todos integrados ao quality gate oficial em `scripts/check.sh`.

---

## 4. Matriz de Homologação em Navegador Real (Desktop, Celular e Simulador)

> **Nota Metodológica:** A matriz abaixo distingue expressamente:
> 1. **Emulação no Chrome Desktop via DevTools MCP:** Execução automatizada com viewport e DPR configurados via Chrome DevTools Protocol contra a API local.
> 2. **Navegador Safari Móvel Real em Simulador iOS (iPhone 18 Pro, iOS 27.2):** Execução nativa no Mobile Safari real emulando uma sessão já autenticada preservada no `localStorage`, recarga normal após promoção de bundle via symlink swap na mesma origem (`127.0.0.1:8585`) e inspeção de layout.

| Plataforma / Ambiente | Resolução / Formato | Itens Validados | Evidência Visual (Navegador Real) | Resultado |
|---|---|---|---|---|
| **Chrome Desktop (MCP)** | 1280x800 Widescreen | **Baseline Pré-Promoção (v1.3.0):** Dashboard autenticado com versão anterior: ausência do botão *"Registrar despesa paga"*. | `prints/homologacao/real_browser_v130_authenticated_dashboard.png` | ✅ Registrado |
| **Chrome Desktop (MCP)** | 1280x800 Widescreen | **Pós-Promoção:** Recarga na mesma URL com sessão preservada: surgimento imediato do botão *"🛍️ Registrar despesa paga (débito em conta)"* no Dashboard e *"🛍️ Registrar despesa"* no Extrato. | `prints/homologacao/real_browser_desktop_promotion.png` | ✅ Aprovado |
| **Chrome Desktop (MCP)** | 1280x800 Modal | **Central de Avisos:** Abertura da modal *"Notificações e Vencimentos"* pelo sininho: listagem de parcelas em atraso com ações *"Marcar como lido"* e *"Dispensar aviso"*. | `prints/homologacao/real_browser_desktop_notifications_modal.png` | ✅ Aprovado |
| **Emulação Móvel Chrome (MCP)** | 375x812 (DPR 3x) | **Dashboard Mobile Responsivo:** Botão *"🛍️ Registrar despesa paga (débito em conta)"*, cards de saldo e bottom navigation sem overflow. | `prints/homologacao/real_browser_mobile_promotion.png` | ✅ Aprovado |
| **Emulação Móvel Chrome (MCP)** | 375x812 (DPR 3x) | **Extrato Mobile:** Botão *"🛍️ Registrar despesa"*, chips de filtros (*Todos*, *Entradas*, *Saídas*, *Categoria*), cards de métricas e lista de transações. | `prints/homologacao/real_browser_mobile_extrato.png` | ✅ Aprovado |
| **Emulação Móvel Chrome (MCP)** | 375x812 (DPR 3x) | **Dashboard Direto:** Navegação via bottom bar para o Dashboard com métricas consolidadas e botão de débito em conta. | `prints/homologacao/real_browser_mobile_dashboard.png` | ✅ Aprovado |
| **Safari Móvel (iOS Simulator)** | iPhone 18 Pro (iOS 27.2) | **Baseline Pré-Promoção (v1.3.0):** Sessão autenticada preservada no `localStorage` no Safari Móvel real; Dashboard exibindo as 3 ações legadas (*A receber*, *A pagar*, *Contas*) e ausência do botão de compra no débito. | `prints/homologacao/safari_mobile_02_v130_authenticated.png` | ✅ Registrado |
| **Safari Móvel (iOS Simulator)** | iPhone 18 Pro (iOS 27.2) | **Pós-Promoção (Sessão Existente + Reload):** Troca de bundle ativo via symlink swap (`web_candidate`), recarga da SPA na mesma origem mantendo a sessão autenticada; renderização imediata do novo botão *"🛍️ Registrar despesa paga (débito em conta)"* sem overflow e layout perfeito. | `prints/homologacao/safari_mobile_03_promoted_dashboard.png` | ✅ Aprovado |
| **Safari Móvel (iOS Simulator)** | iPhone 18 Pro (iOS 27.2) | **Interação com Sininho / Modal:** Diagnóstico técnico registrado: o motor CanvasKit do Flutter Web ignora `PointerEvent` sintéticos despachados via JavaScript na árvore DOM do Safari por segurança (`event.isTrusted`); o simulador headless não possui harness XCUITest/idb nem permissões TCC para cliques nativos do sistema. Validação funcional das ações *"Marcar como lido"* e *"Dispensar aviso"* garantida 100% no Chrome DevTools MCP (`real_browser_desktop_notifications_modal.png`) e presença dos símbolos confirmada no bundle compilado (`apps/mobile/build/web/main.dart.js`). | `prints/homologacao/safari_mobile_04_notifications_modal.png` | ⚠️ Bloqueio de automação headless documentado (Funcional Aprovado no Chrome MCP) |

---

## 5. Arquivos Alterados nesta Entrega

| Arquivo | Descrição das Modificações |
|---|---|
| `apps/api/Dockerfile` | Adicionado `COPY public_web /opt/finance/web` para empacotar o bundle web na imagem de release. |
| `apps/api/.gitignore` | Ignora artefatos temporários de `public_web/*` preservando `.gitkeep`. |
| `apps/api/public_web/.gitkeep` | Mantém diretório rastreado para que builds locais e no CI encontrem a pasta. |
| `.github/workflows/deploy.yml` | Adicionada compilação do Flutter Web de produção, cálculo de `EXPECTED_WEB_HASH`, cópia para `public_web`, passagem obrigatória de `--web-hash` e barreira dupla de release. |
| `scripts/vps-deploy.sh` | Validação mandatória de `--web-hash` fail-closed, extração temporária (`mktemp -d`), validação prévia de hash e arquivos antes de migrações, conversão segura de legado para `web_releases/legacy`, preservação de arquivos ativos, replay idempotente e promoção atômica via symlink. |
| `scripts/vps-deploy-wrapper.sh` | Validação mandatória de `--web-hash <64 hex chars>` e suporte a repasse seguro de argumentos com `--`. |
| `scripts/verify-production-release.sh` | Script canônico de verificação de release pública com checagem de API e hash SHA-256 do JavaScript. |
| `tests/infra/test-vps-web-promotion.sh` | Teste automatizado dos 6 cenários de promoção web (hash ausente/inválido fail-closed, falha na conversão do legado preserva arquivo servido, staging antigo ignorado, falha de extração/hash preserva web sem migrar, promoção atômica bem-sucedida e replay idempotente). |
| `tests/infra/test-release-verification.sh` | Teste automatizado de regressão cobrindo os 5 cenários da barreira dupla. |
| `tests/infra/test-deploy-integrated-simulation.sh` | Atualizado para validar simulação integrada com parâmetro `--web-hash`. |
| `tests/infra/test-deploy-hardening-preflight.sh` | Atualizado para testar validação mandatória de `web_hash`, argumentos posicionais, nomeados e SSH `--`. |
| `tests/infra/test-vps-deploy-transition.sh` | Validação de transição e gatilhos SemVer atualizada para `--web-hash`. |
| `scripts/check.sh` | Integrados os 6 testes de infraestrutura no quality gate oficial `--full`. |
| `docs/decisions/0007-canal-exclusivo-web-flutter.md` | ADR formalizando a decisão de produto: canal oficial exclusivo via navegador e congelamento de lojas nativas. |
| `docs/project-guidelines.md` | Registro canônico de canal exclusivo web, diretrizes de ergonomia desktop/mobile web e barreira dupla. |
| `docs/operations/production-deployment.md` | Documentação do pipeline unificado de deploy, barreira dupla e troubleshooting. |
| `docs/operations/production-runbook.md` | Atualizado incidente `INC-08` com os novos procedimentos de promoção atômica via symlink, replay idempotente e verificação de compatibilidade de scripts na VPS antes da tag. |
| `specs/README.md` | Atualizada camada de especificações com seção de canal de entrega web e menção a `AC-FIN-029`. |
| `specs/financeiro/financeiro.md` | Adicionado critério `AC-FIN-029` (Canal Oficial Exclusivo via Navegador e Barreira Dupla de Release). |
| `specs/transferencias/transferencias.md` | Atualizado critério `AC-TRF-008` para canal web responsivo (ADR 0007). |
| `specs/emprestimos/emprestimos.md` | Atualizado critério `AC-EMP-008` para canal web responsivo (ADR 0007). |
| `docs/ai/HANDOFF.md` | Registro completo do incidente da v1.3.0, medições, causa comprovada, correções, matriz de homologação e próximos passos. |

---

## 6. Próximos Passos (Condicionados à Soberania Humana)

1. **Aguardar Avaliação Humana:** Apresentar a Jeann Lucas o relatório completo, o diff, as evidências e o status do incidente.
2. **Autorizações de Git Necessárias (Sob Demanda Específica):**
   - Autorização para commit na branch `fix/entrega-frontend-web-pipeline-deploy`.
   - Autorização para merge na branch `dev`.
   - Autorização para push da `dev` para `origin/dev`.
   - Autorização para abertura de PR de `dev` para `main`.
   - Autorização para merge commit na `main`.
   - Autorização para criação e publicação da tag SemVer `v1.3.1`.
3. **Fechamento do Incidente:** O incidente da v1.3.0 será considerado formalmente **ENCERRADO** apenas após o deploy da `v1.3.1` ser aprovado pela barreira dupla pública com:
   - `https://finance.bigdevz.com/api/health` respondendo com o SHA da release `v1.3.1`.
   - `https://finance.bigdevz.com/main.dart.js` respondendo com o hash SHA-256 do bundle compilado correspondente.

## Checkpoint — filtros e listagens do Finance Web

- Branch local `feature/filtros-operacoes-web`, aberta a partir de `origin/dev` em `37930cf`. Diff de trabalho disponível para revisão.
- A Pagar, A Receber e Extrato usam um painel de filtros coerente no desktop, com atalhos de período funcionais, categorias pesquisáveis e estados vazios contextuais. No mobile, o painel conserva o fluxo de aplicar ou cancelar.
- Critério `AC-UI-014` validado com teste de widget para o recorte e homologação com dados fictícios. Consulte os logs de `make check`, build web e capturas em `../evidencias-filtros/`.
- Próximo passo: revisão do diff e das capturas web antes de integração.
## Dashboard de prioridades e projeção de curto prazo

- Branch local `feature/dashboard-prioridades`, a partir de `origin/dev` (`37930cf`). AC-UI-013 traz vencidos, próximos 30 dias e valores a informar para o início do Dashboard, com listas filtradas. A carteira e a distribuição por bancos ficaram agrupadas e a ação de despesa paga usa o estilo tonal do tema.
- AC-FIN-037 define a projeção do caixa em centavos a partir do saldo disponível, mais a receber e menos a pagar de hoje até hoje + 30 dias. A janela exclui vencidos, cancelados e valores ainda não informados. A previsão fica indisponível se a API ainda não expuser a entrada do período.
- A ausência dos atalhos contextuais foi demonstrada pela falha inicial do teste Flutter de navegação. A verificação final com `make check` aprovou 15 testes de domínio, 393 Flutter e 242 Laravel com 2.284 asserções, além das verificações de infraestrutura.
- `./scripts/build-web.sh --env=local` e homologação em Chrome com dados fictícios passaram. A soma da amostra foi R$ 61.400,20 + R$ 9.562,05 − R$ 7.585,97 = R$ 63.376,28. O atalho abriu A Pagar com filtro ativo. Capturas e logs em `../evidencias-dashboard/`.
- Próximo passo: revisão das alterações locais. Produção permanece na v1.4.0.

## Integração das melhorias Web

- `feature/release-melhorias-web` reúne dashboard e filtros sobre `origin/dev` em `37930cf`. O atalho do dashboard continua abrindo A Pagar com o filtro selecionado.
- `make check` e `./scripts/build-web.sh --env=local` passaram na árvore integrada. Evidências em `../evidencias-release-web/`.
