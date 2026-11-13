#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Validador de Governança de Deploy SemVer
# Padrão: Tag SemVer -> Merge commit na main -> PR de dev para main aprovado
# ==============================================================================
set -euo pipefail

TAG_NAME="${GITHUB_REF_NAME:-${1:-}}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-jeannlucas/bigdevz-finance}"
GITHUB_STEP_SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ -z "$TAG_NAME" ]; then
  echo "❌ ERRO: Nenhuma tag informada. Uso: $0 <tag-semver>" >&2
  exit 1
fi

echo "=========================================================="
echo "Validando tag de release para deploy em produção: $TAG_NAME"
echo "=========================================================="

# 1. Validação regex SemVer estrita (vMAJOR.MINOR.PATCH)
SEMVER_REGEX='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ! [[ "$TAG_NAME" =~ $SEMVER_REGEX ]]; then
  echo "❌ ERRO DE GOVERNANÇA: A tag '$TAG_NAME' não segue o padrão SemVer vMAJOR.MINOR.PATCH." >&2
  exit 1
fi
echo "✅ Formato SemVer válido: $TAG_NAME"

# 2. Obter commit exato apontado pela tag
TARGET_SHA="${TARGET_SHA:-}"
if [ -z "$TARGET_SHA" ]; then
  TARGET_SHA=$(git rev-parse -q --verify "refs/tags/${TAG_NAME}^{commit}" 2>/dev/null || true)
fi
if [ -z "$TARGET_SHA" ]; then
  TARGET_SHA=$(git rev-parse -q --verify "${TAG_NAME}^{commit}" 2>/dev/null || true)
fi
if [ -z "$TARGET_SHA" ]; then
  echo "❌ ERRO DE GOVERNANÇA: Tag '$TAG_NAME' não encontrada no repositório." >&2
  exit 1
fi
echo "SHA alvo da tag: $TARGET_SHA"

# 3. Validar se o commit pertence à branch main
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  MAIN_REF="origin/main"
elif git rev-parse --verify main >/dev/null 2>&1; then
  MAIN_REF="main"
else
  MAIN_REF=""
fi

if [ -n "$MAIN_REF" ]; then
  if ! git merge-base --is-ancestor "$TARGET_SHA" "$MAIN_REF"; then
    echo "❌ ERRO DE GOVERNANÇA: O commit $TARGET_SHA apontado pela tag não pertence à branch $MAIN_REF!" >&2
    exit 1
  fi
  echo "✅ Commit pertence à branch $MAIN_REF."
fi

# 4. Validar se o commit é um merge commit (2 ou mais pais)
PARENT_COUNT=$(git rev-list --parents -n 1 "$TARGET_SHA" | awk '{print NF-1}')
if [ "$PARENT_COUNT" -lt 2 ]; then
  echo "❌ ERRO DE GOVERNANÇA: O commit $TARGET_SHA apontado pela tag possui apenas $PARENT_COUNT pai e NÃO é um merge commit!" >&2
  echo "   De acordo com a Seção 1 do AGENTS.md, todo deploy em produção deve ser precedido de PR de dev para main aprovado com 'Create a merge commit'." >&2
  exit 1
fi
echo "✅ Proveniência confirmada: merge commit com $PARENT_COUNT pais."

# 5. Validar aprovação formal do Pull Request correspondente na main
echo "Verificando se o commit foi gerado por um Pull Request aprovado e mergeado na branch main..."
PR_NUM=$(gh api "repos/${GITHUB_REPOSITORY}/commits/${TARGET_SHA}/pulls" --jq '.[] | select(.base.ref == "main" and .merged_at != null) | .number' 2>/dev/null | head -n 1 || true)
if [ -z "$PR_NUM" ]; then
  COMMIT_MSG=$(git log -1 --pretty=%B "$TARGET_SHA")
  if [[ "$COMMIT_MSG" =~ Merge\ pull\ request\ #([0-9]+) ]]; then
    PR_NUM="${BASH_REMATCH[1]}"
  fi
fi

if [ -z "$PR_NUM" ]; then
  echo "❌ ERRO DE GOVERNANÇA: O commit $TARGET_SHA apontado pela tag não foi gerado por um Pull Request na branch main!" >&2
  exit 1
fi

echo "Validando Pull Request #$PR_NUM e proveniência de governança..."
PR_DATA=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUM}" --jq '{merged: .merged, merged_by: .merged_by.login, user: .user.login, base: .base.ref, head: .head.ref, head_sha: .head.sha, merge_commit_sha: .merge_commit_sha}' 2>/dev/null || true)
PR_AUTHOR=$(echo "$PR_DATA" | jq -r '.user // empty')
MERGED_BY=$(echo "$PR_DATA" | jq -r '.merged_by // empty')
BASE_REF=$(echo "$PR_DATA" | jq -r '.base // empty')
HEAD_REF=$(echo "$PR_DATA" | jq -r '.head // empty')
PR_HEAD_SHA=$(echo "$PR_DATA" | jq -r '.head_sha // empty')
PR_MERGE_SHA=$(echo "$PR_DATA" | jq -r '.merge_commit_sha // empty')

# Validação: Fluxo estrito de dev para main
if [ "$BASE_REF" != "main" ] || [ "$HEAD_REF" != "dev" ]; then
  echo "❌ ERRO DE GOVERNANÇA: O PR #$PR_NUM deve ser obrigatoriamente de 'dev' para 'main' (encontrado: '$HEAD_REF' -> '$BASE_REF')!" >&2
  exit 1
fi
echo "✅ Fluxo de branch confirmado: '$HEAD_REF' -> '$BASE_REF'."

# Validação: O SHA da tag deve corresponder exatamente ao merge_commit_sha retornado pela API
if [ -z "$PR_MERGE_SHA" ] || [ "$TARGET_SHA" != "$PR_MERGE_SHA" ]; then
  echo "❌ ERRO DE GOVERNANÇA: O SHA da tag ($TARGET_SHA) diverge do merge_commit_sha oficial do PR #$PR_NUM ($PR_MERGE_SHA)!" >&2
  exit 1
fi
echo "✅ SHA da tag ($TARGET_SHA) confere exatamente com o merge_commit_sha do PR #$PR_NUM."

# Validação: Evidência própria de autorização humana por Jeann Lucas
HUMAN_AUTH_EVIDENCE=""
if [ "$PR_AUTHOR" = "jeannlucas" ]; then
  if [ "$MERGED_BY" = "jeannlucas" ]; then
    HUMAN_AUTH_EVIDENCE="Autorizado por Jeann Lucas (autor do PR e executor do merge commit na main)"
    echo "✅ Promoção aprovada comprovada com evidência própria: PR de autoria de jeannlucas mergeado diretamente por jeannlucas."
  else
    echo "❌ ERRO DE GOVERNANÇA: PR de autoria de jeannlucas foi mergeado por terceiro ('$MERGED_BY') sem autorização!" >&2
    exit 1
  fi
else
  # Para PRs de outros autores, exige review formal APPROVED vigente emitido por jeannlucas para o PR_HEAD_SHA exato
  APPROVED_FOR_HEAD=0
  if [ -n "$PR_HEAD_SHA" ]; then
    APPROVED_FOR_HEAD=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUM}/reviews" --jq "[.[] | select(.user.login == \"jeannlucas\" and .state == \"APPROVED\" and .commit_id == \"${PR_HEAD_SHA}\")] | length" 2>/dev/null || echo 0)
  fi

  if [ "$APPROVED_FOR_HEAD" -gt 0 ]; then
    HUMAN_AUTH_EVIDENCE="Autorizado por Jeann Lucas (review de aprovação formal sobre head $PR_HEAD_SHA)"
    echo "✅ Promoção aprovada comprovada com evidência própria: PR #$PR_NUM ($HEAD_REF -> $BASE_REF), autorizada formalmente por Jeann Lucas ($APPROVED_FOR_HEAD aprovações vigentes)."
  else
    echo "❌ ERRO DE GOVERNANÇA: O PR #$PR_NUM não possui aprovação formal válida de Jeann Lucas para a revisão de código promovida ($PR_HEAD_SHA)!" >&2
    echo "   (autor: '$PR_AUTHOR', merged_by: '$MERGED_BY', aprovações vigentes de jeannlucas no head: $APPROVED_FOR_HEAD). Aprovações obsoletas ou merge por terceiro sem review de aprovação são rejeitados." >&2
    exit 1
  fi
fi

if [ "$GITHUB_STEP_SUMMARY" != "/dev/null" ]; then
  {
    echo "## 🏷️ Validação de Tag SemVer e Governança"
    echo "| Parâmetro | Valor |"
    echo "|---|---|"
    echo "| **Tag de Release** | \`$TAG_NAME\` |"
    echo "| **Commit Alvo** | \`$TARGET_SHA\` |"
    echo "| **Branch Base** | \`main\` |"
    echo "| **Pull Request** | #$PR_NUM (\`$HEAD_REF\` → \`$BASE_REF\`) |"
    echo "| **Autorização Humana** | ✅ $HUMAN_AUTH_EVIDENCE |"
    echo "| **Status da Governança** | ✅ 100% Conforme AGENTS.md |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "=========================================================="
echo "🎉 Governança e autorização de release aprovadas!"
echo "=========================================================="
exit 0
