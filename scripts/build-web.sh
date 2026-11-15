#!/bin/bash
# ==============================================================================
# BigDev.Z Finance — Script Padronizado de Build do Frontend Flutter Web
# Uso:
#   ./scripts/build-web.sh --env=local
#   ./scripts/build-web.sh --env=staging
#   ./scripts/build-web.sh --env=production
# ==============================================================================
set -euo pipefail

ENV="local"
CUSTOM_API_URL=""

for arg in "$@"; do
    case "$arg" in
        --env=*) ENV="${arg#*=}" ;;
        --api-url=*) CUSTOM_API_URL="${arg#*=}" ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MOBILE_DIR="${PROJECT_ROOT}/apps/mobile"

echo "=============================================================================="
echo " BUILD FLUTTER WEB — BIGDEV.Z FINANCE"
echo " Ambiente Selecionado: $ENV"
echo "=============================================================================="

API_URL=""
PWA_FLAGS=""

case "$ENV" in
    local|dev|development)
        ENV="local"
        API_URL="${CUSTOM_API_URL:-http://127.0.0.1:8000/api}"
        if [[ "$API_URL" == *"finance.bigdevz.com"* ]]; then
            echo "ERRO FATAL DE SEGURANÇA: Build local não pode apontar para o domínio de produção!" >&2
            exit 1
        fi
        # No ambiente local, endpoint padrão é a API local
        ;;
    staging|hml|homolog)
        ENV="staging"
        API_URL="${CUSTOM_API_URL:-https://staging-finance.bigdevz.com/api}"
        if [[ "$API_URL" == *"finance.bigdevz.com"* ]] && [[ "$API_URL" != *"staging"* ]]; then
            echo "ERRO FATAL DE SEGURANÇA: Build de homologação não pode apontar para produção!" >&2
            exit 1
        fi
        ;;
    production|prod)
        ENV="production"
        API_URL="${CUSTOM_API_URL:-https://finance.bigdevz.com/api}"
        if [[ "$API_URL" == *"localhost"* ]] || [[ "$API_URL" == *"127.0.0.1"* ]] || [[ "$API_URL" == *"10.0.2.2"* ]] || [[ "$API_URL" == *":8000"* ]]; then
            echo "ERRO FATAL DE SEGURANÇA: Build de produção não pode conter endereços locais de desenvolvimento!" >&2
            exit 1
        fi
        if [[ "$API_URL" == "http://"* ]]; then
            echo "ERRO FATAL DE SEGURANÇA: Build de produção exige transporte seguro via HTTPS!" >&2
            exit 1
        fi
        ;;
    *)
        echo "ERRO: Ambiente inválido '$ENV'. Use 'local', 'staging' ou 'production'." >&2
        exit 1
        ;;
esac

echo "Configuração validada:"
echo " - APP_ENV: $ENV"
echo " - API_BASE_URL: $API_URL"

cd "$MOBILE_DIR"
flutter pub get --enforce-lockfile

echo "Compilando Flutter Web em modo release..."
flutter build web --release \
    --dart-define="APP_ENV=${ENV}" \
    --dart-define="API_BASE_URL=${API_URL}"

echo "=============================================================================="
echo " OK: Bundle Flutter Web compilado com sucesso para ambiente '$ENV'!"
echo " Diretório: apps/mobile/build/web"
echo "=============================================================================="
