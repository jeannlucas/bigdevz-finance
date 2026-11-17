#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Script Canônico de Deploy na VPS (/srv/finance)
# Padrão: SemVer tag -> Merge commit na main -> Fail-closed rollback com DB
# ==============================================================================
set -euo pipefail

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${PROJECT_NAME:-finance-prod}}"
export COMPOSE_PROJECT_NAME="$PROJECT_NAME"
TARGET_DIR="${TARGET_DIR:-/srv/finance}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.production.yml}"
COMPOSE_ENV_FILE="${COMPOSE_ENV_FILE:-.env.production}"
BACKUP_DIR="${BACKUP_DIR:-$TARGET_DIR/backups/db}"
LOCK_FILE="${LOCK_FILE:-/var/lock/vps-deploy-finance.lock}"
VAR_LIB_DIR="${VAR_LIB_DIR:-/var/lib/vps-deploy/bigdevz-finance}"

API_PORT="${API_PORT:-8510}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-30}"
CONTAINER_PG="${CONTAINER_PG:-}"
CONTAINER_API="${CONTAINER_API:-}"
DB_USER="${DB_USER:-bigdevz}"
DB_NAME="${DB_NAME:-bigdevz_finance}"
DEPLOY_TAG="${DEPLOY_TAG:-}"
FINANCE_IMAGE_DIGEST="${FINANCE_IMAGE_DIGEST:-}"
SKIP_GIT_CHECKOUT="${SKIP_GIT_CHECKOUT:-0}"
DEPLOY_HEALTH_PASSED=0

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
    --project|-p)
      PROJECT_NAME="$2"
      export COMPOSE_PROJECT_NAME="$PROJECT_NAME"
      shift 2
      ;;
    --skip-checkout)
      SKIP_GIT_CHECKOUT=1
      shift
      ;;
    --help|-h)
      echo "Uso: $0 [--tag vX.Y.Z] [--digest imagem@sha256:...] [--project nome] [--skip-checkout]"
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

# ==============================================================================
# Funções Auxiliares de Execução e Pré-Voo
# ==============================================================================

run_compose() {
  docker compose --env-file "$COMPOSE_ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

safe_write_marker() {
  local target_file="$1"
  local content="$2"
  local target_dir
  target_dir="$(dirname "$target_file")"
  mkdir -p "$target_dir"
  local tmp_file
  tmp_file=$(mktemp "${target_dir}/.marker_tmp_XXXXXX")
  printf '%s\n' "$content" > "$tmp_file"
  chmod 644 "$tmp_file" 2>/dev/null || true
  mv -f "$tmp_file" "$target_file"
}

get_service_container() {
  local service="$1"
  local cid=""
  cid=$(run_compose ps -q "$service" 2>/dev/null | head -n 1 || true)
  if [ -n "$cid" ]; then
    docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||' || true
  fi
}

resolve_containers() {
  if [ -z "$CONTAINER_PG" ]; then
    if docker inspect "finance-prod-postgres-1" >/dev/null 2>&1; then
      CONTAINER_PG="finance-prod-postgres-1"
    elif docker inspect "bigdevz-finance-postgres-1" >/dev/null 2>&1; then
      CONTAINER_PG="bigdevz-finance-postgres-1"
    else
      local discovered_pg
      discovered_pg=$(get_service_container "postgres")
      if [ -n "$discovered_pg" ]; then
        CONTAINER_PG="$discovered_pg"
      else
        CONTAINER_PG="${PROJECT_NAME}-postgres-1"
      fi
    fi
  fi

  if [ -z "$CONTAINER_API" ]; then
    if docker inspect "finance-prod-api-1" >/dev/null 2>&1; then
      CONTAINER_API="finance-prod-api-1"
    elif docker inspect "bigdevz-finance-api-1" >/dev/null 2>&1; then
      CONTAINER_API="bigdevz-finance-api-1"
    else
      local discovered_api
      discovered_api=$(get_service_container "api")
      if [ -n "$discovered_api" ]; then
        CONTAINER_API="$discovered_api"
      else
        CONTAINER_API="${PROJECT_NAME}-api-1"
      fi
    fi
  fi
}

check_permissions_preflight() {
  if ! mkdir -p "$VAR_LIB_DIR" 2>/dev/null; then
    echo "❌ ERRO DE PRÉ-VOO: Impossível criar ou acessar diretório de marcadores: $VAR_LIB_DIR" >&2
    exit 1
  fi
  if [ ! -w "$VAR_LIB_DIR" ]; then
    echo "❌ ERRO DE PRÉ-VOO: Sem permissão de escrita no diretório de marcadores: $VAR_LIB_DIR" >&2
    exit 1
  fi

  local test_file
  test_file=$(mktemp "$VAR_LIB_DIR/.preflight_test_XXXXXX" 2>/dev/null || true)
  if [ -z "$test_file" ] || [ ! -f "$test_file" ]; then
    echo "❌ ERRO DE PRÉ-VOO: Falha ao criar arquivo de teste no diretório de marcadores: $VAR_LIB_DIR" >&2
    exit 1
  fi
  rm -f "$test_file"

  for marker in "$MARCADOR_TAG" "$MARCADOR_COMMIT" "$MARCADOR_DIGEST" "$RECOVERY_PENDING"; do
    if [ -e "$marker" ] && [ ! -w "$marker" ]; then
      echo "❌ ERRO DE PRÉ-VOO: Marcador '$marker' existe mas não possui permissão de escrita para o usuário atual ($(id -un))." >&2
      echo "   Execute no servidor: sudo chown $(id -un):$(id -gn) $marker && sudo chmod 644 $marker" >&2
      exit 1
    fi
  done

  if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    echo "❌ ERRO DE PRÉ-VOO: Impossível criar ou acessar diretório de backup: $BACKUP_DIR" >&2
    exit 1
  fi
  if [ ! -w "$BACKUP_DIR" ]; then
    echo "❌ ERRO DE PRÉ-VOO: Sem permissão de escrita no diretório de backup: $BACKUP_DIR" >&2
    exit 1
  fi
}

check_infra_preflight() {
  resolve_containers

  if ! docker inspect "$CONTAINER_PG" >/dev/null 2>&1; then
    echo "❌ ERRO DE PRÉ-VOO: Container de banco de dados '$CONTAINER_PG' não existe no Docker." >&2
    exit 1
  fi

  local pg_running
  pg_running=$(docker inspect --format '{{.State.Running}}' "$CONTAINER_PG" 2>/dev/null || true)
  if [ "$pg_running" = "false" ]; then
    echo "❌ ERRO DE PRÉ-VOO: Container de banco de dados '$CONTAINER_PG' não está em execução." >&2
    exit 1
  fi

  echo "✅ Pré-voo de infraestrutura aprovado: Container de banco '$CONTAINER_PG' disponível."
}

# ==============================================================================
# Execução Principal do Pipeline de Deploy
# ==============================================================================

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
  TARGET_SHA=$(git rev-parse -q --verify "refs/remotes/origin/tags/${DEPLOY_TAG}^{commit}" 2>/dev/null || git rev-parse -q --verify "refs/tags/${DEPLOY_TAG}^{commit}" 2>/dev/null || true)
  if [ -z "$TARGET_SHA" ]; then
    echo "❌ ERRO DE GOVERNANÇA: Tag '$DEPLOY_TAG' não encontrada no repositório." >&2
    exit 1
  fi

  # Validar ancestralidade na origin/main ou main
  if git rev-parse --verify refs/remotes/origin/main >/dev/null 2>&1; then
    if ! git merge-base --is-ancestor "$TARGET_SHA" refs/remotes/origin/main; then
      echo "❌ ERRO DE GOVERNANÇA: O commit $TARGET_SHA apontado pela tag não pertence a origin/main!" >&2
      exit 1
    fi
  elif git rev-parse --verify refs/heads/main >/dev/null 2>&1; then
    if ! git merge-base --is-ancestor "$TARGET_SHA" refs/heads/main; then
      echo "❌ ERRO DE GOVERNANÇA: O commit $TARGET_SHA apontado pela tag não pertence a main!" >&2
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

# 5. Verificação de Marcadores e Pré-Voo de Permissões
MARCADOR_TAG="$VAR_LIB_DIR/implantado_tag"
MARCADOR_COMMIT="$VAR_LIB_DIR/implantado"
MARCADOR_DIGEST="$VAR_LIB_DIR/implantado_digest"
RECOVERY_PENDING="$VAR_LIB_DIR/recuperacao_pendente"

check_permissions_preflight

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
  safe_write_marker "$MARCADOR_TAG" "$DEPLOY_TAG"
  exit 0
fi

PREVIOUS_COMMIT="$IMPLANTADO_COMMIT"
if [ -z "$PREVIOUS_COMMIT" ] || ! git cat-file -e "${PREVIOUS_COMMIT}^{commit}"; then
  echo "Não foi possível comprovar o commit implantado. Deploy bloqueado." >&2
  exit 1
fi

PREVIOUS_DIGEST=$(cat "$MARCADOR_DIGEST" 2>/dev/null || true)
if [ -z "$PREVIOUS_DIGEST" ] && command -v docker >/dev/null 2>&1; then
  resolve_containers
  PREVIOUS_DIGEST=$(docker inspect "$CONTAINER_API" --format '{{.Image}}' 2>/dev/null || true)
fi

# Validar se a referência anterior está disponível para reversão
if [ -n "$PREVIOUS_DIGEST" ] && command -v docker >/dev/null 2>&1; then
  if docker inspect "$PREVIOUS_DIGEST" >/dev/null 2>&1; then
    if [[ "$PREVIOUS_DIGEST" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
      echo "ℹ️ [vps-deploy] Referência anterior para reversão comprovada: ID local de imagem ($PREVIOUS_DIGEST)."
    else
      echo "ℹ️ [vps-deploy] Referência anterior para reversão comprovada: $PREVIOUS_DIGEST."
    fi
  else
    echo "⚠️ [vps-deploy] Referência anterior ($PREVIOUS_DIGEST) não encontrada no Docker local." >&2
  fi
fi

# 6. Validação Estrita de Referência do Registro por Digest (Fail-Closed antes de qualquer alteração)
AUTHORIZED_REPO_REGEX='^(bigdevz/finance-api|ghcr\.io/[a-zA-Z0-9._-]+/(bigdevz-)?finance-api)'
STRICT_DIGEST_REGEX="^(${AUTHORIZED_REPO_REGEX})@sha256:[a-fA-F0-9]{64}$"

if [ -z "$FINANCE_IMAGE_DIGEST" ]; then
  echo "❌ ERRO DE GOVERNANÇA: O deploy de produção em $TARGET_DIR exige uma referência imutável do registro (--digest <repositório>@sha256:<64 hex chars>). Referência vazia rejeitada antes de alterar serviços ou rodar migrações." >&2
  exit 1
fi

if [[ "$FINANCE_IMAGE_DIGEST" =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
  echo "❌ ERRO DE GOVERNANÇA: Referência '$FINANCE_IMAGE_DIGEST' rejeitada. O digest não pode ser um sha256 isolado sem o repositório autorizado (formato esperado: <repositório>@sha256:<hash>)." >&2
  exit 1
fi

if [[ "$FINANCE_IMAGE_DIGEST" =~ :[a-zA-Z0-9._-]+$ ]] && ! [[ "$FINANCE_IMAGE_DIGEST" =~ @sha256: ]]; then
  echo "❌ ERRO DE GOVERNANÇA: Referência '$FINANCE_IMAGE_DIGEST' rejeitada. Tags isoladas são proibidas em produção. Exija <repositório>@sha256:<64 hex chars>." >&2
  exit 1
fi

if ! [[ "$FINANCE_IMAGE_DIGEST" =~ $STRICT_DIGEST_REGEX ]]; then
  echo "❌ ERRO DE GOVERNANÇA: Referência '$FINANCE_IMAGE_DIGEST' inválida ou repositório não autorizado para o Finance." >&2
  echo "   Formato obrigatório: <repositório>@sha256:<64 hex chars> (repositórios autorizados: bigdevz/finance-api, ghcr.io/*/bigdevz-finance-api)." >&2
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

# Pré-voo de conectividade e infraestrutura do banco de dados antes de parar qualquer escritor
check_infra_preflight

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

  if [ "$DEPLOY_HEALTH_PASSED" -eq 1 ]; then
    echo "⚠️ [vps-deploy] ATENÇÃO: Falha ocorreu APÓS o healthcheck ser aprovado com sucesso." >&2
    echo "   Os serviços da aplicação (API e Scheduler) permanecem ATIVOS e SAUDÁVEIS." >&2
    echo "   Verifique permissões de marcadores ou serviços de notificação." >&2
    return
  fi

  if [ "$MIGRATIONS_RAN" -eq 1 ]; then
    if ! run_compose stop api scheduler; then
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
       ! run_compose up -d --no-build api scheduler; then
      echo "Falha ao retomar a versão anterior. Intervenção necessária." >&2
    else
      rm -f "$RECOVERY_PENDING"
    fi
  fi
}
trap perform_rollback EXIT

# Parar os escritores antes de criar o snapshot
WRITERS_STOPPED=1
run_compose stop api scheduler
if ! running_writers=$(run_compose ps --status running -q api scheduler) || [ -n "$running_writers" ]; then
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

# Persistir o estado de recuperação antes de iniciar qualquer etapa que possa alterar o banco
safe_write_marker "$RECOVERY_PENDING" "$(printf 'SHA=%s\nBACKUP=%s\nCHECKSUM=%s\n' "$PREVIOUS_COMMIT" "$BACKUP_FILE" "$SHA_FILE")"

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

# 9. Execução das migrações de banco
MIGRATIONS_RAN=1
echo "🚀 Executando migrações de banco (seeds de usuários estritamente desativadas)..."
run_compose run --rm -T --no-deps api php artisan migrate --force
run_compose up -d --no-build api scheduler

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

# Sincronização e transição atômica de Frontend Web se houver staging preparado
if [ -d "$TARGET_DIR/web_staging" ]; then
  echo "🌐 Promovendo Frontend Web coordenado (staging -> web)..."
  mkdir -p "$TARGET_DIR/web"
  rsync -ac --delete "$TARGET_DIR/web_staging/" "$TARGET_DIR/web/"
  rm -rf "$TARGET_DIR/web_staging"
  echo "✅ Frontend Web atualizado com sucesso após healthcheck positivo da API."
fi

# Marcação de saúde aprovada
DEPLOY_HEALTH_PASSED=1

# 11. Atualização dos Marcadores de Sucesso
safe_write_marker "$MARCADOR_TAG" "$DEPLOY_TAG"
safe_write_marker "$MARCADOR_COMMIT" "$TARGET_SHA"
safe_write_marker "$MARCADOR_DIGEST" "$FINANCE_IMAGE_DIGEST"
rm -f "$RECOVERY_PENDING"

if command -v notify-deploy >/dev/null 2>&1; then
  notify-deploy success --project "$PROJECT_NAME" --msg "Produção promovida com sucesso para $DEPLOY_TAG ($TARGET_SHA)" || true
fi

echo "=========================================================="
echo "✅ Deploy de $PROJECT_NAME concluído com 100% de sucesso!"
echo "   Tag: $DEPLOY_TAG | Commit: $TARGET_SHA"
echo "=========================================================="
exit 0
