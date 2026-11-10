#!/bin/bash
# ==============================================================================
# BigDev.Z Finance — Script de Deploy Automatizado para Produção (VPS srv1884441)
# Topologia: PostgreSQL 17 Alpine | Base: bigdevz_finance | Caddy no Host
# Uso:
#   ./scripts/deploy-production.sh --check-only    # Validação local e build sem tocar na VPS
#   ./scripts/deploy-production.sh --execute       # Execução na VPS (apenas a partir da main)
# ==============================================================================
set -euo pipefail

MODE="check"
SSH_ALIAS="bigdevz"
REMOTE_DIR="/srv/finance"
BACKUP_DIR="${REMOTE_DIR}/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
API_PORT="8510"

for arg in "$@"; do
    case "$arg" in
        --check-only) MODE="check" ;;
        --execute) MODE="execute" ;;
    esac
done

echo "=============================================================================="
echo " PIPELINE DE DEPLOY DE PRODUÇÃO — BIGDEV.Z FINANCE"
echo " Topologia VPS: PostgreSQL 17 | Base: bigdevz_finance | Caddy TLS"
echo " Modo de Execução: $MODE"
echo "=============================================================================="

echo "=== [1/7] Validação de Branch e Integridade Git ==="
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "Branch local ativa: $CURRENT_BRANCH ($CURRENT_COMMIT)"

if [ "$MODE" = "execute" ]; then
    if [ "$CURRENT_BRANCH" != "main" ] && [ "${ALLOW_NON_MAIN:-false}" != "true" ]; then
        echo "ERRO FATAL: Deploy de produção exige obrigatoriamente a branch 'main'!" >&2
        echo "A branch atual é '$CURRENT_BRANCH'. Faça o merge para a main antes de publicar." >&2
        exit 1
    fi
    
    # Confirma que a working tree está limpa
    if ! git diff-index --quiet HEAD --; then
        echo "ERRO FATAL: Existem alterações não commitadas na working tree local!" >&2
        exit 1
    fi
fi

echo "=== [2/7] Compilação do Frontend Flutter Web (Release) ==="
cd apps/mobile
echo "Executando build do Flutter Web para produção (https://finance.bigdevz.com/api)..."
flutter pub get --enforce-lockfile
flutter build web --release --dart-define=API_BASE_URL=https://finance.bigdevz.com/api
cd ../..

if [ ! -f "apps/mobile/build/web/index.html" ] || [ ! -f "apps/mobile/build/web/main.dart.js" ]; then
    echo "ERRO FATAL: Falha na compilação do Flutter Web! Bundle incompleto." >&2
    exit 1
fi
echo "OK: Bundle Flutter Web compilado com sucesso em apps/mobile/build/web/."

echo "=== [3/7] Quality Gate Local Pré-Deploy ==="
echo "Executando testes de domínio financeiro..."
php apps/api/tests/domain.php
echo "Executando linter Laravel Pint..."
(cd apps/api && vendor/bin/pint --test)
echo "Executando análise estática Dart..."
(cd apps/mobile && flutter analyze)

if [ "$MODE" = "check" ]; then
    echo "=============================================================================="
    echo " [MODO CHECK-ONLY CONCLUÍDO COM SUCESSO]"
    echo " Todos os pré-requisitos locais, compilações e testes foram 100% aprovados."
    echo " Nenhuma modificação foi executada na VPS."
    echo " Para publicar em produção após o merge na main: $0 --execute"
    echo "=============================================================================="
    exit 0
fi

# ==============================================================================
# SEÇÃO REMOTA (EXECUTADA APENAS COM --execute NA BRANCH MAIN)
# ==============================================================================
echo "=== [4/7] Snapshot Preventivo do Banco de Dados PostgreSQL 17 na VPS ==="
ssh "$SSH_ALIAS" "mkdir -p ${BACKUP_DIR}/db ${BACKUP_DIR}/web_previous ${BACKUP_DIR}/api_previous"

echo "Gerando dump da base bigdevz_finance antes de aplicar qualquer alteração..."
ssh "$SSH_ALIAS" "
    CONTAINER_PG='bigdevz-finance-postgres-1'
    BACKUP_FILE='${BACKUP_DIR}/db/pre_deploy_${TIMESTAMP}.dump'
    docker exec -i \$CONTAINER_PG pg_dump -U bigdevz -d bigdevz_finance -Fc --no-owner --no-acl > \$BACKUP_FILE
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum \$BACKUP_FILE > \${BACKUP_FILE}.sha256
    fi
    echo 'Backup concluído: ' \$BACKUP_FILE
"

echo "=== [5/7] Arquivamento das Versões Atuais para Rollback Rápido ==="
ssh "$SSH_ALIAS" "
    # Arquiva versão atual do frontend web
    if [ -d '${REMOTE_DIR}/web' ]; then
        rm -rf '${BACKUP_DIR}/web_previous'
        cp -r '${REMOTE_DIR}/web' '${BACKUP_DIR}/web_previous'
    fi
    # Arquiva versão atual da API (exceto storage e vendor pesado)
    if [ -d '${REMOTE_DIR}/api' ]; then
        rm -rf '${BACKUP_DIR}/api_previous'
        mkdir -p '${BACKUP_DIR}/api_previous'
        rsync -a --exclude 'storage' --exclude 'vendor' '${REMOTE_DIR}/api/' '${BACKUP_DIR}/api_previous/'
    fi
"

echo "=== [6/7] Sincronização Segura do Código (Frontend Web e Backend API) ==="
# Sincroniza Flutter Web
rsync -avz --delete apps/mobile/build/web/ "${SSH_ALIAS}:${REMOTE_DIR}/web/"

# Sincroniza API Laravel preservando storage, logs e production.conf
rsync -avz --exclude 'storage/logs/*' --exclude 'storage/framework/cache/*' \
    --exclude '.env' --exclude 'production.conf' apps/api/ "${SSH_ALIAS}:${REMOTE_DIR}/api/"

echo "Recompilando containers da API e Scheduler na VPS..."
ssh "$SSH_ALIAS" "
    cd ${REMOTE_DIR}
    docker compose up -d --build api scheduler
"

echo "Executando migrações no banco bigdevz_finance (--force)..."
ssh "$SSH_ALIAS" "
    docker exec -i bigdevz-finance-api-1 php artisan migrate --force
"

echo "Otimizando caches de produção do Laravel..."
ssh "$SSH_ALIAS" "
    docker exec -i bigdevz-finance-api-1 php artisan config:cache
    docker exec -i bigdevz-finance-api-1 php artisan route:cache
    docker exec -i bigdevz-finance-api-1 php artisan view:cache
"

echo "=== [7/7] Validação de Saúde e Teste de Fumaça Pós-Deploy ==="
ssh "$SSH_ALIAS" "
    sleep 3
    echo 'Verificando endpoint de vida (/up)...'
    STATUS_UP=\$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${API_PORT}/up || echo 'fail')
    if [ \"\$STATUS_UP\" != '200' ]; then
        echo 'ERRO: Endpoint /up falhou com status ' \$STATUS_UP >&2
        exit 1
    fi
    echo 'OK: Endpoint /up respondendo 200.'

    echo 'Verificando endpoint de saúde detalhado (/api/health)...'
    HEALTH_JSON=\$(curl -s http://127.0.0.1:${API_PORT}/api/health || echo '')
    echo 'Saúde dos subsistemas: ' \$HEALTH_JSON
    if ! echo \"\$HEALTH_JSON\" | grep -q '\"status\":\"ok\"'; then
        echo 'ERRO: Health check detalhado reportou falha!' >&2
        exit 1
    fi
    echo 'OK: Base de dados e storage íntegros.'
"

echo "=============================================================================="
echo " DEPLOY DE PRODUÇÃO CONCLUÍDO COM SUCESSO!"
echo " Aplicação: https://finance.bigdevz.com"
echo " Snapshot de Banco: pre_deploy_${TIMESTAMP}.dump"
echo " Rollback disponível via: ./scripts/rollback-production.sh"
echo "=============================================================================="
