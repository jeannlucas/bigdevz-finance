#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Simulação Integrada de Produção (End-to-End)
# Topologia equivalente à VPS (sem tocar em produção e sem dados reais):
# - Estrutura /srv/finance completa em sandbox temporário
# - Simulação de PostgreSQL, API Laravel e Caddy para Web
# - Validação de schema, assets, marcadores e trava em 3 fases:
#   Fase 1: Deploy bem-sucedido com promoção de web_staging -> web
#   Fase 2: Deploy com falha de healthcheck -> Fail-closed, trava e rollback
#   Fase 3: Recuperação controlada e validação de consistência final
# ==============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d -t finance_integrated_sim_XXXXXX)
export TEST_DIR
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
DEPLOY_SRC="$SCRIPTS_DIR/vps-deploy.sh"
ROLLBACK_SRC="$SCRIPTS_DIR/rollback-production.sh"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "=========================================================="
echo "  BigDev.Z Finance — Simulação Integrada de Produção       "
echo "=========================================================="

# 1. Configurar Mock Binaries (Docker, curl, flock, notify)
MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$PATH"

EVENTS_LOG="$TEST_DIR/events.log"
touch "$EVENTS_LOG"
export TEST_EVENTS_LOG="$EVENTS_LOG"

cat << 'EOF' > "$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "DOCKER: $*" >> "${TEST_EVENTS_LOG}"
if [[ "$*" =~ pg_dump ]]; then
  echo "INTEGRATED_SIM_DB_SNAPSHOT_DATA"
  exit 0
fi
if [[ "$*" =~ pg_restore ]]; then
  exit 0
fi
if [[ "$1" == "inspect" ]]; then
  exit 0
fi
if [[ "$1" == "create" ]]; then
  echo "mock_cid_sim_123"
  exit 0
fi
if [[ "$1" == "cp" ]]; then
  dest="${@: -1}"
  mkdir -p "$dest"
  if [ -f "$TEST_DIR/mock_web_content.txt" ]; then
    cat "$TEST_DIR/mock_web_content.txt" > "$dest/index.html"
  else
    echo "ASSETS_V1_2_0" > "$dest/index.html"
  fi
  echo "console.log('main');" > "$dest/main.dart.js"
  echo "console.log('bootstrap');" > "$dest/flutter_bootstrap.js"
  exit 0
fi
if [[ "$1" == "pull" ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/docker"

cat << 'EOF' > "$MOCK_BIN/curl"
#!/usr/bin/env bash
if [ "${MOCK_CURL_STATUS:-200}" = "200" ]; then
  echo "200"
  exit 0
else
  echo "500"
  exit 1
fi
EOF
chmod +x "$MOCK_BIN/curl"

cat << 'EOF' > "$MOCK_BIN/flock"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/flock"

# 2. Configurar Repositório Git Central (simulando origin/main)
UPSTREAM="$TEST_DIR/upstream.git"
git init --bare "$UPSTREAM" >/dev/null
git -C "$UPSTREAM" symbolic-ref HEAD refs/heads/main

INIT_REPO="$TEST_DIR/init_repo"
git clone "$UPSTREAM" "$INIT_REPO" >/dev/null 2>&1
(
  cd "$INIT_REPO"
  git config user.name "Jeann Lucas"
  git config user.email "jeann@bigdevz.com"
  git config commit.gpgsign false

  # Commit inicial
  git commit --allow-empty -m "chore: base" -q >/dev/null 2>&1
  git checkout -b feature-v100 -q >/dev/null 2>&1
  git commit --allow-empty -m "feat: release v1.0.0" -q >/dev/null 2>&1
  git checkout -B main -q >/dev/null 2>&1
  git merge --no-ff feature-v100 -m "Merge pull request #1 into main" -q >/dev/null 2>&1
  git tag -a "v1.0.0" -m "v1.0.0"
  git push origin main --tags -q >/dev/null 2>&1

  # Commit v1.2.0
  git checkout -b feature-v120 -q >/dev/null 2>&1
  git commit --allow-empty -m "feat: release v1.2.0" -q >/dev/null 2>&1
  git checkout main -q >/dev/null 2>&1
  git merge --no-ff feature-v120 -m "Merge pull request #2 into main" -q >/dev/null 2>&1
  git tag -a "v1.2.0" -m "v1.2.0"
  git push origin main --tags -q >/dev/null 2>&1

  # Commit v1.2.1
  git checkout -b feature-v121 -q >/dev/null 2>&1
  git commit --allow-empty -m "feat: release v1.2.1" -q >/dev/null 2>&1
  git checkout main -q >/dev/null 2>&1
  git merge --no-ff feature-v121 -m "Merge pull request #3 into main" -q >/dev/null 2>&1
  git tag -a "v1.2.1" -m "v1.2.1"
  git push origin main --tags -q >/dev/null 2>&1
)

SHA_V100=$(cd "$INIT_REPO" && git rev-parse "refs/tags/v1.0.0^{commit}")
SHA_V120=$(cd "$INIT_REPO" && git rev-parse "refs/tags/v1.2.0^{commit}")
SHA_V121=$(cd "$INIT_REPO" && git rev-parse "refs/tags/v1.2.1^{commit}")

# 3. Configurar Target Sandbox (/srv/finance)
TARGET_FINANCE="$TEST_DIR/srv/finance"
git clone "$UPSTREAM" "$TARGET_FINANCE" >/dev/null 2>&1
(
  cd "$TARGET_FINANCE"
  git config user.name "Deployer"
  git config user.email "deployer@bigdevz.com"
  git config commit.gpgsign false
  git reset --hard "$SHA_V100" -q
)

touch "$TARGET_FINANCE/docker-compose.production.yml"
touch "$TARGET_FINANCE/.env.production"
mkdir -p "$TARGET_FINANCE/web"
echo "ASSETS_V1_0_0" > "$TARGET_FINANCE/web/index.html"

VAR_LIB="$TEST_DIR/var/lib/vps-deploy/finance-prod"
mkdir -p "$VAR_LIB"
echo "v1.0.0" > "$VAR_LIB/implantado_tag"
echo "$SHA_V100" > "$VAR_LIB/implantado"
echo "ghcr.io/jeannlucas/bigdevz-finance-api@sha256:1111111111111111111111111111111111111111111111111111111111111111" > "$VAR_LIB/implantado_digest"

SANDBOX_DEPLOY="$TEST_DIR/sim-vps-deploy.sh"
sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$TARGET_FINANCE}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/sim_lock|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB|g" \
  -e "s|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-30}\"|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-2}\"|g" \
  "$DEPLOY_SRC" > "$SANDBOX_DEPLOY"
chmod +x "$SANDBOX_DEPLOY"

DIGEST_V120="ghcr.io/jeannlucas/bigdevz-finance-api@sha256:00dcfda38be164573da5966246aa5792b79c8dc10caa5753b77a2041e5010c24"
DIGEST_V121="ghcr.io/jeannlucas/bigdevz-finance-api@sha256:2222222222222222222222222222222222222222222222222222222222222222"

# ------------------------------------------------------------------------------
# FASE 1: Deploy bem-sucedido da release v1.2.0 com promoção web coordenada
# ------------------------------------------------------------------------------
echo -n "🧪 Fase 1: Simulação de deploy completo e bem-sucedido (v1.2.0) .. "

# Preparar staging web com versão v1.2.0
echo "ASSETS_V1_2_0" > "$TEST_DIR/mock_web_content.txt"
mkdir -p "$TARGET_FINANCE/web_staging"
echo "ASSETS_V1_2_0" > "$TARGET_FINANCE/web_staging/index.html"

> "$EVENTS_LOG"
export MOCK_CURL_STATUS=200
VALID_WEB_HASH="ca7dc00a8cc0ab0d105d2ae2bc85220d70ad590072169071248dd0538668c9bf"
bash "$SANDBOX_DEPLOY" --tag "v1.2.0" --digest "$DIGEST_V120" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1

# Conferir marcadores
if [ "$(cat "$VAR_LIB/implantado_tag")" != "v1.2.0" ]; then
  echo "❌ FALHOU: implantado_tag não é v1.2.0"
  exit 1
fi
if [ "$(cat "$VAR_LIB/implantado")" != "$SHA_V120" ]; then
  echo "❌ FALHOU: implantado SHA não corresponde a v1.2.0"
  exit 1
fi
if [ "$(cat "$VAR_LIB/implantado_digest")" != "$DIGEST_V120" ]; then
  echo "❌ FALHOU: implantado_digest incorreto"
  exit 1
fi

# Conferir promoção web
if [ ! -f "$TARGET_FINANCE/web/index.html" ] || [ "$(cat "$TARGET_FINANCE/web/index.html")" != "ASSETS_V1_2_0" ]; then
  echo "❌ FALHOU: Assets web v1.2.0 não foram promovidos"
  exit 1
fi
if [ -d "$TARGET_FINANCE/web_staging" ]; then
  echo "❌ FALHOU: web_staging não foi removido após promoção"
  exit 1
fi

# Conferir trava livre
if [ -e "$VAR_LIB/recuperacao_pendente" ]; then
  echo "❌ FALHOU: recuperacao_pendente não deveria existir após sucesso"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# FASE 2: Deploy com falha de healthcheck na v1.2.1 -> Fail-Closed e Trava Ativa
# ------------------------------------------------------------------------------
echo -n "🧪 Fase 2: Simulação de deploy com falha de healthcheck (v1.2.1) .. "

# Preparar staging web v1.2.1
echo "ASSETS_V1_2_1_QUEBRADA" > "$TEST_DIR/mock_web_content.txt"
mkdir -p "$TARGET_FINANCE/web_staging"
echo "ASSETS_V1_2_1_QUEBRADA" > "$TARGET_FINANCE/web_staging/index.html"

# Simular healthcheck falhando (HTTP 500)
export MOCK_CURL_STATUS=500
set +e
bash "$SANDBOX_DEPLOY" --tag "v1.2.1" --digest "$DIGEST_V121" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1
SIM_FAIL_EXIT=$?
set -e
export MOCK_CURL_STATUS=200

if [ "$SIM_FAIL_EXIT" -eq 0 ]; then
  echo "❌ FALHOU: Deploy deveria ter falhado com healthcheck 500"
  exit 1
fi

# Conferir preservação dos marcadores na versão v1.2.0 estável
if [ "$(cat "$VAR_LIB/implantado_tag")" != "v1.2.0" ]; then
  echo "❌ FALHOU: implantado_tag foi modificado após falha de healthcheck"
  exit 1
fi
if [ "$(cat "$VAR_LIB/implantado")" != "$SHA_V120" ]; then
  echo "❌ FALHOU: commit implantado foi modificado após falha de healthcheck"
  exit 1
fi

# Conferir que a web NÃO foi promovida para a versão quebrada
if [ "$(cat "$TARGET_FINANCE/web/index.html")" != "ASSETS_V1_2_0" ]; then
  echo "❌ FALHOU: Frontend web foi corrompido/promovido apesar da falha na API"
  exit 1
fi

# Conferir criação compulsória da trava de recuperação com snapshot
if [ ! -s "$VAR_LIB/recuperacao_pendente" ]; then
  echo "❌ FALHOU: Trava recuperacao_pendente ausente ou vazia"
  exit 1
fi

# Conferir bloqueio fail-closed de novos deploys
set +e
bash "$SANDBOX_DEPLOY" --tag "v1.2.1" --digest "$DIGEST_V121" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1
BLOCKED_EXIT=$?
set -e
if [ "$BLOCKED_EXIT" -eq 0 ]; then
  echo "❌ FALHOU: Novo deploy deveria ter sido bloqueado pela trava"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# FASE 3: Recuperação controlada e validação de sucesso subsequente
# ------------------------------------------------------------------------------
echo -n "🧪 Fase 3: Recuperação controlada, liberação de trava e deploy corrigido .. "

# Simulação de saneamento operacional: intervenção humana remove a trava após restabelecer banco
rm -f "$VAR_LIB/recuperacao_pendente"
rm -rf "$TARGET_FINANCE/web_staging"

# Preparar novo staging web corrigido para v1.2.1
echo "ASSETS_V1_2_1_CORRIGIDA" > "$TEST_DIR/mock_web_content.txt"
mkdir -p "$TARGET_FINANCE/web_staging"
echo "ASSETS_V1_2_1_CORRIGIDA" > "$TARGET_FINANCE/web_staging/index.html"

# Executar novo deploy v1.2.1 com saúde aprovada
export MOCK_CURL_STATUS=200
bash "$SANDBOX_DEPLOY" --tag "v1.2.1" --digest "$DIGEST_V121" --web-hash "$VALID_WEB_HASH" >/dev/null 2>&1

# Conferir marcadores atualizados para v1.2.1
if [ "$(cat "$VAR_LIB/implantado_tag")" != "v1.2.1" ]; then
  echo "❌ FALHOU: implantado_tag não atualizado para v1.2.1"
  exit 1
fi
if [ "$(cat "$VAR_LIB/implantado")" != "$SHA_V121" ]; then
  echo "❌ FALHOU: commit implantado não atualizado para v1.2.1"
  exit 1
fi
if [ "$(cat "$TARGET_FINANCE/web/index.html")" != "ASSETS_V1_2_1_CORRIGIDA" ]; then
  echo "❌ FALHOU: Web corrigida não foi promovida"
  exit 1
fi
if [ -e "$VAR_LIB/recuperacao_pendente" ]; then
  echo "❌ FALHOU: Trava residual encontrada"
  exit 1
fi
echo "✅ PASSOU"

echo "=========================================================="
echo "🎉 Simulação Integrada E2E aprovada com 100% de sucesso!"
echo "=========================================================="
exit 0
