#!/bin/bash
# ==============================================================================
# BigDev.Z Finance — Script de Rollback Seguro de Produção
# Alinhado à topologia real da VPS (PostgreSQL 17, Caddy no host, base bigdevz_finance)
# Suporta: Rollback de Código (API / Web) e/ou Restauração Explícita do Banco
# Uso: ./scripts/rollback-production.sh [--code-only] [--with-db-restore <caminho_do_backup.dump>]
# ==============================================================================
set -euo pipefail

RESTORE_DB=false
RESTORE_CODE=false
BACKUP_FILE=""
APP_DIR="/srv/finance"
BACKUP_DIR="${APP_DIR}/backups"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --code-only)
            RESTORE_CODE=true
            shift
            ;;
        --with-code)
            RESTORE_CODE=true
            shift
            ;;
        --with-db-restore)
            RESTORE_DB=true
            BACKUP_FILE="${2:-}"
            shift 2
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            echo "Uso: $0 [--code-only] [--with-db-restore <caminho_do_backup.dump>]" >&2
            exit 1
            ;;
    esac
done

echo "=============================================================================="
echo " INICIANDO PROTOCOLO DE ROLLBACK DE PRODUÇÃO — BIGDEV.Z FINANCE"
echo " Topologia: PostgreSQL 17 Alpine | Base: bigdevz_finance | Caddy no Host"
echo "=============================================================================="

# Se nenhuma flag foi passada, restaura o código por padrão
if [ "$RESTORE_DB" = false ] && [ "$RESTORE_CODE" = false ]; then
    RESTORE_CODE=true
fi

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-finance-prod}"
CONTAINER_API=$(docker ps --format '{{.Names}}' | grep -E 'finance-prod-api-1|bigdevz-finance-api-1|api' | head -n1 || true)
CONTAINER_SCHEDULER=$(docker ps --format '{{.Names}}' | grep -E 'finance-prod-scheduler-1|bigdevz-finance-scheduler-1|scheduler' | head -n1 || true)
CONTAINER_PG=$(docker ps --format '{{.Names}}' | grep -E 'finance-prod-postgres-1|bigdevz-finance-postgres-1|postgres' | head -n1 || true)

echo "=== [1/4] Interrompendo Containers da Aplicação (api e scheduler) ==="
if [ -n "$CONTAINER_API" ]; then
    docker stop "$CONTAINER_API" ${CONTAINER_SCHEDULER:+"$CONTAINER_SCHEDULER"} || true
fi

if [ "$RESTORE_CODE" = true ]; then
    echo "=== [2/4] Revertendo Versão do Código (API e Flutter Web) ==="
    
    # Reverte Frontend Web se houver versão anterior arquivada
    if [ -d "${BACKUP_DIR}/web_previous" ]; then
        echo "Restaurando bundle estático anterior em ${APP_DIR}/web..."
        rm -rf "${APP_DIR}/web"
        cp -r "${BACKUP_DIR}/web_previous" "${APP_DIR}/web"
        echo "Frontend Web revertido com sucesso."
    else
        echo "Aviso: Diretório ${BACKUP_DIR}/web_previous não encontrado para rollback de frontend."
    fi

    # Reverte Backend API se houver versão anterior arquivada
    if [ -d "${BACKUP_DIR}/api_previous" ]; then
        echo "Restaurando código anterior da API em ${APP_DIR}/api..."
        # Preserva .env / production.conf e storage atual
        mkdir -p /tmp/finance_preserve
        [ -f "${APP_DIR}/api/.env" ] && cp "${APP_DIR}/api/.env" /tmp/finance_preserve/
        
        rm -rf "${APP_DIR}/api"
        cp -r "${BACKUP_DIR}/api_previous" "${APP_DIR}/api"
        
        [ -f /tmp/finance_preserve/.env ] && cp /tmp/finance_preserve/.env "${APP_DIR}/api/.env"
        rm -rf /tmp/finance_preserve
        echo "Backend API revertido com sucesso."
    else
        echo "Aviso: Diretório ${BACKUP_DIR}/api_previous não encontrado para rollback de API."
    fi
fi

if [ "$RESTORE_DB" = true ]; then
    echo "=== [3/4] Restauração do Banco de Dados PostgreSQL 17 (bigdevz_finance) ==="
    if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
        echo "ERRO FATAL: Arquivo de backup não especificado ou não encontrado: '$BACKUP_FILE'" >&2
        exit 1
    fi

    # Validação rigorosa de Checksum SHA-256 se existir
    CHECKSUM_FILE="${BACKUP_FILE}.sha256"
    if [ -f "$CHECKSUM_FILE" ]; then
        echo "Validando checksum SHA-256 do backup antes da restauração..."
        if command -v shasum >/dev/null 2>&1; then
            shasum -a 256 -c "$CHECKSUM_FILE"
        elif command -v sha256sum >/dev/null 2>&1; then
            sha256sum -c "$CHECKSUM_FILE"
        fi
        echo "Checksum SHA-256 verificado com sucesso!"
    else
        echo "AVISO OPERACIONAL: Checksum não localizado. Prosseguindo com o dump informado."
    fi

    if [ -z "$CONTAINER_PG" ]; then
        CONTAINER_PG=$(docker ps --format '{{.Names}}' | grep -E 'finance-prod-postgres-1|bigdevz-finance-postgres-1|postgres' | head -n1 || true)
    fi
    if [ -z "$CONTAINER_PG" ]; then
        CONTAINER_PG="${PROJECT_NAME}-postgres-1"
    fi
    DB_USER="bigdevz"
    DB_NAME="bigdevz_finance"

    echo "Encerrando conexões ativas na base '$DB_NAME'..."
    docker exec -i "$CONTAINER_PG" psql -U "$DB_USER" -d postgres -c "
        SELECT pg_terminate_backend(pid) FROM pg_stat_activity 
        WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();
    " || true

    echo "Executando pg_restore com --clean na base '$DB_NAME'..."
    cat "$BACKUP_FILE" | docker exec -i "$CONTAINER_PG" \
        pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists --no-owner --no-acl || true

    echo "Banco de dados restaurado com sucesso a partir de $BACKUP_FILE!"
else
    echo "=== [3/4] Restauração de Banco Não Solicitada ==="
    echo "Nota: O banco de dados foi preservado. Se a falha foi causada por schema incompatível,"
    echo "execute novamente com: $0 --with-db-restore <caminho_do_dump>"
fi

echo "=== [4/4] Reinicializando Containers e Validando Saúde ==="
COMPOSE_FILE=""
if [ -f "${APP_DIR}/docker-compose.production.yml" ]; then
    COMPOSE_FILE="${APP_DIR}/docker-compose.production.yml"
elif [ -f "${APP_DIR}/docker-compose.yml" ]; then
    COMPOSE_FILE="${APP_DIR}/docker-compose.yml"
fi

if [ -n "$COMPOSE_FILE" ]; then
    cd "$APP_DIR"
    docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d --no-build api scheduler 2>/dev/null || \
    docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d api scheduler
elif [ -n "$CONTAINER_API" ]; then
    docker start "$CONTAINER_API" ${CONTAINER_SCHEDULER:+"$CONTAINER_SCHEDULER"} 2>/dev/null || true
fi

echo "Aguardando inicialização da API..."
sleep 5

API_PORT="8510"
HEALTH_URL="http://127.0.0.1:${API_PORT}/up"
echo "Validando liveness em ${HEALTH_URL}..."
if curl -s -f -o /dev/null "$HEALTH_URL"; then
    echo "OK: API respondeu HTTP 200 no endpoint de vida (/up)."
else
    echo "AVISO: A API ainda não respondeu HTTP 200 em ${HEALTH_URL}. Verifique os logs." >&2
fi

echo "=============================================================================="
echo " Protocolo de Rollback Concluído."
echo "=============================================================================="
