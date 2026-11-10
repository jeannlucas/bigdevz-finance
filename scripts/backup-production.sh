#!/bin/bash
# ==============================================================================
# BigDev.Z Finance — Script de Backup Automático e Retenção para Produção
# Alinhado à topologia real da VPS (PostgreSQL 17 Alpine - Base: bigdevz_finance)
# Formato: pg_dump custom (-Fc) com cálculo de checksum SHA-256 e rotação.
# Uso: ./scripts/backup-production.sh [diretorio_destino] [dias_retencao]
# ==============================================================================
set -euo pipefail

BACKUP_DIR="${1:-storage/backups/production}"
RETENTION_DAYS="${2:-30}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/prod_backup_${TIMESTAMP}.dump"
CHECKSUM_FILE="${BACKUP_FILE}.sha256"

mkdir -p "$BACKUP_DIR"

echo "=== [1/3] Gerando Backup Consistente do PostgreSQL 17 (bigdevz_finance) ==="

DB_USER="${DB_USERNAME:-bigdevz}"
DB_NAME="${DB_DATABASE:-bigdevz_finance}"

# Localiza o container ativo (seja por nome direto ou via compose)
CONTAINER_PG=""
if docker ps --format '{{.Names}}' | grep -q '^bigdevz-finance-postgres-1$'; then
    CONTAINER_PG="bigdevz-finance-postgres-1"
elif docker ps --format '{{.Names}}' | grep -q 'postgres'; then
    CONTAINER_PG=$(docker ps --format '{{.Names}}' | grep 'postgres' | head -n1)
fi

if [ -z "$CONTAINER_PG" ]; then
    echo "ERRO FATAL: Container PostgreSQL não está em execução!" >&2
    exit 1
fi

echo "Executando pg_dump no container '$CONTAINER_PG' para a base '$DB_NAME'..."
docker exec -i "$CONTAINER_PG" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc --no-owner --no-acl > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
    echo "ERRO: Falha ao gerar arquivo de backup ou arquivo gerado está vazio!" >&2
    rm -f "$BACKUP_FILE"
    exit 1
fi

echo "=== [2/3] Gerando Checksum de Integridade (SHA-256) ==="
if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$BACKUP_FILE" > "$CHECKSUM_FILE"
elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$BACKUP_FILE" > "$CHECKSUM_FILE"
else
    echo "Aviso: Utilitário sha256sum/shasum não disponível no host."
fi

SIZE_MB=$(du -m "$BACKUP_FILE" | cut -f1)
echo "Backup gerado com sucesso:"
echo "Arquivo:  $BACKUP_FILE (${SIZE_MB} MB)"
if [ -f "$CHECKSUM_FILE" ]; then
    echo "Checksum: $(cat "$CHECKSUM_FILE")"
fi

echo "=== [3/3] Aplicando Política de Retenção ($RETENTION_DAYS dias) ==="
find "$BACKUP_DIR" -type f \( -name "prod_backup_*.dump" -o -name "prod_backup_*.sha256" \) -mtime +"$RETENTION_DAYS" -exec rm -v {} \; || true
echo "Limpeza de retenção concluída."
