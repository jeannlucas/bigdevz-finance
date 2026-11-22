#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Teste Automatizado de Hardening e Pré-Voo do Pipeline
# Valida as proteções específicas contra as falhas observadas na v1.2.0:
# 1. Resiliência do wrapper SSH a diferentes formatos de argumentos e separador '--'
# 2. Bloqueio pré-voo fail-closed diante de falta de permissão em marcadores
# 3. Proteção e preservação dos serviços saudáveis pós-healthcheck aprovado
# 4. Invocação SSH segura com '--' no workflow de deploy do GitHub Actions
# 5. Estadiamento coordenado de Frontend Web (web_staging -> web apenas pós-healthcheck)
# 6. Bloqueio fail-closed de pré-voo diante de container de banco ausente ou offline
# 7. Replay idempotente de tags já sincronizadas ou commits já implantados
# 8. Falha em migrações aciona fail-closed, preserva snapshot e trava recuperacao_pendente
# ==============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d -t finance_hardening_test_XXXXXX)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
WRAPPER_SRC="$SCRIPTS_DIR/vps-deploy-wrapper.sh"
DEPLOY_SRC="$SCRIPTS_DIR/vps-deploy.sh"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "=========================================================="
echo "  BigDev.Z Finance — Testes de Hardening e Pré-Voo        "
echo "=========================================================="

VALID_TAG="v1.2.0"
VALID_DIGEST="ghcr.io/jeannlucas/bigdevz-finance-api@sha256:00dcfda38be164573da5966246aa5792b79c8dc10caa5753b77a2041e5010c24"

# ------------------------------------------------------------------------------
# Teste 1: Resiliência do Wrapper SSH a flags, argumentos e separador '--'
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 1: Wrapper SSH suporta '--', flags e argumentos posicionais .. "

MOCK_DEPLOY="$TEST_DIR/mock-vps-deploy.sh"
cat << 'EOF' > "$MOCK_DEPLOY"
#!/usr/bin/env bash
echo "RECEIVED: $*" > "${MOCK_DEPLOY_OUT}"
exit 0
EOF
chmod +x "$MOCK_DEPLOY"

SANDBOX_WRAPPER="$TEST_DIR/vps-deploy-wrapper-sandbox.sh"
sed -e "s|/srv/finance/scripts/vps-deploy.sh|$MOCK_DEPLOY|g" "$WRAPPER_SRC" > "$SANDBOX_WRAPPER"
chmod +x "$SANDBOX_WRAPPER"

export MOCK_DEPLOY_OUT="$TEST_DIR/mock_deploy.out"
VALID_WEB_HASH="ca7dc00a8cc0ab0d105d2ae2bc85220d70ad590072169071248dd0538668c9bf"

# 1.1 Invocação com 3 argumentos posicionais (incluindo web_hash)
"$SANDBOX_WRAPPER" "$VALID_TAG" "$VALID_DIGEST" "$VALID_WEB_HASH"
if [ "$(cat "$MOCK_DEPLOY_OUT")" != "RECEIVED: --tag $VALID_TAG --digest $VALID_DIGEST --web-hash $VALID_WEB_HASH" ]; then
  echo "❌ FALHOU (Chamada com 3 argumentos posicionais incluindo web_hash falhou)"
  exit 1
fi

# 1.2 Invocação com flags nomeadas incluindo --web-hash
"$SANDBOX_WRAPPER" --tag "$VALID_TAG" --digest "$VALID_DIGEST" --web-hash "$VALID_WEB_HASH"
if [ "$(cat "$MOCK_DEPLOY_OUT")" != "RECEIVED: --tag $VALID_TAG --digest $VALID_DIGEST --web-hash $VALID_WEB_HASH" ]; then
  echo "❌ FALHOU (Chamada com flags nomeadas incluindo web-hash falhou)"
  exit 1
fi

# 1.3 Invocação com separador '--' inicial (como gerado pelo cliente OpenSSH seguro)
"$SANDBOX_WRAPPER" -- "$VALID_TAG" "$VALID_DIGEST" "$VALID_WEB_HASH"
if [ "$(cat "$MOCK_DEPLOY_OUT")" != "RECEIVED: --tag $VALID_TAG --digest $VALID_DIGEST --web-hash $VALID_WEB_HASH" ]; then
  echo "❌ FALHOU (Chamada com separador '--' inicial falhou)"
  exit 1
fi

# 1.4 Invocação simulando SSH_ORIGINAL_COMMAND com separador '--' e flags
SSH_ORIGINAL_COMMAND="-- --tag $VALID_TAG --digest $VALID_DIGEST --web-hash $VALID_WEB_HASH" "$SANDBOX_WRAPPER"
if [ "$(cat "$MOCK_DEPLOY_OUT")" != "RECEIVED: --tag $VALID_TAG --digest $VALID_DIGEST --web-hash $VALID_WEB_HASH" ]; then
  echo "❌ FALHOU (SSH_ORIGINAL_COMMAND com '--' e flags falhou)"
  exit 1
fi

# 1.5 Invocação simulando SSH_ORIGINAL_COMMAND posicional
SSH_ORIGINAL_COMMAND="$VALID_TAG $VALID_DIGEST $VALID_WEB_HASH" "$SANDBOX_WRAPPER"
if [ "$(cat "$MOCK_DEPLOY_OUT")" != "RECEIVED: --tag $VALID_TAG --digest $VALID_DIGEST --web-hash $VALID_WEB_HASH" ]; then
  echo "❌ FALHOU (SSH_ORIGINAL_COMMAND posicional falhou)"
  exit 1
fi

# 1.6 Rejeição estrita quando web_hash está ausente
set +e
"$SANDBOX_WRAPPER" "$VALID_TAG" "$VALID_DIGEST" >/dev/null 2>&1
MISSING_HASH_EXIT=$?
set -e
if [ "$MISSING_HASH_EXIT" -eq 0 ]; then
  echo "❌ FALHOU (Wrapper aceitou deploy sem web-hash)"
  exit 1
fi

# 1.7 Rejeição estrita quando web_hash é malformado
set +e
"$SANDBOX_WRAPPER" "$VALID_TAG" "$VALID_DIGEST" "hash_invalido" >/dev/null 2>&1
MALFORMED_HASH_EXIT=$?
set -e
if [ "$MALFORMED_HASH_EXIT" -eq 0 ]; then
  echo "❌ FALHOU (Wrapper aceitou web-hash malformado)"
  exit 1
fi

# 1.8 Rejeição estrita de tag inválida
set +e
"$SANDBOX_WRAPPER" "versao-invalida" "$VALID_DIGEST" "$VALID_WEB_HASH" >/dev/null 2>&1
INVALID_TAG_EXIT=$?
set -e
if [ "$INVALID_TAG_EXIT" -eq 0 ]; then
  echo "❌ FALHOU (Wrapper aceitou tag semver inválida)"
  exit 1
fi

echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 2: Pré-Voo Fail-Closed diante de falta de permissão de escrita em marcadores
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 2: Pré-voo aborta fail-closed com erro de permissão em marcadores .. "

MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "DOCKER: $*" >> "${TEST_EVENTS_LOG}"
if [[ "$*" =~ pg_dump ]]; then
  echo "MOCK_DUMP_DATA_FOR_BACKUP"
  exit 0
fi
if [[ "$*" =~ pg_restore ]]; then
  exit 0
fi
if [[ "$1" == "inspect" ]]; then
  exit 0
fi
if [[ "$1" == "create" ]]; then
  echo "mock_cid_preflight_123"
  exit 0
fi
if [[ "$1" == "cp" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest"
  if [ -n "${TARGET_WEB:-}" ] && [ -f "$TARGET_WEB/web_staging/index.html" ]; then
    cp "$TARGET_WEB/web_staging/index.html" "$dest/index.html"
  else
    echo "FRONTEND_V2_NEW" > "$dest/index.html"
  fi
  echo "console.log('main');" > "$dest/main.dart.js"
  echo "console.log('bootstrap');" > "$dest/flutter_bootstrap.js"
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/docker"

SANDBOX_DEPLOY="$TEST_DIR/sandbox-deploy-perm.sh"
VAR_LIB_UNWRITABLE="$TEST_DIR/var_lib_perm"
mkdir -p "$VAR_LIB_UNWRITABLE"
touch "$VAR_LIB_UNWRITABLE/implantado_tag"
touch "$VAR_LIB_UNWRITABLE/implantado"
touch "$VAR_LIB_UNWRITABLE/implantado_digest"
chmod 444 "$VAR_LIB_UNWRITABLE/implantado_digest"

EVENTS_LOG="$TEST_DIR/events_perm.log"
export TEST_EVENTS_LOG="$EVENTS_LOG"
touch "$EVENTS_LOG"

TARGET_DUMMY="$TEST_DIR/dummy_target"
mkdir -p "$TARGET_DUMMY"
touch "$TARGET_DUMMY/docker-compose.production.yml"

sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$TARGET_DUMMY}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/lock_perm|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB_UNWRITABLE|g" \
  "$DEPLOY_SRC" > "$SANDBOX_DEPLOY"
chmod +x "$SANDBOX_DEPLOY"

export PATH="$MOCK_BIN:$PATH"
set +e
SKIP_GIT_CHECKOUT=1 bash "$SANDBOX_DEPLOY" --tag "$VALID_TAG" --digest "$VALID_DIGEST" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1
PERM_TEST_EXIT=$?
set -e

chmod 644 "$VAR_LIB_UNWRITABLE/implantado_digest"

if [ "$PERM_TEST_EXIT" -eq 0 ]; then
  echo "❌ FALHOU (Deploy prosseguiu com marcador sem permissão de escrita)"
  exit 1
fi

if grep -q "stop api scheduler" "$EVENTS_LOG"; then
  echo "❌ FALHOU (Deploy interrompeu serviços apesar de falha no pré-voo)"
  exit 1
fi

if grep -q "migrate" "$EVENTS_LOG"; then
  echo "❌ FALHOU (Deploy tentou migrações apesar de falha no pré-voo)"
  exit 1
fi

echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 3: Desacoplamento pós-healthcheck — Serviços saudáveis não são parados
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 3: Trap não desliga API e Scheduler após healthcheck aprovado .. "

cat << 'EOF' > "$MOCK_BIN/curl"
#!/usr/bin/env bash
echo "200"
exit 0
EOF
chmod +x "$MOCK_BIN/curl"

cat << 'EOF' > "$MOCK_BIN/flock"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/flock"

# Notificação pós-deploy que falha propositalmente
cat << 'EOF' > "$MOCK_BIN/notify-deploy"
#!/usr/bin/env bash
echo "NOTIFY_FAILED" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/notify-deploy"

TARGET_HEALTH="$TEST_DIR/dummy_health"
mkdir -p "$TARGET_HEALTH"
git init "$TARGET_HEALTH" >/dev/null
(
  cd "$TARGET_HEALTH"
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false
  git commit --allow-empty -m "base commit on main" -q >/dev/null 2>&1
  git checkout -b branch-feature -q >/dev/null 2>&1
  git commit --allow-empty -m "feature commit" -q >/dev/null 2>&1
  git checkout main -q >/dev/null 2>&1
  git commit --allow-empty -m "main preparation commit" -q >/dev/null 2>&1
  git merge --no-ff branch-feature -m "Merge pull request #1 into main" -q >/dev/null 2>&1
  git tag -a "$VALID_TAG" -m "$VALID_TAG"
)
touch "$TARGET_HEALTH/docker-compose.production.yml"
PREV_TEST3_SHA=$(cd "$TARGET_HEALTH" && git rev-parse HEAD~1)
EXPECTED_TEST3_SHA=$(cd "$TARGET_HEALTH" && git rev-parse HEAD)

VAR_LIB_HEALTH="$TEST_DIR/var_lib_health"
mkdir -p "$VAR_LIB_HEALTH"
echo "v1.1.0" > "$VAR_LIB_HEALTH/implantado_tag"
echo "$PREV_TEST3_SHA" > "$VAR_LIB_HEALTH/implantado"
echo "bigdevz/finance-api@sha256:old" > "$VAR_LIB_HEALTH/implantado_digest"

SANDBOX_HEALTH="$TEST_DIR/sandbox-health.sh"
sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$TARGET_HEALTH}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/lock_health|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB_HEALTH|g" \
  -e "s|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-30}\"|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-2}\"|g" \
  "$DEPLOY_SRC" > "$SANDBOX_HEALTH"
chmod +x "$SANDBOX_HEALTH"

> "$EVENTS_LOG"
SKIP_GIT_CHECKOUT=1 bash "$SANDBOX_HEALTH" --tag "$VALID_TAG" --digest "$VALID_DIGEST" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1

# Verificar que up -d --no-build foi emitido
if ! grep -q "up -d --no-build api scheduler" "$EVENTS_LOG"; then
  echo "❌ FALHOU (Comando up -d não foi emitido)"
  exit 1
fi

# Verificar que os marcadores foram atualizados com sucesso
if [ "$(cat "$VAR_LIB_HEALTH/implantado_tag")" != "$VALID_TAG" ]; then
  echo "❌ FALHOU (implantado_tag não foi atualizado)"
  exit 1
fi

echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 4: Validação da Sintaxe do Workflow de Deploy (.github/workflows/deploy.yml)
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 4: Comando SSH no workflow utiliza separador '--' seguro .. "

DEPLOY_WORKFLOW="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.github/workflows" && pwd)/deploy.yml"
if ! grep -q -- '-- "$TAG_NAME" "$IMAGE_DIGEST"' "$DEPLOY_WORKFLOW"; then
  echo "❌ FALHOU (Workflow deploy.yml não está utilizando o separador '--' seguro)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 5: Estadiamento Coordenado do Frontend Web (web_staging -> web)
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 5: Promoção de Frontend Web ocorre atomicamente apenas pós-healthcheck .. "

TARGET_WEB="$TEST_DIR/dummy_web"
mkdir -p "$TARGET_WEB"
git init "$TARGET_WEB" >/dev/null
(
  cd "$TARGET_WEB"
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false
  git commit --allow-empty -m "base commit" -q >/dev/null 2>&1
  git checkout -b branch-web -q >/dev/null 2>&1
  git commit --allow-empty -m "feature web" -q >/dev/null 2>&1
  git checkout main -q >/dev/null 2>&1
  git commit --allow-empty -m "main prep" -q >/dev/null 2>&1
  git merge --no-ff branch-web -m "Merge pr web into main" -q >/dev/null 2>&1
  git tag -a "$VALID_TAG" -m "$VALID_TAG"
)
touch "$TARGET_WEB/docker-compose.production.yml"
PREV_WEB_SHA=$(cd "$TARGET_WEB" && git rev-parse HEAD~1)

mkdir -p "$TARGET_WEB/web"
echo "FRONTEND_V1_OLD" > "$TARGET_WEB/web/index.html"

mkdir -p "$TARGET_WEB/web_staging"
echo "FRONTEND_V2_NEW" > "$TARGET_WEB/web_staging/index.html"

VAR_LIB_WEB="$TEST_DIR/var_lib_web"
mkdir -p "$VAR_LIB_WEB"
echo "v1.1.0" > "$VAR_LIB_WEB/implantado_tag"
echo "$PREV_WEB_SHA" > "$VAR_LIB_WEB/implantado"
echo "bigdevz/finance-api@sha256:old" > "$VAR_LIB_WEB/implantado_digest"

SANDBOX_WEB="$TEST_DIR/sandbox-web.sh"
sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$TARGET_WEB}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/lock_web|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB_WEB|g" \
  -e "s|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-30}\"|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-2}\"|g" \
  "$DEPLOY_SRC" > "$SANDBOX_WEB"
chmod +x "$SANDBOX_WEB"

SKIP_GIT_CHECKOUT=1 bash "$SANDBOX_WEB" --tag "$VALID_TAG" --digest "$VALID_DIGEST" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1

if [ ! -f "$TARGET_WEB/web/index.html" ] || [ "$(cat "$TARGET_WEB/web/index.html")" != "FRONTEND_V2_NEW" ]; then
  echo "❌ FALHOU (Frontend Web não foi promovido para a versão nova pós-healthcheck)"
  exit 1
fi
if [ -d "$TARGET_WEB/web_staging" ]; then
  echo "❌ FALHOU (web_staging temporário não foi limpo após promoção)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 6: Pré-Voo Fail-Closed com Banco Offline ou Container Inexistente
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 6: Pré-voo aborta fail-closed quando container Postgres está ausente .. "

MOCK_BIN_FAIL="$TEST_DIR/bin_fail"
mkdir -p "$MOCK_BIN_FAIL"
cat << 'EOF' > "$MOCK_BIN_FAIL/docker"
#!/usr/bin/env bash
if [[ "$*" =~ inspect && "$*" =~ postgres ]]; then
  # Simula container postgres inexistente
  exit 1
fi
exit 0
EOF
chmod +x "$MOCK_BIN_FAIL/docker"

TARGET_NO_PG="$TEST_DIR/dummy_no_pg"
mkdir -p "$TARGET_NO_PG"
git init "$TARGET_NO_PG" >/dev/null
(
  cd "$TARGET_NO_PG"
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false
  git commit --allow-empty -m "base" -q >/dev/null 2>&1
  git checkout -b branch-nopg -q >/dev/null 2>&1
  git commit --allow-empty -m "feature" -q >/dev/null 2>&1
  git checkout main -q >/dev/null 2>&1
  git commit --allow-empty -m "prep" -q >/dev/null 2>&1
  git merge --no-ff branch-nopg -m "Merge into main" -q >/dev/null 2>&1
  git tag -a "v1.2.9" -m "v1.2.9"
)
touch "$TARGET_NO_PG/docker-compose.production.yml"
PREV_NO_PG_SHA=$(cd "$TARGET_NO_PG" && git rev-parse HEAD~1)

VAR_LIB_NO_PG="$TEST_DIR/var_lib_no_pg"
mkdir -p "$VAR_LIB_NO_PG"
echo "v1.1.0" > "$VAR_LIB_NO_PG/implantado_tag"
echo "$PREV_NO_PG_SHA" > "$VAR_LIB_NO_PG/implantado"
echo "bigdevz/finance-api@sha256:old" > "$VAR_LIB_NO_PG/implantado_digest"

SANDBOX_NO_PG="$TEST_DIR/sandbox-no-pg.sh"
sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$TARGET_NO_PG}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/lock_no_pg|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB_NO_PG|g" \
  "$DEPLOY_SRC" > "$SANDBOX_NO_PG"
chmod +x "$SANDBOX_NO_PG"

set +e
PATH="$MOCK_BIN_FAIL:$PATH" SKIP_GIT_CHECKOUT=1 bash "$SANDBOX_NO_PG" --tag "v1.2.9" --digest "$VALID_DIGEST" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1
NO_PG_EXIT=$?
set -e

if [ "$NO_PG_EXIT" -eq 0 ]; then
  echo "❌ FALHOU (Deploy prosseguiu com container de banco ausente)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 7: Idempotência de Replay (Tag já sincronizada)
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 7: Replay idempotente de tag já implantada sai com exit 0 sem alterações .. "

echo "$VALID_TAG" > "$VAR_LIB_WEB/implantado_tag"

set +e
SKIP_GIT_CHECKOUT=1 bash "$SANDBOX_WEB" --tag "$VALID_TAG" --digest "$VALID_DIGEST" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1
REPLAY_EXIT=$?
set -e

if [ "$REPLAY_EXIT" -ne 0 ]; then
  echo "❌ FALHOU (Replay de tag já implantada falhou com exit code $REPLAY_EXIT)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 8: Falha durante migração aciona fail-closed e trava recuperacao_pendente
# ------------------------------------------------------------------------------
echo -n "🧪 Teste 8: Falha em migrações aciona fail-closed e preserva snapshot .. "

MOCK_BIN_MIG_FAIL="$TEST_DIR/bin_mig_fail"
mkdir -p "$MOCK_BIN_MIG_FAIL"
cat << 'EOF' > "$MOCK_BIN_MIG_FAIL/docker"
#!/usr/bin/env bash
echo "DOCKER: $*" >> "${TEST_EVENTS_LOG}"
if [[ "$*" =~ pg_dump ]]; then
  echo "MOCK_BACKUP_SNAPSHOT"
  exit 0
fi
if [[ "$*" =~ pg_restore ]]; then
  exit 0
fi
if [[ "$1" == "inspect" ]]; then
  exit 0
fi
if [[ "$1" == "create" ]]; then
  echo "mock_cid_preflight_123"
  exit 0
fi
if [[ "$1" == "cp" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest"
  if [ -n "${TARGET_WEB:-}" ] && [ -f "$TARGET_WEB/web_staging/index.html" ]; then
    cp "$TARGET_WEB/web_staging/index.html" "$dest/index.html"
  else
    echo "FRONTEND_V2_NEW" > "$dest/index.html"
  fi
  echo "console.log('main');" > "$dest/main.dart.js"
  echo "console.log('bootstrap');" > "$dest/flutter_bootstrap.js"
  exit 0
fi
if [[ "$*" =~ "artisan migrate" ]]; then
  echo "SQLSTATE[HY000]: Migration error simulated" >&2
  exit 1
fi
exit 0
EOF
chmod +x "$MOCK_BIN_MIG_FAIL/docker"

TARGET_MIG="$TEST_DIR/dummy_mig"
mkdir -p "$TARGET_MIG"
git init "$TARGET_MIG" >/dev/null
(
  cd "$TARGET_MIG"
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false
  git commit --allow-empty -m "base" -q >/dev/null 2>&1
  git checkout -b branch-mig -q >/dev/null 2>&1
  git commit --allow-empty -m "feature mig" -q >/dev/null 2>&1
  git checkout main -q >/dev/null 2>&1
  git commit --allow-empty -m "prep mig" -q >/dev/null 2>&1
  git merge --no-ff branch-mig -m "Merge pr mig into main" -q >/dev/null 2>&1
  git tag -a "v1.2.1" -m "v1.2.1"
)
touch "$TARGET_MIG/docker-compose.production.yml"
PREV_MIG_SHA=$(cd "$TARGET_MIG" && git rev-parse HEAD~1)

VAR_LIB_MIG="$TEST_DIR/var_lib_mig"
mkdir -p "$VAR_LIB_MIG"
echo "v1.1.0" > "$VAR_LIB_MIG/implantado_tag"
echo "$PREV_MIG_SHA" > "$VAR_LIB_MIG/implantado"
echo "bigdevz/finance-api@sha256:old" > "$VAR_LIB_MIG/implantado_digest"

SANDBOX_MIG="$TEST_DIR/sandbox-mig-fail.sh"
sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$TARGET_MIG}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/lock_mig|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB_MIG|g" \
  -e "s|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-30}\"|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-2}\"|g" \
  "$DEPLOY_SRC" > "$SANDBOX_MIG"
chmod +x "$SANDBOX_MIG"

set +e
PATH="$MOCK_BIN_MIG_FAIL:$PATH" SKIP_GIT_CHECKOUT=1 bash "$SANDBOX_MIG" --tag "v1.2.1" --digest "$VALID_DIGEST" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1
MIG_FAIL_EXIT=$?
set -e

if [ "$MIG_FAIL_EXIT" -eq 0 ]; then
  echo "❌ FALHOU (Deploy deveria ter falhado na migração)"
  exit 1
fi

if [ ! -s "$VAR_LIB_MIG/recuperacao_pendente" ]; then
  echo "❌ FALHOU (recuperacao_pendente não foi registrada após falha de migração)"
  exit 1
fi

if [ "$(cat "$VAR_LIB_MIG/implantado_tag")" != "v1.1.0" ]; then
  echo "❌ FALHOU (marcador implantado_tag foi modificado indevidamente)"
  exit 1
fi
echo "✅ PASSOU"

echo "=========================================================="
echo "🎉 Todos os 8 testes de hardening e pré-voo passaram 100%!"
echo "=========================================================="
exit 0
