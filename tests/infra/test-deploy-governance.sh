#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Teste Automatizado de Governança de Deploy SemVer
# Valida rigorosamente todos os critérios de proveniência e aprovação humana:
# 1. PR de autoria de jeannlucas mergeado por jeannlucas -> APROVADO
# 2. PR de terceiro com review de aprovação formal de jeannlucas -> APROVADO
# 3. PR de terceiro mergeado sem aprovação formal válida -> REJEITADO
# 4. PR de terceiro com review de aprovação obsoleto (stale commit) -> REJEITADO
# 5. SHA da tag divergente do merge_commit_sha retornado pela API -> REJEITADO
# 6. PR mergeado de branch diferente de dev (ex: feature -> main) -> REJEITADO
# 7. PR de autoria de jeannlucas mergeado por terceiro sem autorização -> REJEITADO
# ==============================================================================
set -euo pipefail

TEST_DIR=$(mktemp -d -t finance_gov_test_XXXXXX)
VALIDATOR_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)/validate-deploy-governance.sh"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

MOCK_BIN="$TEST_DIR/bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$PATH"

# 1. Repositório Git de Teste
REPO_DIR="$TEST_DIR/repo"
mkdir -p "$REPO_DIR"
(
  cd "$REPO_DIR"
  git init -b main >/dev/null 2>&1
  git config user.name "Tester"
  git config user.email "tester@bigdevz.com"
  git config commit.gpgsign false

  # Base commit
  git commit --allow-empty -m "chore: base" >/dev/null 2>&1
  git checkout -b dev >/dev/null 2>&1
  git commit --allow-empty -m "feat: work on dev" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  git merge --no-ff dev -m "Merge pull request #10 from dev" >/dev/null 2>&1
  git tag v1.0.1
)
VALID_MERGE_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
DEV_HEAD_SHA=$(git -C "$REPO_DIR" rev-parse dev)

# Mock do `gh`
GH_MOCK="$MOCK_BIN/gh"
cat << 'EOF' > "$GH_MOCK"
#!/usr/bin/env bash
set -euo pipefail

CMD="$*"
JQ_FILTER=""
for ((i=1; i<=$#; i++)); do
  eval "arg=\${$i}"
  if [ "$arg" = "--jq" ]; then
    next=$((i+1))
    eval "JQ_FILTER=\${$next}"
    break
  fi
done

process_output() {
  if [ -n "$JQ_FILTER" ]; then
    jq -r "$JQ_FILTER"
  else
    cat
  fi
}

# Consulta de pulls por commit
if [[ "$CMD" =~ /commits/.*/pulls ]]; then
  echo '[{"number": 10, "base": {"ref": "main"}, "merged_at": "2026-11-12T00:00:00Z"}]' | process_output
  exit 0
fi

# Consulta de detalhes do PR
if [[ "$CMD" =~ /pulls/10(\ |$) ]]; then
  AUTHOR="${MOCK_PR_AUTHOR:-jeannlucas}"
  MERGED_BY="${MOCK_PR_MERGED_BY:-jeannlucas}"
  BASE_REF="${MOCK_PR_BASE:-main}"
  HEAD_REF="${MOCK_PR_HEAD:-dev}"
  HEAD_SHA="${MOCK_PR_HEAD_SHA:-$DEV_HEAD_SHA}"
  MERGE_SHA="${MOCK_PR_MERGE_SHA:-$VALID_MERGE_SHA}"

  cat << JSON | process_output
{
  "merged": true,
  "user": {"login": "$AUTHOR"},
  "merged_by": {"login": "$MERGED_BY"},
  "base": {"ref": "$BASE_REF"},
  "head": {"ref": "$HEAD_REF", "sha": "$HEAD_SHA"},
  "merge_commit_sha": "$MERGE_SHA"
}
JSON
  exit 0
fi

# Consulta de reviews
if [[ "$CMD" =~ /pulls/10/reviews ]]; then
  if [ "${MOCK_HAS_APPROVAL:-0}" -eq 1 ]; then
    COMMIT_REVIEWED="${MOCK_REVIEW_COMMIT:-$DEV_HEAD_SHA}"
    REVIEWER="${MOCK_REVIEWER:-jeannlucas}"
    STATE="${MOCK_REVIEW_STATE:-APPROVED}"
    cat << JSON | process_output
[
  {
    "user": {"login": "$REVIEWER"},
    "state": "$STATE",
    "commit_id": "$COMMIT_REVIEWED"
  }
]
JSON
  else
    echo "[]" | process_output
  fi
  exit 0
fi

echo "gh mock: unhandled command: $CMD" >&2
exit 1
EOF
chmod +x "$GH_MOCK"

echo "=========================================================="
echo "  BigDev.Z Finance — Testes de Governança de Deploy SemVer"
echo "=========================================================="

cd "$REPO_DIR"

# ------------------------------------------------------------------------------
# Teste 1: PR de autoria de jeannlucas mergeado por jeannlucas (dev -> main)
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 1: PR de jeannlucas mergeado por jeannlucas (dev -> main) .. "
export MOCK_PR_AUTHOR="jeannlucas"
export MOCK_PR_MERGED_BY="jeannlucas"
export MOCK_PR_BASE="main"
export MOCK_PR_HEAD="dev"
export MOCK_PR_HEAD_SHA="$DEV_HEAD_SHA"
export MOCK_PR_MERGE_SHA="$VALID_MERGE_SHA"
export MOCK_HAS_APPROVAL=0

OUT=$("$VALIDATOR_SRC" v1.0.1 2>&1) || {
  echo "❌ FALHOU (Deveria ter aprovado)"
  echo "$OUT"
  exit 1
}
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 2: PR de terceiro com aprovação formal válida de jeannlucas
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 2: PR de terceiro com aprovação válida de jeannlucas .. "
export MOCK_PR_AUTHOR="developer-terceiro"
export MOCK_PR_MERGED_BY="maintainer-bot"
export MOCK_HAS_APPROVAL=1
export MOCK_REVIEW_COMMIT="$DEV_HEAD_SHA"
export MOCK_REVIEWER="jeannlucas"
export MOCK_REVIEW_STATE="APPROVED"

if ! "$VALIDATOR_SRC" v1.0.1 >/dev/null 2>&1; then
  echo "❌ FALHOU (Deveria ter aprovado com review formal válido)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 3: Rejeição de PR de terceiro sem aprovação válida
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 3: Rejeição de merge por terceiro sem aprovação .. "
export MOCK_PR_AUTHOR="developer-terceiro"
export MOCK_PR_MERGED_BY="terceiro-sem-autorizacao"
export MOCK_HAS_APPROVAL=0

if "$VALIDATOR_SRC" v1.0.1 >/dev/null 2>&1; then
  echo "❌ FALHOU (Deveria ter rejeitado merge sem aprovação)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 4: Rejeição de aprovação obsoleta (stale review em commit anterior)
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 4: Rejeição de aprovação obsoleta (stale commit) .. "
export MOCK_PR_AUTHOR="developer-terceiro"
export MOCK_PR_MERGED_BY="terceiro"
export MOCK_HAS_APPROVAL=1
export MOCK_REVIEW_COMMIT="sha_antigo_obsoleto_12345"

if "$VALIDATOR_SRC" v1.0.1 >/dev/null 2>&1; then
  echo "❌ FALHOU (Deveria ter rejeitado aprovação em commit obsoleto)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 5: Rejeição de SHA da tag divergente do merge_commit_sha retornado pela API
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 5: Rejeição de SHA divergente da API .. "
export MOCK_PR_AUTHOR="jeannlucas"
export MOCK_PR_MERGED_BY="jeannlucas"
export MOCK_PR_MERGE_SHA="sha_diferente_retornado_pela_api_9999"

if "$VALIDATOR_SRC" v1.0.1 >/dev/null 2>&1; then
  echo "❌ FALHOU (Deveria ter rejeitado SHA divergente)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 6: Rejeição de PR com branch base ou head inválidos (não dev -> main)
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 6: Rejeição de branch inválida (não dev -> main) .. "
export MOCK_PR_AUTHOR="jeannlucas"
export MOCK_PR_MERGED_BY="jeannlucas"
export MOCK_PR_MERGE_SHA="$VALID_MERGE_SHA"
export MOCK_PR_HEAD="feature/minha-feature"
export MOCK_PR_BASE="main"

if "$VALIDATOR_SRC" v1.0.1 >/dev/null 2>&1; then
  echo "❌ FALHOU (Deveria ter rejeitado PR fora de dev -> main)"
  exit 1
fi
echo "✅ PASSOU"

# ------------------------------------------------------------------------------
# Teste 7: Rejeição de PR de jeannlucas mergeado por terceiro sem autorização
# ------------------------------------------------------------------------------
echo -n "🧪 Cenário 7: Rejeição de PR de jeannlucas mergeado por terceiro .. "
export MOCK_PR_AUTHOR="jeannlucas"
export MOCK_PR_MERGED_BY="atacante-ou-terceiro"
export MOCK_PR_HEAD="dev"
export MOCK_PR_BASE="main"
export MOCK_PR_MERGE_SHA="$VALID_MERGE_SHA"

if "$VALIDATOR_SRC" v1.0.1 >/dev/null 2>&1; then
  echo "❌ FALHOU (Deveria ter rejeitado merge por terceiro sem review)"
  exit 1
fi
echo "✅ PASSOU"

echo "=========================================================="
echo "🎉 Todos os 7 testes de governança e aprovação passaram 100%!"
echo "=========================================================="
exit 0
