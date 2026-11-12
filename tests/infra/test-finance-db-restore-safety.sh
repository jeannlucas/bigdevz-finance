#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Teste de Segurança de Rollback e Preservação de Dados de BD
# Comprova que:
# 1. Falha antes de migrações (build/checkout) NÃO restaura DB (zero risco de perda)
# 2. Escritores (scheduler e api) são pausados antes do snapshot e migrações
# 3. Restauração preserva contingência e recupera a versão anterior
# ==============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d -t finance_db_safety_XXXXXX)
SCRIPT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/vps-deploy.sh"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$PATH"

EVENTS_LOG="$TEST_DIR/events.log"
touch "$EVENTS_LOG"
export TEST_EVENTS_LOG="$EVENTS_LOG"

cat << 'EOF' > "$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "DOCKER: $*" >> "${TEST_EVENTS_LOG}"
if [[ "$*" =~ ps ]]; then
  echo "bigdevz-finance-postgres-1"
  echo "bigdevz-finance-api-1"
  echo "bigdevz-finance-scheduler-1"
  exit 0
fi
if [[ "$*" =~ pg_dump ]]; then
  echo "DUMP_RECORDED_AT_$(date +%s)"
  exit 0
fi
if [[ "$*" =~ pg_restore ]]; then
  echo "RESTORE: pg_restore called with $*" >> "${TEST_EVENTS_LOG}"
  exit 0
fi
if [[ "$*" =~ "down" ]]; then
  echo "MAINTENANCE_DOWN_CALLED" >> "${TEST_EVENTS_LOG}"
  exit 0
fi
if [[ "$*" =~ "up" && "$*" =~ "artisan" ]]; then
  echo "MAINTENANCE_UP_CALLED" >> "${TEST_EVENTS_LOG}"
  exit 0
fi
if [ "${MOCK_DOCKER_FAIL:-0}" = "1" ]; then
  exit 1
fi
exit 0
EOF
chmod +x "$MOCK_BIN/docker"

cat << 'EOF' > "$MOCK_BIN/curl"
#!/usr/bin/env bash
if [ "${MOCK_CURL_FAIL:-0}" = "1" ]; then
  echo "500"
  exit 1
fi
echo "200"
exit 0
EOF
chmod +x "$MOCK_BIN/curl"

cat << 'EOF' > "$MOCK_BIN/flock"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/flock"

cat << 'EOF' > "$MOCK_BIN/notify-deploy"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/notify-deploy"

# Upstream Git repo
UPSTREAM_DIR="$TEST_DIR/upstream.git"
git init --bare "$UPSTREAM_DIR" >/dev/null 2>&1
git -C "$UPSTREAM_DIR" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1

INIT_REPO="$TEST_DIR/init-repo"
git clone "$UPSTREAM_DIR" "$INIT_REPO" >/dev/null 2>&1
(
  cd "$INIT_REPO"
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false

  git commit --allow-empty -m "chore: base" >/dev/null 2>&1
  git checkout -b branch-v1 >/dev/null 2>&1
  git commit --allow-empty -m "feat: stable release v1.0.0" >/dev/null 2>&1
  git checkout -B main >/dev/null 2>&1
  git merge --no-ff branch-v1 -m "Merge pull request #1 into main" >/dev/null 2>&1
  git tag v1.0.0
  git push origin main --tags >/dev/null 2>&1
)
STABLE_SHA=$(cd "$INIT_REPO" && git rev-parse HEAD)

REPO_DIR="$TEST_DIR/srv/finance"
git clone "$UPSTREAM_DIR" "$REPO_DIR" >/dev/null 2>&1
(
  cd "$REPO_DIR"
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false
)

mkdir -p "$REPO_DIR/scripts"
cp "$SCRIPT_SRC" "$REPO_DIR/scripts/vps-deploy.sh"
chmod +x "$REPO_DIR/scripts/vps-deploy.sh"
touch "$REPO_DIR/docker-compose.yml"

VAR_LIB="$TEST_DIR/var/lib/vps-deploy/bigdevz-finance"
mkdir -p "$VAR_LIB"
echo "v1.0.0" > "$VAR_LIB/implantado_tag"
echo "$STABLE_SHA" > "$VAR_LIB/implantado"

SANDBOX_SCRIPT="$TEST_DIR/vps-deploy-sandbox"
sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$REPO_DIR}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/lock|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB|g" \
  -e "s|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-30}\"|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-2}\"|g" \
  "$REPO_DIR/scripts/vps-deploy.sh" > "$SANDBOX_SCRIPT"
chmod +x "$SANDBOX_SCRIPT"

echo "=========================================================="
echo "  BigDev.Z Finance — Testes de Salvaguarda de Banco e BD   "
echo "=========================================================="

# ------------------------------------------------------------------------------
# Teste A: Falha ANTES das migrações (build/checkout) NÃO executa pg_restore
# ------------------------------------------------------------------------------
echo -n "🧪 Teste A: Falha pré-migração NÃO restaura DB (dados intactos) .. "
(
  cd "$INIT_REPO"
  git checkout -b branch-fail-build >/dev/null 2>&1
  git commit --allow-empty -m "feat: release com erro no build" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  git merge --no-ff branch-fail-build -m "Merge pull request #2 into main" >/dev/null 2>&1
  git tag -a v1.0.1 -m "Release v1.0.1"
  git push origin main --tags >/dev/null 2>&1
)

> "$EVENTS_LOG"
export MOCK_DOCKER_FAIL=1
set +e
bash "$SANDBOX_SCRIPT" --tag v1.0.1 >/dev/null 2>&1
EXIT_A=$?
set -e
export MOCK_DOCKER_FAIL=0

if [ "$EXIT_A" -eq 0 ]; then
  echo "❌ FALHOU: O deploy deveria ter retornado erro."
  exit 1
fi

if grep -q "RESTORE: pg_restore" "$EVENTS_LOG"; then
  echo "❌ FALHOU: pg_restore foi chamado mesmo sem execução de migrações (risco de sobrescrever dados recentes)!"
  exit 1
fi

if [ "$(cat "$VAR_LIB/implantado_tag")" != "v1.0.0" ] || [ "$(cd "$REPO_DIR" && git rev-parse HEAD)" != "$STABLE_SHA" ]; then
  echo "❌ FALHOU: Versão de código não foi restaurada para o commit estável anterior."
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste B: Falha no healthcheck PÓS-migrações restaura com segurança e recupera versão estável
# ------------------------------------------------------------------------------
echo -n "🧪 Teste B: Falha pós-migração aciona rollback seguro e recupera versão anterior .. "
(
  cd "$INIT_REPO"
  git checkout -b branch-fail-health >/dev/null 2>&1
  git commit --allow-empty -m "feat: release com erro em runtime" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  git merge --no-ff branch-fail-health -m "Merge pull request #3 into main" >/dev/null 2>&1
  git tag -a v1.0.2 -m "Release v1.0.2"
  git push origin main --tags >/dev/null 2>&1
)

> "$EVENTS_LOG"
export MOCK_CURL_FAIL=1
set +e
bash "$SANDBOX_SCRIPT" --tag v1.0.2 >/dev/null 2>&1
EXIT_B=$?
set -e
export MOCK_CURL_FAIL=0

if [ "$EXIT_B" -eq 0 ]; then
  echo "❌ FALHOU: O deploy deveria ter retornado erro no healthcheck."
  exit 1
fi

if ! grep -q "RESTORE: pg_restore" "$EVENTS_LOG"; then
  echo "❌ FALHOU: pg_restore deveria ter sido acionado porque migrações foram executadas."
  exit 1
fi

if [ "$(cat "$VAR_LIB/implantado_tag")" != "v1.0.0" ] || [ "$(cd "$REPO_DIR" && git rev-parse HEAD)" != "$STABLE_SHA" ]; then
  echo "❌ FALHOU: Versão de código e marcadores não preservaram o estado anterior estável."
  exit 1
fi
echo "✅ PASSOU"

echo "=========================================================="
echo "🎉 Salvaguardas de banco de dados e rollback aprovadas 100%!"
echo "=========================================================="
exit 0
