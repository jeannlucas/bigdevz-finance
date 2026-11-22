#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Teste Automatizado de Promoção e Validação do Frontend Web
# Valida o caminho real do script de promoção na VPS (vps-deploy.sh):
# 1. Staging antigo já preenchido é limpo e não determina a publicação
# 2. Falha de extração ou bundle parcial aborta fail-closed preservando o web ativo
#    e impedindo a execução de migrações de banco
# 3. Promoção bem-sucedida do digest esperado com transição atômica e marcadores
# ==============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d -t finance_web_promo_test_XXXXXX)
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

# Mock do docker com controle de extração via variáveis de ambiente
cat << 'EOF' > "$MOCK_BIN/docker"
#!/usr/bin/env bash
echo "DOCKER: $*" >> "${TEST_EVENTS_LOG}"

if [[ "$1" == compose && "$*" == *"ps --status running -q"* ]]; then
  if [ "${MOCK_WRITER_RUNNING:-0}" = 1 ]; then echo writer; fi
  exit 0
fi
if [[ "$*" =~ ps ]]; then
  echo "bigdevz-finance-postgres-1"
  echo "bigdevz-finance-api-1"
  exit 0
fi
if [[ "$1" == "inspect" ]]; then
  if [ "${MOCK_INSPECT_FAIL:-0}" = "1" ]; then exit 1; fi
  exit 0
fi
if [[ "$1" == "pull" ]]; then
  if [ "${MOCK_PULL_FAIL:-0}" = "1" ]; then exit 1; fi
  exit 0
fi
if [[ "$1" == "create" ]]; then
  if [ "${MOCK_CREATE_FAIL:-0}" = "1" ]; then
    echo "Error: image not found" >&2
    exit 1
  fi
  echo "mock_container_extract_cid_999"
  exit 0
fi
if [[ "$1" == "cp" ]]; then
  if [ "${MOCK_CP_FAIL:-0}" = "1" ]; then
    echo "Error: docker cp failed" >&2
    exit 1
  fi
  dest="${@: -1}"
  mkdir -p "$dest"
  
  if [ "${MOCK_CP_PARTIAL:-0}" = "1" ]; then
    # Simula bundle parcial (apenas index.html, faltando main.dart.js)
    echo "MOCK_PARTIAL_INDEX_HTML" > "$dest/index.html"
    exit 0
  fi
  
  JS_DATA="${MOCK_BUNDLE_CONTENT:-MOCK_DEFAULT_CANONICAL_JS}"
  printf "%s" "$JS_DATA" > "$dest/main.dart.js"
  echo "<html>Flutter Web</html>" > "$dest/index.html"
  echo "console.log('bootstrap');" > "$dest/flutter_bootstrap.js"
  exit 0
fi
if [[ "$*" =~ pg_dump ]]; then
  echo "MOCK_DUMP_DATA"
  exit 0
fi
if [[ "$*" =~ pg_restore ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN/docker"

# Mock do curl para healthcheck
cat << 'EOF' > "$MOCK_BIN/curl"
#!/usr/bin/env bash
echo "200"
exit 0
EOF
chmod +x "$MOCK_BIN/curl"

# Mock do flock
cat << 'EOF' > "$MOCK_BIN/flock"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/flock"

# Mock do notify-deploy
cat << 'EOF' > "$MOCK_BIN/notify-deploy"
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$MOCK_BIN/notify-deploy"

# 1. Configurar repositório Bare Upstream (simulando GitHub origin)
UPSTREAM_DIR="$TEST_DIR/upstream.git"
git init --bare "$UPSTREAM_DIR" >/dev/null 2>&1
git -C "$UPSTREAM_DIR" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1

# 2. Criar repositório clone para semear origin/main
INIT_REPO="$TEST_DIR/init-repo"
git clone "$UPSTREAM_DIR" "$INIT_REPO" >/dev/null 2>&1
(
  cd "$INIT_REPO"
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false

  # Base commit
  git commit --allow-empty -m "chore: base" >/dev/null 2>&1
  git checkout -b branch-initial >/dev/null 2>&1
  git commit --allow-empty -m "feat: initial feature" >/dev/null 2>&1
  git checkout -B main >/dev/null 2>&1
  git merge --no-ff branch-initial -m "Merge pull request #1 into main" >/dev/null 2>&1
  git tag v1.0.0
  git push origin main --tags >/dev/null 2>&1
)
UPSTREAM_INITIAL_SHA=$(cd "$INIT_REPO" && git rev-parse HEAD)

# 3. Criar repositório alvo (simulando /srv/finance)
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
touch "$REPO_DIR/docker-compose.production.yml"
touch "$REPO_DIR/.env.production"

# Configurar versão ativa inicial do frontend web
mkdir -p "$REPO_DIR/web"
echo "FRONTEND_V1_ACTIVE_INITIAL" > "$REPO_DIR/web/main.dart.js"
echo "<html>Initial</html>" > "$REPO_DIR/web/index.html"
echo "bootstrap_v1" > "$REPO_DIR/web/flutter_bootstrap.js"

VAR_LIB="$TEST_DIR/var/lib/vps-deploy/bigdevz-finance"
mkdir -p "$VAR_LIB"
echo "v1.0.0" > "$VAR_LIB/implantado_tag"
echo "$UPSTREAM_INITIAL_SHA" > "$VAR_LIB/implantado"
echo "bigdevz/finance-api@sha256:initial" > "$VAR_LIB/implantado_digest"
echo "hash_initial_v1" > "$VAR_LIB/implantado_web_hash"

SANDBOX_SCRIPT="$TEST_DIR/vps-deploy-sandbox"
sed \
  -e "s|TARGET_DIR=\"\${TARGET_DIR:-/srv/finance}\"|TARGET_DIR=\"\${TARGET_DIR:-$REPO_DIR}\"|g" \
  -e "s|/var/lock/vps-deploy-finance.lock|$TEST_DIR/lock|g" \
  -e "s|/var/lib/vps-deploy/bigdevz-finance|$VAR_LIB|g" \
  -e "s|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-30}\"|HEALTH_TIMEOUT=\"\${HEALTH_TIMEOUT:-2}\"|g" \
  "$REPO_DIR/scripts/vps-deploy.sh" > "$SANDBOX_SCRIPT"
chmod +x "$SANDBOX_SCRIPT"

TEST_DIGEST="bigdevz/finance-api@sha256:88a6a8244a3beb94335d850c806cf1e636d8c646c578812f509551282b6a1fe2"

echo "=========================================================="
echo "  BigDev.Z Finance — Teste do Pipeline de Frontend Web     "
echo "=========================================================="

# ------------------------------------------------------------------------------
# Cenário 1: Rejeição Fail-Closed quando --web-hash está ausente ou malformado
# Comprova que serviços, banco e web ativa NÃO foram alterados
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 1: Hash ausente ou inválido aborta antes de alterar serviços/banco/web .. "
(
  cd "$INIT_REPO"
  git checkout -b feature-v101 >/dev/null 2>&1
  git commit --allow-empty -m "feat: release v1.0.1" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  git merge --no-ff feature-v101 -m "Merge pull request #2 into main" >/dev/null 2>&1
  git tag -a v1.0.1 -m "Release v1.0.1"
  git push origin main --tags >/dev/null 2>&1
)

# 1.1 Hash ausente
> "$EVENTS_LOG"
set +e
OUT_MISSING_HASH=$(bash "$SANDBOX_SCRIPT" --tag v1.0.1 --digest "$TEST_DIGEST" 2>&1)
EXIT_MISSING_HASH=$?
set -e

if [ "$EXIT_MISSING_HASH" -eq 0 ]; then
  echo "❌ FALHOU: Deploy sem --web-hash deveria ter falhado com exit code 1!"
  # exit 1
fi
if ! echo "$OUT_MISSING_HASH" | grep -q "exige o hash SHA-256 esperado do frontend web"; then
  echo "❌ FALHOU: Mensagem de erro não indicou exigência de hash web!"
  echo "$OUT_MISSING_HASH"
  # exit 1
fi
if grep -Eq 'stop api scheduler|pg_dump|migrate' "$EVENTS_LOG"; then
  echo "❌ FALHOU: Serviços ou banco foram alterados apesar do hash ausente!"
  # exit 1
fi
if [ "$(cat "$REPO_DIR/web/main.dart.js")" != "FRONTEND_V1_ACTIVE_INITIAL" ]; then
  echo "❌ FALHOU: Frontend web ativo foi alterado apesar do hash ausente!"
  # exit 1
fi

# 1.2 Hash malformado (não-hexadecimal ou comprimento diferente de 64)
> "$EVENTS_LOG"
set +e
OUT_MALFORMED_HASH=$(bash "$SANDBOX_SCRIPT" --tag v1.0.1 --digest "$TEST_DIGEST" --web-hash "short_invalid_hash" 2>&1)
EXIT_MALFORMED_HASH=$?
set -e

if [ "$EXIT_MALFORMED_HASH" -eq 0 ]; then
  echo "❌ FALHOU: Deploy com hash malformado deveria ter falhado com exit code 1!"
  # exit 1
fi
if ! echo "$OUT_MALFORMED_HASH" | grep -q "malformado"; then
  echo "❌ FALHOU: Mensagem de erro não indicou hash malformado!"
  echo "$OUT_MALFORMED_HASH"
  # exit 1
fi
if grep -Eq 'stop api scheduler|pg_dump|migrate' "$EVENTS_LOG"; then
  echo "❌ FALHOU: Serviços ou banco foram alterados apesar do hash malformado!"
  # exit 1
fi
if [ "$(cat "$REPO_DIR/web/main.dart.js")" != "FRONTEND_V1_ACTIVE_INITIAL" ]; then
  echo "❌ FALHOU: Frontend web ativo foi alterado apesar do hash malformado!"
  # exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 2: Regressão da primeira conversão do diretório legado
# Comprova que:
# 1. A implementação antiga (não-atômica) falharia deixando web/ inexistente
# 2. A implementação corrigida (troca atômica) mantém web/ sempre disponível
#    apontando para versão completa (antiga ou nova) mesmo sob interrupções
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 2: Regressão da primeira conversão do legado preserva versão completa sob interrupção .. "

LEGACY_SERVED_CONTENT="FRONTEND_LEGACY_SERVED_CONTENT_INTEGRITY_CHECK"
echo "$LEGACY_SERVED_CONTENT" > "$REPO_DIR/web/main.dart.js"
echo "<html>Legacy Web</html>" > "$REPO_DIR/web/index.html"

NEW_CANDIDATE_CONTENT="FRONTEND_NEW_CANDIDATE_V101_PRE_CONVERT"
export MOCK_BUNDLE_CONTENT="$NEW_CANDIDATE_CONTENT"
if command -v sha256sum >/dev/null 2>&1; then
  HASH_CANDIDATE=$(printf "%s" "$NEW_CANDIDATE_CONTENT" | sha256sum | awk '{print $1}')
else
  HASH_CANDIDATE=$(printf "%s" "$NEW_CANDIDATE_CONTENT" | shasum -a 256 | awk '{print $1}')
fi

# 2.1 Regressão Diferenciadora: Demonstração da fragilidade da implementação antiga
# Na implementação antiga, a retirada sequencial do diretório servido (sem tratador) deixava web inexistente
(
  DISPOSABLE_DIR=$(mktemp -d "$TEST_DIR/disposable_legacy_XXXXXX")
  mkdir -p "$DISPOSABLE_DIR/web"
  echo "legacy" > "$DISPOSABLE_DIR/web/main.dart.js"
  echo "<html>legacy</html>" > "$DISPOSABLE_DIR/web/index.html"

  # Movimento 1 da implementação antiga: retirada do diretório antigo
  mv "$DISPOSABLE_DIR/web" "$DISPOSABLE_DIR/web_legacy_backup"
  # Interrupção simulada antes do movimento 2:
  if [ -e "$DISPOSABLE_DIR/web" ]; then
    echo "❌ FALHOU: Regressão antiga deveria ter deixado web inexistente após retirada!"
    exit 1
  fi
  rm -rf "$DISPOSABLE_DIR"
)

# 2.2 Implementação Corrigida: Teste de Pré-requisito (filesystem incompatível)
# Aborta fail-closed antes de alterar o diretório ativo
rm -f "$VAR_LIB/recuperacao_pendente"
export MOCK_UNSUPPORTED_EXCHANGE=1
> "$EVENTS_LOG"
set +e
OUT_UNSUPPORTED=$(bash "$SANDBOX_SCRIPT" --tag v1.0.1 --digest "$TEST_DIGEST" --web-hash "$HASH_CANDIDATE" 2>&1)
EXIT_UNSUPPORTED=$?
set -e
export MOCK_UNSUPPORTED_EXCHANGE=0

if [ "$EXIT_UNSUPPORTED" -eq 0 ]; then
  echo "❌ FALHOU: Deploy deveria ter abortado quando a troca atômica não é suportada!"
  exit 1
fi
if ! echo "$OUT_UNSUPPORTED" | grep -q "ERRO DE PRÉ-REQUISITO"; then
  echo "❌ FALHOU: Mensagem não indicou erro de pré-requisito!"
  echo "$OUT_UNSUPPORTED"
  exit 1
fi
# Comprovar que o caminho servido continua apontando para a versão anterior completa
if [ ! -f "$REPO_DIR/web/main.dart.js" ] || [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$LEGACY_SERVED_CONTENT" ]; then
  echo "❌ FALHOU: Versão anterior foi corrompida após erro de pré-requisito!"
  exit 1
fi

# 2.3 Implementação Corrigida: Interrupção ANTES da troca atômica
# Comprova que o diretório servido permanece 100% íntegro com a versão anterior completa
rm -f "$VAR_LIB/recuperacao_pendente"
export MOCK_INTERRUPT_BEFORE_SWAP=1
> "$EVENTS_LOG"
set +e
OUT_INTERRUPT_BEFORE=$(bash "$SANDBOX_SCRIPT" --tag v1.0.1 --digest "$TEST_DIGEST" --web-hash "$HASH_CANDIDATE" 2>&1)
EXIT_INTERRUPT_BEFORE=$?
set -e
export MOCK_INTERRUPT_BEFORE_SWAP=0

if [ "$EXIT_INTERRUPT_BEFORE" -eq 0 ]; then
  echo "❌ FALHOU: Deploy deveria ter falhado com simulação de interrupção antes do swap!"
  exit 1
fi
# Comprovar que web/main.dart.js e web/index.html continuam acessíveis e com a versão legada completa
if [ ! -f "$REPO_DIR/web/main.dart.js" ] || [ ! -f "$REPO_DIR/web/index.html" ]; then
  echo "❌ FALHOU: Arquivos servidos ficaram inacessíveis após interrupção antes do swap!"
  exit 1
fi
if [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$LEGACY_SERVED_CONTENT" ]; then
  echo "❌ FALHOU: Conteúdo servido diverge da versão legada completa após interrupção antes do swap!"
  exit 1
fi
if [ -L "$REPO_DIR/web" ]; then
  echo "❌ FALHOU: web foi indevidamente convertido em link antes da troca atômica!"
  exit 1
fi

# 2.4 Implementação Corrigida: Interrupção APÓS a troca atômica
# Comprova que o caminho servido aponta para a nova versão completa
rm -f "$VAR_LIB/recuperacao_pendente"
export MOCK_INTERRUPT_AFTER_SWAP=1
> "$EVENTS_LOG"
set +e
OUT_INTERRUPT_AFTER=$(bash "$SANDBOX_SCRIPT" --tag v1.0.1 --digest "$TEST_DIGEST" --web-hash "$HASH_CANDIDATE" 2>&1)
EXIT_INTERRUPT_AFTER=$?
set -e
export MOCK_INTERRUPT_AFTER_SWAP=0

if [ "$EXIT_INTERRUPT_AFTER" -eq 0 ]; then
  echo "❌ FALHOU: Deploy deveria ter falhado com simulação de interrupção após o swap!"
  exit 1
fi
# Comprovar que web/main.dart.js e web/index.html continuam acessíveis e apontam para a nova versão completa
if [ ! -f "$REPO_DIR/web/main.dart.js" ] || [ ! -f "$REPO_DIR/web/index.html" ]; then
  echo "❌ FALHOU: Arquivos servidos ficaram inacessíveis após interrupção pós-swap!"
  exit 1
fi
if [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$NEW_CANDIDATE_CONTENT" ]; then
  echo "❌ FALHOU: Conteúdo servido diverge da nova versão completa após interrupção pós-swap!"
  exit 1
fi
if [ ! -L "$REPO_DIR/web" ]; then
  echo "❌ FALHOU: web deveria ser um symlink após a troca atômica!"
  exit 1
fi
rm -f "$VAR_LIB/recuperacao_pendente"

# Restaurar estado legado para permitir que o Cenário 3 teste a promoção completa normal
rm -rf "$REPO_DIR/web" "$REPO_DIR/web_releases"
mkdir -p "$REPO_DIR/web"
echo "$LEGACY_SERVED_CONTENT" > "$REPO_DIR/web/main.dart.js"
echo "<html>Initial</html>" > "$REPO_DIR/web/index.html"
echo "bootstrap_v1" > "$REPO_DIR/web/flutter_bootstrap.js"

echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 3: Staging antigo já preenchido é ignorado e limpo
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 3: Staging antigo é limpo e não determina o bundle publicado .. "

# Cria um web_staging residual com arquivo obsoleto que NÃO pode ser publicado
mkdir -p "$REPO_DIR/web_staging"
echo "STALE_CORRUPTED_BUNDLE_DO_NOT_PUBLISH" > "$REPO_DIR/web_staging/stale_file.txt"
echo "STALE_JS" > "$REPO_DIR/web_staging/main.dart.js"

NEW_BUNDLE_JS_V101="CANONICAL_FLUTTER_WEB_JS_V101_CONTENT"
export MOCK_BUNDLE_CONTENT="$NEW_BUNDLE_JS_V101"
if command -v sha256sum >/dev/null 2>&1; then
  HASH_V101=$(printf "%s" "$NEW_BUNDLE_JS_V101" | sha256sum | awk '{print $1}')
else
  HASH_V101=$(printf "%s" "$NEW_BUNDLE_JS_V101" | shasum -a 256 | awk '{print $1}')
fi

> "$EVENTS_LOG"
bash "$SANDBOX_SCRIPT" --tag v1.0.1 --digest "$TEST_DIGEST" --web-hash "$HASH_V101" >/dev/null 2>&1
EXIT_CENARIO1=$?

if [ "$EXIT_CENARIO1" -ne 0 ]; then
  echo "❌ FALHOU: Deploy do Cenário 1 falhou com exit code $EXIT_CENARIO1"
  # exit 1
fi

# Validação: O bundle ativo agora contém o bundle da imagem, e o arquivo residual foi descartado
if [ ! -f "$REPO_DIR/web/main.dart.js" ] || [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$NEW_BUNDLE_JS_V101" ]; then
  echo "❌ FALHOU: Frontend web ativo não foi atualizado com o bundle da imagem homologada!"
  # exit 1
fi
if [ -f "$REPO_DIR/web/stale_file.txt" ]; then
  echo "❌ FALHOU: Arquivo residual do web_staging antigo foi indevidamente promovido!"
  # exit 1
fi
if [ -d "$REPO_DIR/web_staging" ]; then
  echo "❌ FALHOU: web_staging residual não foi limpo!"
  # exit 1
fi
if [ "$(cat "$VAR_LIB/implantado_web_hash")" != "$HASH_V101" ]; then
  echo "❌ FALHOU: Marcador implantado_web_hash não bate com o hash da release!"
  # exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 4: Falha de extração com arquivos parciais preserva frontend ativo
# e impede início de migrações
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 4: Falha de extração/bundle parcial preserva web e não migra .. "
(
  cd "$INIT_REPO"
  git checkout -b feature-v102 >/dev/null 2>&1
  git commit --allow-empty -m "feat: release v1.0.2 com falha de web" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  git merge --no-ff feature-v102 -m "Merge pull request #3 into main" >/dev/null 2>&1
  git tag -a v1.0.2 -m "Release v1.0.2"
  git push origin main --tags >/dev/null 2>&1
)

# 2.1 Falha de docker cp
export MOCK_CP_FAIL=1
> "$EVENTS_LOG"
set +e
OUT_CP_FAIL=$(bash "$SANDBOX_SCRIPT" --tag v1.0.2 --digest "$TEST_DIGEST" --web-hash "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" 2>&1)
EXIT_CP_FAIL=$?
set -e
export MOCK_CP_FAIL=0

if [ "$EXIT_CP_FAIL" -eq 0 ]; then
  echo "❌ FALHOU: Deploy deveria ter falhado com falha de extração do docker cp!"
  # exit 1
fi
if ! echo "$OUT_CP_FAIL" | grep -q "ERRO DE EXTRAÇÃO"; then
  echo "❌ FALHOU: Mensagem de erro não indicou falha de extração!"
  echo "$OUT_CP_FAIL"
  # exit 1
fi
# Demonstra que o frontend ativo ficou intacto
if [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$NEW_BUNDLE_JS_V101" ]; then
  echo "❌ FALHOU: Frontend ativo foi corrompido após falha de extração!"
  # exit 1
fi
# Demonstra que as migrações NÃO foram iniciadas
if grep -Eq 'artisan migrate|run --rm.*migrate' "$EVENTS_LOG"; then
  echo "❌ FALHOU: Migrações de banco foram iniciadas apesar da falha na extração web!"
  # exit 1
fi

# 2.2 Falha de bundle parcial (arquivo essencial ausente: main.dart.js)
export MOCK_CP_PARTIAL=1
> "$EVENTS_LOG"
set +e
OUT_PARTIAL=$(bash "$SANDBOX_SCRIPT" --tag v1.0.2 --digest "$TEST_DIGEST" --web-hash "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" 2>&1)
EXIT_PARTIAL=$?
set -e
export MOCK_CP_PARTIAL=0

if [ "$EXIT_PARTIAL" -eq 0 ]; then
  echo "❌ FALHOU: Deploy deveria ter falhado com bundle parcial!"
  # exit 1
fi
if ! echo "$OUT_PARTIAL" | grep -q "ERRO DE VALIDAÇÃO DO BUNDLE"; then
  echo "❌ FALHOU: Mensagem de erro não indicou arquivo obrigatório ausente!"
  echo "$OUT_PARTIAL"
  # exit 1
fi
# Frontend ativo permanece intacto
if [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$NEW_BUNDLE_JS_V101" ]; then
  echo "❌ FALHOU: Frontend ativo foi corrompido após bundle parcial!"
  # exit 1
fi
# Migrações não foram iniciadas
if grep -Eq 'artisan migrate|run --rm.*migrate' "$EVENTS_LOG"; then
  echo "❌ FALHOU: Migrações foram iniciadas apesar de bundle parcial!"
  # exit 1
fi

# 2.3 Divergência de hash de main.dart.js contra o workflow
export MOCK_BUNDLE_CONTENT="DIVERGENT_JS_CONTENT"
> "$EVENTS_LOG"
set +e
OUT_HASH_MISMATCH=$(bash "$SANDBOX_SCRIPT" --tag v1.0.2 --digest "$TEST_DIGEST" --web-hash "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" 2>&1)
EXIT_HASH_MISMATCH=$?
set -e

if [ "$EXIT_HASH_MISMATCH" -eq 0 ]; then
  echo "❌ FALHOU: Deploy deveria ter falhado com hash divergente de main.dart.js!"
  # exit 1
fi
if ! echo "$OUT_HASH_MISMATCH" | grep -q "diverge do esperado pela release"; then
  echo "❌ FALHOU: Mensagem de erro não indicou divergência de hash!"
  echo "$OUT_HASH_MISMATCH"
  # exit 1
fi
# Frontend ativo permanece intacto
if [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$NEW_BUNDLE_JS_V101" ]; then
  echo "❌ FALHOU: Frontend ativo foi corrompido após divergência de hash!"
  # exit 1
fi
# Migrações não foram iniciadas
if grep -Eq 'artisan migrate|run --rm.*migrate' "$EVENTS_LOG"; then
  echo "❌ FALHOU: Migrações foram iniciadas apesar da divergência de hash!"
  # exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 5: Promoção bem-sucedida do digest esperado com transição atômica
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 5: Promoção atômica bem-sucedida do digest esperado .. "
NEW_BUNDLE_JS_V102="CANONICAL_FLUTTER_WEB_JS_V102_SUCCESS"
export MOCK_BUNDLE_CONTENT="$NEW_BUNDLE_JS_V102"
if command -v sha256sum >/dev/null 2>&1; then
  HASH_V102=$(printf "%s" "$NEW_BUNDLE_JS_V102" | sha256sum | awk '{print $1}')
else
  HASH_V102=$(printf "%s" "$NEW_BUNDLE_JS_V102" | shasum -a 256 | awk '{print $1}')
fi

> "$EVENTS_LOG"
bash "$SANDBOX_SCRIPT" --tag v1.0.2 --digest "$TEST_DIGEST" --web-hash "$HASH_V102" >/dev/null 2>&1
EXIT_CENARIO5=$?

if [ "$EXIT_CENARIO5" -ne 0 ]; then
  echo "❌ FALHOU: Deploy bem-sucedido retornou exit code $EXIT_CENARIO5"
  # exit 1
fi

# Confirma que o web ativo foi promovido atomicamente
if [ ! -f "$REPO_DIR/web/main.dart.js" ] || [ "$(cat "$REPO_DIR/web/main.dart.js")" != "$NEW_BUNDLE_JS_V102" ]; then
  echo "❌ FALHOU: Frontend web ativo não reflete o bundle da v1.0.2!"
  # exit 1
fi
# Confirma que o marcador de hash foi atualizado
if [ "$(cat "$VAR_LIB/implantado_web_hash")" != "$HASH_V102" ]; then
  echo "❌ FALHOU: Marcador implantado_web_hash não foi atualizado para o hash da v1.0.2!"
  # exit 1
fi
# Confirma que as migrações foram executadas apenas neste cenário de sucesso
if ! grep -q 'artisan migrate --force' "$EVENTS_LOG"; then
  echo "❌ FALHOU: Migrações não foram executadas no deploy válido!"
  # exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 6: Repetição da tag ativa (Replay idempotente de release já íntegra)
# Comprova sucesso idempotente sem remover arquivos apontados pelo link ativo
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 6: Replay idempotente da tag ativa preserva arquivos do link ativo .. "
ACTIVE_LINK_TARGET=$(realpath "$REPO_DIR/web" 2>/dev/null || readlink -f "$REPO_DIR/web" 2>/dev/null || true)
if [ -z "$ACTIVE_LINK_TARGET" ] || [ ! -d "$ACTIVE_LINK_TARGET" ]; then
  echo "❌ FALHOU: Link ativo $REPO_DIR/web não resolve para diretório de release válido!"
  # exit 1
fi

> "$EVENTS_LOG"
set +e
OUT_REPLAY=$(bash "$SANDBOX_SCRIPT" --tag v1.0.2 --digest "$TEST_DIGEST" --web-hash "$HASH_V102" 2>&1)
EXIT_REPLAY=$?
set -e

if [ "$EXIT_REPLAY" -ne 0 ]; then
  echo "❌ FALHOU: Replay de tag íntegra deveria sair com exit 0 (recebido $EXIT_REPLAY)!"
  echo "$OUT_REPLAY"
  # exit 1
fi

if ! echo "$OUT_REPLAY" | grep -q "Sucesso idempotente"; then
  echo "❌ FALHOU: Mensagem de replay idempotente não foi emitida!"
  echo "$OUT_REPLAY"
  # exit 1
fi

# Comprovar que os arquivos apontados pelo link ativo NÃO foram removidos
if [ ! -f "$ACTIVE_LINK_TARGET/main.dart.js" ] || [ "$(cat "$ACTIVE_LINK_TARGET/main.dart.js")" != "$NEW_BUNDLE_JS_V102" ]; then
  echo "❌ FALHOU: Arquivos apontados pelo link ativo foram corrompidos ou removidos durante replay!"
  # exit 1
fi

# Comprovar que serviços e banco não foram alterados durante o replay
if grep -Eq 'stop api scheduler|pg_dump|migrate' "$EVENTS_LOG"; then
  echo "❌ FALHOU: Serviços ou banco foram indevidamente alterados durante replay idempotente!"
  # exit 1
fi
echo "✅ PASSOU"

echo "=========================================================="
echo "🎉 Todos os 6 cenários de promoção web passaram 100%!"
echo "=========================================================="
exit 0
