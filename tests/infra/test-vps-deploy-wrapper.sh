#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Testes Unitários do Wrapper de Segurança SSH
# Valida as rejeições fail-closed e a passagem estrita de tags SemVer
# ==============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d -t finance_wrapper_test_XXXXXX)
WRAPPER_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/vps-deploy-wrapper.sh"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

MOCK_DEPLOY="$TEST_DIR/vps-deploy.sh"
cat << 'EOF' > "$MOCK_DEPLOY"
#!/usr/bin/env bash
echo "DEPLOY_CALLED_WITH: $*"
exit 0
EOF
chmod +x "$MOCK_DEPLOY"

SANDBOX_WRAPPER="$TEST_DIR/wrapper"
sed "s|readonly DEPLOY_SCRIPT=\"/srv/finance/scripts/vps-deploy.sh\"|readonly DEPLOY_SCRIPT=\"$MOCK_DEPLOY\"|g" "$WRAPPER_SRC" > "$SANDBOX_WRAPPER"
chmod +x "$SANDBOX_WRAPPER"

echo "=========================================================="
echo "  BigDev.Z Finance — Testes de Segurança do Wrapper SSH    "
echo "=========================================================="

# Teste 1: Rejeição de comando vazio
echo -n "🧪 Teste 1: Rejeição de comando vazio .. "
set +e
OUT=$(SSH_ORIGINAL_COMMAND="" bash "$SANDBOX_WRAPPER" 2>&1)
CODE=$?
set -e
if [ "$CODE" -eq 1 ] && echo "$OUT" | grep -q "Nenhuma tag fornecida"; then
  echo "✅ PASSOU"
else
  echo "❌ FALHOU ($OUT)"
  exit 1
fi

# Teste 2: Rejeição de quebras de linha / injeção
echo -n "🧪 Teste 2: Rejeição de quebras de linha e injeção .. "
set +e
OUT=$(SSH_ORIGINAL_COMMAND=$'v1.0.1\nrm -rf /' bash "$SANDBOX_WRAPPER" 2>&1)
CODE=$?
set -e
if [ "$CODE" -eq 1 ] && echo "$OUT" | grep -q "Caracteres de quebra de linha detectados"; then
  echo "✅ PASSOU"
else
  echo "❌ FALHOU ($OUT)"
  exit 1
fi

# Teste 3: Rejeição de comando arbitrário ('check-access' probe)
echo -n "🧪 Teste 3: Rejeição do probe 'check-access' .. "
set +e
OUT=$(SSH_ORIGINAL_COMMAND="check-access" bash "$SANDBOX_WRAPPER" 2>&1)
CODE=$?
set -e
if [ "$CODE" -eq 1 ] && echo "$OUT" | grep -q "Apenas uma única tag no formato vMAJOR.MINOR.PATCH"; then
  echo "✅ PASSOU"
else
  echo "❌ FALHOU ($OUT)"
  exit 1
fi

# Teste 4: Rejeição de flags extras no comando
echo -n "🧪 Teste 4: Rejeição de flags extras no comando .. "
set +e
OUT=$(SSH_ORIGINAL_COMMAND="v1.0.1 --skip-checkout" bash "$SANDBOX_WRAPPER" 2>&1)
CODE=$?
set -e
if [ "$CODE" -eq 1 ] && echo "$OUT" | grep -q "Entrada rejeitada"; then
  echo "✅ PASSOU"
else
  echo "❌ FALHOU ($OUT)"
  exit 1
fi

# Teste 5: Aceitação de tag SemVer válida
echo -n "🧪 Teste 5: Execução autorizada de tag SemVer válida .. "
OUT=$(SSH_ORIGINAL_COMMAND="v1.0.1" bash "$SANDBOX_WRAPPER" 2>&1)
if echo "$OUT" | grep -q "DEPLOY_CALLED_WITH: --tag v1.0.1"; then
  echo "✅ PASSOU"
else
  echo "❌ FALHOU ($OUT)"
  exit 1
fi

echo "=========================================================="
echo "🎉 Todos os testes de segurança do wrapper passaram 100%!"
echo "=========================================================="
exit 0
