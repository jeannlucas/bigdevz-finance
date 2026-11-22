#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Teste Automatizado da Barreira de Release de Produção
# Valida a barreira dupla de verificação pós-deploy (API health + Web hash):
# 1. Ambos corretos -> Sucesso (código 0)
# 2. Revisão da API divergente -> Falha (código 1) com diagnóstico
# 3. Hash do Frontend Web divergente (Regressão v1.3.0) -> Falha (código 1) com diagnóstico
# 4. Falha de rede / HTTP 500 -> Falha (código 1)
# 5. Argumentos obrigatórios ausentes -> Falha (código 1)
# ==============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d -t finance_release_verify_test_XXXXXX)
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)"
VERIFY_SCRIPT="$SCRIPTS_DIR/verify-production-release.sh"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$PATH"

MOCK_LOG="$TEST_DIR/mock_curl.log"
touch "$MOCK_LOG"

cat << 'EOF' > "$MOCK_BIN/curl"
#!/usr/bin/env bash
echo "CURL: $*" >> "${TEST_MOCK_LOG}"

URL=""
OUT_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      OUT_FILE="$2"
      shift 2
      ;;
    http*|https*)
      URL="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ "${MOCK_CURL_FAIL:-0}" = "1" ]; then
  exit 1
fi

if [[ "$URL" =~ /api/health ]]; then
  if [ "${MOCK_API_FAIL:-0}" = "1" ]; then
    echo '{"status":"error","message":"Internal Server Error"}'
    exit 1
  fi
  REVISION="${MOCK_API_REVISION:-6cd4ae72409d9c211447cbd18d47a02870d71a77}"
  STATUS="${MOCK_API_STATUS:-ok}"
  echo "{\"status\":\"$STATUS\",\"revision\":\"$REVISION\"}"
  exit 0
fi

if [[ "$URL" =~ /main.dart.js ]]; then
  CONTENT="${MOCK_WEB_CONTENT:-MOCK_JAVASCRIPT_CANONICAL_V131}"
  if [ -n "$OUT_FILE" ]; then
    printf "%s" "$CONTENT" > "$OUT_FILE"
  else
    printf "%s" "$CONTENT"
  fi
  exit 0
fi

exit 0
EOF
chmod +x "$MOCK_BIN/curl"
export TEST_MOCK_LOG="$MOCK_LOG"

echo "=========================================================="
echo "  BigDev.Z Finance — Teste de Barreira de Release       "
echo "=========================================================="

EXPECTED_SHA="6cd4ae72409d9c211447cbd18d47a02870d71a77"
CANONICAL_CONTENT="MOCK_JAVASCRIPT_CANONICAL_V131"
if command -v sha256sum >/dev/null 2>&1; then
  EXPECTED_HASH=$(printf "%s" "$CANONICAL_CONTENT" | sha256sum | awk '{print $1}')
  STALE_HASH=$(printf "%s" "MOCK_JAVASCRIPT_STALE_V120" | sha256sum | awk '{print $1}')
else
  EXPECTED_HASH=$(printf "%s" "$CANONICAL_CONTENT" | shasum -a 256 | awk '{print $1}')
  STALE_HASH=$(printf "%s" "MOCK_JAVASCRIPT_STALE_V120" | shasum -a 256 | awk '{print $1}')
fi

# ------------------------------------------------------------------------------
# Cenário 1: API e Web coincidem com o esperado -> Sucesso (código 0)
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 1: API e Frontend Web íntegros e sincronizados .. "
export MOCK_API_REVISION="$EXPECTED_SHA"
export MOCK_API_STATUS="ok"
export MOCK_WEB_CONTENT="$CANONICAL_CONTENT"

OUT1=$(bash "$VERIFY_SCRIPT" \
  --expected-sha "$EXPECTED_SHA" \
  --expected-web-hash "$EXPECTED_HASH" \
  --max-attempts 1 \
  --delay 0 2>&1)
EXIT1=$?

if [ "$EXIT1" -ne 0 ] || ! echo "$OUT1" | grep -q "BARREIRA DUPLA DE RELEASE APROVADA"; then
  echo "❌ FALHOU: Verificação válida rejeitada indevidamente!"
  echo "$OUT1"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 2: API diverge na revisão -> Falha (código 1) com diagnóstico
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 2: Revisão da API divergente é rejeitada .. "
export MOCK_API_REVISION="divergent_sha_999999"
export MOCK_WEB_CONTENT="$CANONICAL_CONTENT"

set +e
OUT2=$(bash "$VERIFY_SCRIPT" \
  --expected-sha "$EXPECTED_SHA" \
  --expected-web-hash "$EXPECTED_HASH" \
  --max-attempts 1 \
  --delay 0 2>&1)
EXIT2=$?
set -e

if [ "$EXIT2" -eq 0 ]; then
  echo "❌ FALHOU: API divergente foi aceita indevidamente!"
  exit 1
fi
if ! echo "$OUT2" | grep -q "API pública não sincronizou"; then
  echo "❌ FALHOU: Mensagem de erro não indicou falha na API."
  echo "$OUT2"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 3: Frontend Web diverge (Regressão Incidente v1.3.0) -> Falha (código 1)
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 3: Frontend Web desatualizado (incidente v1.3.0) é rejeitado .. "
export MOCK_API_REVISION="$EXPECTED_SHA"
export MOCK_API_STATUS="ok"
export MOCK_WEB_CONTENT="MOCK_JAVASCRIPT_STALE_V120"

set +e
OUT3=$(bash "$VERIFY_SCRIPT" \
  --expected-sha "$EXPECTED_SHA" \
  --expected-web-hash "$EXPECTED_HASH" \
  --max-attempts 1 \
  --delay 0 2>&1)
EXIT3=$?
set -e

if [ "$EXIT3" -eq 0 ]; then
  echo "❌ FALHOU: Frontend Web desatualizado foi aceito indevidamente!"
  exit 1
fi
if ! echo "$OUT3" | grep -q "Frontend Web público (main.dart.js) não sincronizou"; then
  echo "❌ FALHOU: Mensagem de erro não indicou falha no hash do Frontend Web."
  echo "$OUT3"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 4: Falha de rede ou HTTP 500 -> Falha (código 1)
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 4: Erro de rede ou endpoint indisponível .. "
export MOCK_CURL_FAIL=1

set +e
OUT4=$(bash "$VERIFY_SCRIPT" \
  --expected-sha "$EXPECTED_SHA" \
  --expected-web-hash "$EXPECTED_HASH" \
  --max-attempts 1 \
  --delay 0 2>&1)
EXIT4=$?
set -e
export MOCK_CURL_FAIL=0

if [ "$EXIT4" -eq 0 ]; then
  echo "❌ FALHOU: Falha de rede deveria ter rejeitado o deploy!"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Cenário 5: Parâmetros obrigatórios ausentes -> Falha (código 1)
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 5: Parâmetros obrigatórios ausentes fail-closed .. "
set +e
bash "$VERIFY_SCRIPT" --expected-sha "" --expected-web-hash "$EXPECTED_HASH" >/dev/null 2>&1
EXIT5A=$?
bash "$VERIFY_SCRIPT" --expected-sha "$EXPECTED_SHA" --expected-web-hash "" >/dev/null 2>&1
EXIT5B=$?
set -e

if [ "$EXIT5A" -eq 0 ] || [ "$EXIT5B" -eq 0 ]; then
  echo "❌ FALHOU: Verificação sem argumentos obrigatórios deveria ter falhado!"
  exit 1
fi
echo "✅ PASSOU"

echo "=========================================================="
echo "🎉 Todos os 5 cenários da barreira de release passaram 100%!"
echo "=========================================================="
exit 0
