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
RELEASE_TAG=""
BUILD_NUMBER=""

for arg in "$@"; do
    case "$arg" in
        --env=*) ENV="${arg#*=}" ;;
        --release-tag=*) RELEASE_TAG="${arg#*=}" ;;
        --build-number=*) BUILD_NUMBER="${arg#*=}" ;;
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

PACKAGE_VERSION="$(awk '/^version: / {print $2; exit}' "$MOBILE_DIR/pubspec.yaml")"
APP_VERSION="${PACKAGE_VERSION%%+*}"
BUILD_NUMBER="${BUILD_NUMBER:-${PACKAGE_VERSION#*+}}"

if [[ "$ENV" == "production" && -z "$RELEASE_TAG" ]]; then
    RELEASE_TAG="$(git -C "$PROJECT_ROOT" describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || true)"
fi
if [[ -n "$RELEASE_TAG" || "$ENV" == "production" ]]; then
    if ! [[ "$RELEASE_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        echo "Informe uma tag SemVer válida em --release-tag=vX.Y.Z."
        exit 1
    fi
    APP_VERSION="${RELEASE_TAG#v}"
fi
if ! [[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "O número do build precisa ser um inteiro positivo."
    exit 1
fi

echo "Configuração validada:"
echo " - APP_ENV: $ENV"
echo " - API_BASE_URL: $API_URL"

cd "$MOBILE_DIR"
flutter pub get --enforce-lockfile

echo "Compilando Flutter Web em modo release..."
flutter build web --release \
    --build-name="$APP_VERSION" \
    --build-number="$BUILD_NUMBER" \
    --dart-define="APP_VERSION=$APP_VERSION" \
    --dart-define="APP_BUILD=$BUILD_NUMBER" \
    --dart-define="APP_ENV=${ENV}" \
    --dart-define="API_BASE_URL=${API_URL}"

# O Caddy mantém /assets/ imutável. A fonte Material pode mudar com o subset
# gerado pelo compilador, por isso cada conjunto recebe uma URL por conteúdo.
(
    cd build/web
    asset_hash="$(find assets -path assets/releases -prune -o -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | cut -d ' ' -f 1)"
    test "${#asset_hash}" -eq 64
    asset_base="assets/releases/$asset_hash"
    temp_assets="$(mktemp -d)"
    trap 'rm -rf "$temp_assets"' EXIT
    rm -rf assets/releases
    cp -R assets "$temp_assets/assets"
    mkdir -p "$asset_base"
    mv "$temp_assets/assets" "$asset_base/assets"
    sed "s|<head>|<head><meta name=\"finance-assets-base\" content=\"$asset_base/\">|" index.html > index.versioned.html
    grep -q 'name="finance-assets-base"' index.versioned.html
    mv index.versioned.html index.html
)

echo "=============================================================================="
echo " OK: Bundle Flutter Web compilado com sucesso para ambiente '$ENV'!"
echo " Diretório: apps/mobile/build/web"
echo "=============================================================================="
