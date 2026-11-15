#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Script Canônico de Deploy na VPS (/srv/finance)
# Padrão: SemVer tag -> Merge commit na main -> Fail-closed rollback com DB
# ==============================================================================
set -euo pipefail

PROJECT_NAME="bigdevz-finance"
TARGET_DIR="${TARGET_DIR:-/srv/finance}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.production.yml}"
COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-.env.production}"
BACKUP_DIR="${BACKUP_DIR:-$TARGET_DIR/backups/db}"
LOCK_FILE="${LOCK_FILE:-/var/lock/vps-deploy-finance.lock}"
VAR_LIB_DIR="${VAR_LIB_DIR:-/var/lib/vps-deploy/bigdevz-finance}"
API_PORT="${API_PORT:-8510}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-30}"
CONTAINER_PG="${CONTAINER_PG:-finance-postgres-prod}"
CONTAINER_API="${CONTAINER_API:-finance-api-prod}"
DB_USER="${DB_USER:-bigdevz}"
DB_NAME="${DB_NAME:-bigdevz_finance}"
DEPLOY_TAG="${DEPLOY_TAG:-}"
FINANCE_IMAGE_DIGEST="${FINANCE_IMAGE_DIGEST:-}"
SKIP_GIT_CHECKOUT="${SKIP_GIT_CHECKOUT:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)
      DEPLOY_TAG="$2"
      shift 2
      ;;
    --digest|--image-digest)
      FINANCE_IMAGE_DIGEST="$2"
      shift 2
      ;;
    --skip-checkout)
      SKIP_GIT_CHECKOUT=1
      shift
      ;;
    --help|-h)
      echo "Uso: $0 [--tag vX.Y.Z] [--digest imagem@sha256:...] [--skip-checkout]"
      exit 0
      ;;
    *)
      if [ -z "$DEPLOY_TAG" ] && [[ "$1" =~ ^v ]]; then
        DEPLOY_TAG="$1"
        shift
      else
        echo "Argumento desconhecido: $1" >&2
        exit 1
      fi
      ;;
  esac
done

# Trava contra execuções concorrentes (flock)
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9> "$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
  flock -n 9 || {
    echo "⚠️ [vps-deploy] Outro deploy já está em andamento para $PROJECT_NAME. Encerrando."
    exit 0
  }
fi

cd "$TARGET_DIR" || exit 1

# 1. Consulta / Fetch de tags SemVer isoladas se for repositório Git
if [ -d "$TARGET_DIR/.git" ] && [ "$SKIP_GIT_CHECKOUT" -eq 0 ]; then
  if ! git fetch -q --no-tags --prune origin "+refs/heads/main:refs/remotes/origin/main" "+refs/tags/v*:refs/remotes/origin/tags/v*"; then
    echo "❌ Falha ao consultar o remoto origin (rede ou autenticação). Abortando." >&2
    exit 1
  fi
fi

# 2. Resolução da Tag Alvo
if [ -z "$DEPLOY_TAG" ]; then
  if [ -d "$TARGET_DIR/.git" ]; then
    DEPLOY_TAG=$(git for-each-ref --points-at refs/remotes/origin/main --format='%(refname:strip=4)' refs/remotes/origin/tags/ 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)
  fi
fi

if [ -z "$DEPLOY_TAG" ]; then
  echo "ℹ️ [vps-deploy] Nenhuma tag SemVer (vMAJOR.MINOR.PATCH) apontando para origin/main. Deploy ignorado."
  exit 0
fi

# 3. Validação Regex SemVer estrita
SEMVER_REGEX='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
if ! [[ "$DEPLOY_TAG" =~ $SEMVER_REGEX ]]; then
  echo "❌ ERRO DE GOVERNANÇA: A tag '$DEPLOY_TAG' não segue o padrão SemVer vMAJOR.MINOR.PATCH." >&2
  exit 1
fi

# 4. Obtenção do commit alvo e validação de merge commit
if [ -d "$TARGET_DIR/.git" ]; then
  TARGET_SHA=$(git rev-parse -q --verify "refs/remotes/origin/tags/${DEPLOY_TAG}^{commit}" 2>/dev/null || true)
  if [ -z "$TARGET_SHA" ]; then
    echo "❌ ERRO DE GOVERNANÇA: Tag '$DEPLOY_TAG' não encontrada no repositório." >&2
    exit 1
  fi

  # Validar ancestralidade na origin/main
  if git rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1; then
    if ! git merge-base --is-ancestor "$TARGET_SHA" refs/remotes/origin/main; then
      echo "❌ ERRO DE GOVERNANÇA: O commit $TARGET_SHA apontado pela tag não pertence a origin/main!" >&2
      exit 1
    fi
  fi

  # Validar se é merge commit (>= 2 pais)
  PARENTS=$(git rev-list --parents -n 1 "$TARGET_SHA" | awk '{print NF-1}')
  if [ "$PARENTS" -lt 2 ]; then
    echo "❌ ERRO DE GOVERNANÇA: Tag $DEPLOY_TAG aponta para commit direto na main ($PARENTS pais). Deploy rejeitado." >&2
    exit 1
  fi
else
  echo "Checkout Git de produção indisponível." >&2
  exit 1
fi

# 5. Verificação de Marcadores
MARCADOR_TAG="$VAR_LIB_DIR/implantado_tag"
MARCADOR_COMMIT="$VAR_LIB_DIR/implantado"
mkdir -p "$VAR_LIB_DIR"
RECOVERY_PENDING="$VAR_LIB_DIR/recuperacao_pendente"
if [ -e "$RECOVERY_PENDING" ]; then
  echo "Recuperação pendente em $RECOVERY_PENDING. Deploy bloqueado." >&2
  exit 1
fi

IMPLANTADA_TAG=$(cat "$MARCADOR_TAG" 2>/dev/null || true)
IMPLANTADO_COMMIT=$(cat "$MARCADOR_COMMIT" 2>/dev/null || true)

if [ "$IMPLANTADA_TAG" = "$DEPLOY_TAG" ] && [ -n "$DEPLOY_TAG" ]; then
  echo "ℹ️ [vps-deploy] Tag $DEPLOY_TAG já está implantada (marcador sincronizado). Deploy ignorado."
  exit 0
fi

if [ -n "$IMPLANTADO_COMMIT" ] && [ "$IMPLANTADO_COMMIT" = "$TARGET_SHA" ] && [ "$TARGET_SHA" != "static-version" ]; then
  echo "ℹ️ [vps-deploy] Commit $TARGET_SHA da tag $DEPLOY_TAG já está em execução. Sincronizando marcador de tag."
  printf '%s\n' "$DEPLOY_TAG" > "$MARCADOR_TAG"
  exit 0
fi

PREVIOUS_COMMIT="$IMPLANTADO_COMMIT"
if [ -z "$PREVIOUS_COMMIT" ] || ! git cat-file -e "${PREVIOUS_COMMIT}^{commit}"; then
  echo "Não foi possível comprovar o commit implantado. Deploy bloqueado." >&2
  exit 1
fi

MARCADOR_DIGEST="$VAR_LIB_DIR/implantado_digest"
PREVIOUS_DIGEST=$(cat "$MARCADOR_DIGEST" 2>/dev/null || true)
if [ -z "$PREVIOUS_DIGEST" ] && command -v docker >/dev/null 2>&1; then
  PREVIOUS_DIGEST=$(docker inspect "$CONTAINER_API" --format '{{.Image}}' 2>/dev/null || true)
fi

# 6. Validação Estrita de Digest Imutável para Produção (Fail-Closed antes de qualquer alteração)
if [ -z "$FINANCE_IMAGE_DIGEST" ]; then
  echo "❌ ERRO DE GOVERNANÇA: O deploy de produção em $TARGET_DIR exige um digest imutável do registro (--digest <imagem>@sha256:...). Fallback para tags desativado." >&2
  exit 1
fi

DIGEST_REGEX='^([a-zA-Z0-9._/-]+@)?sha256:[a-fA-F0-9]{64}$'
if ! [[ "$FINANCE_IMAGE_DIGEST" =~ $DIGEST_REGEX ]]; then
  echo "❌ ERRO DE GOVERNANÇA: Digest inválido '$FINANCE_IMAGE_DIGEST'. Formato esperado: <repo>@sha256:<64 hex chars> ou sha256:<64 hex chars>." >&2
  exit 1
fi

if [ ! -f "$COMPOSE_FILE" ] || ! command -v docker >/dev/null 2>&1; then
  echo "Docker ou manifesto Compose de produção indisponível." >&2
  exit 1
fi

echo "🔍 Validando disponibilidade da imagem digest no Docker: $FINANCE_IMAGE_DIGEST..."
if ! docker inspect "$FINANCE_IMAGE_DIGEST" >/dev/null 2>&1; then
  echo "📥 Baixando imagem por digest do registro..."
  if ! docker pull "$FINANCE_IMAGE_DIGEST"; then
    echo "❌ Falha ao baixar a imagem por digest '$FINANCE_IMAGE_DIGEST' do registro. Deploy abortado antes de migrações ou alterações em serviços." >&2
    exit 1
  fi
fi

umask 077
mkdir -p "$BACKUP_DIR"
BACKUP_FILE=$(mktemp "$BACKUP_DIR/pre_deploy_XXXXXXXX")
SHA_FILE="${BACKUP_FILE}.sha256"
MIGRATIONS_RAN=0
WRITERS_STOPPED=0

perform_rollback() {
  local exit_code=$?
  if [ "$exit_code" -eq 0 ]; then
    return
  fi
  if [ "$MIGRATIONS_RAN" -eq 1 ]; then
    if ! docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" stop api scheduler; then
      echo "Falha ao parar os serviços após o erro de deploy." >&2
    fi
    echo "O banco pode ter sido alterado. Snapshot preservado em $BACKUP_FILE." >&2
    echo "Recuperação manual necessária. Novos deploys permanecem bloqueados." >&2
    return
  fi
  if [ "$WRITERS_STOPPED" -eq 1 ]; then
    if [ -n "$PREVIOUS_DIGEST" ]; then
      export FINANCE_API_IMAGE="$PREVIOUS_DIGEST"
    fi
    if ! git reset --hard "$PREVIOUS_COMMIT" -q ||
       ! docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" up -d --no-build api scheduler; then
      echo "Falha ao retomar a versão anterior. Intervenção necessária." >&2
    else
      rm -f "$RECOVERY_PENDING"
    fi
  fi
}
trap perform_rollback EXIT

# Parar os escritores antes de criar o snapshot.
WRITERS_STOPPED=1
docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" stop api scheduler
if ! running_writers=$(docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" ps --status running -q api scheduler) || [ -n "$running_writers" ]; then
  echo "Não foi possível confirmar a parada dos escritores. Deploy bloqueado." >&2
  exit 1
fi

if ! docker exec -i "$CONTAINER_PG" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc --no-owner --no-acl > "$BACKUP_FILE" ||
   [ ! -s "$BACKUP_FILE" ]; then
  echo "Backup pré-deploy falhou ou está vazio. Deploy bloqueado." >&2
  exit 1
fi
docker exec -i "$CONTAINER_PG" pg_restore --list < "$BACKUP_FILE" >/dev/null
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$BACKUP_FILE" > "$SHA_FILE"
else
  shasum -a 256 "$BACKUP_FILE" > "$SHA_FILE"
fi

# Persistir o estado antes de iniciar qualquer etapa que possa alterar o banco.
printf 'SHA=%s\nBACKUP=%s\nCHECKSUM=%s\n' "$PREVIOUS_COMMIT" "$BACKUP_FILE" "$SHA_FILE" > "$RECOVERY_PENDING"

# 7. Atualização do Código para a Versão Alvo
if [ -d "$TARGET_DIR/.git" ] && [ "$SKIP_GIT_CHECKOUT" -eq 0 ]; then
  echo "🔄 Atualizando repositório para o commit $TARGET_SHA..."
  git reset --hard "$TARGET_SHA" -q
fi

# 8. Inicialização com imagem homologada e imutável (--no-build)
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Manifesto de produção ausente no commit de destino." >&2
  exit 1
fi

export FINANCE_API_IMAGE="$FINANCE_IMAGE_DIGEST"
echo "📦 Imagem digest imutável homologada para implantação: $FINANCE_API_IMAGE"

MIGRATIONS_RAN=1
echo "🚀 Executando migrações de banco (seeds de usuários estritamente desativadas)..."
docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" run --rm -T --no-deps api php artisan migrate --force
docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" up -d --no-build api scheduler

# 10. Validação de Saúde (Healthcheck)
echo "🩺 Executando healthcheck pós-deploy..."
HEALTH_OK=0
for i in $(seq 1 "$HEALTH_TIMEOUT"); do
  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${API_PORT}/up" || true)
  if [ "$STATUS_CODE" = "200" ]; then
    HEALTH_OK=1
    break
  fi
  sleep 1
done

if [ "$HEALTH_OK" -ne 1 ]; then
  echo "❌ Healthcheck falhou: endpoint /up não respondeu 200 em ${HEALTH_TIMEOUT}s." >&2
  exit 1
fi

# 11. Atualização dos Marcadores de Sucesso
printf '%s\n' "$DEPLOY_TAG" > "$MARCADOR_TAG"
printf '%s\n' "$TARGET_SHA" > "$MARCADOR_COMMIT"
printf '%s\n' "$FINANCE_IMAGE_DIGEST" > "$MARCADOR_DIGEST"
rm -f "$RECOVERY_PENDING"

if command -v notify-deploy >/dev/null 2>&1; then
  notify-deploy success --project "$PROJECT_NAME" --msg "Produção promovida com sucesso para $DEPLOY_TAG ($TARGET_SHA)" || true
fi

echo "=========================================================="
echo "✅ Deploy de $PROJECT_NAME concluído com 100% de sucesso!"
echo "   Tag: $DEPLOY_TAG | Commit: $TARGET_SHA"
echo "=========================================================="
exit 0
