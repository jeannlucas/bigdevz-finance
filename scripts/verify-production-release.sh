#!/usr/bin/env bash
# ==============================================================================
# BigDev.Z Finance — Verificação Pública de Release de Produção (Barreira Dupla)
# Valida simultaneamente:
# 1. API pública (/api/health) com status "ok" e revisão correspondente ao SHA da release
# 2. Frontend Web público (/main.dart.js) com hash SHA-256 idêntico ao compilado
# ==============================================================================
set -euo pipefail

EXPECTED_SHA="${RELEASE_SHA:-}"
EXPECTED_WEB_HASH="${EXPECTED_WEB_HASH:-}"
API_URL="${API_URL:-https://finance.bigdevz.com/api/health}"
WEB_URL="${WEB_URL:-https://finance.bigdevz.com/main.dart.js}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"
DELAY_SECONDS="${DELAY_SECONDS:-3}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-15}"

while [ $# -gt 0 ]; do
  case "$1" in
    --expected-sha)
      EXPECTED_SHA="$2"
      shift 2
      ;;
    --expected-web-hash)
      EXPECTED_WEB_HASH="$2"
      shift 2
      ;;
    --api-url)
      API_URL="$2"
      shift 2
      ;;
    --web-url)
      WEB_URL="$2"
      shift 2
      ;;
    --max-attempts)
      MAX_ATTEMPTS="$2"
      shift 2
      ;;
    --delay)
      DELAY_SECONDS="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --help|-h)
      echo "Uso: $0 --expected-sha <SHA> --expected-web-hash <HASH> [--api-url <URL>] [--web-url <URL>]"
      exit 0
      ;;
    *)
      echo "Argumento desconhecido: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$EXPECTED_SHA" ]; then
  echo "❌ ERRO: --expected-sha não informado ou vazio." >&2
  exit 1
fi

if [ -z "$EXPECTED_WEB_HASH" ]; then
  echo "❌ ERRO: --expected-web-hash não informado ou vazio." >&2
  exit 1
fi

echo "=========================================================="
echo "  BigDev.Z Finance — Barreira de Verificação de Release   "
echo "=========================================================="
echo "Alvo API:       $API_URL"
echo "Revisão Alvo:   $EXPECTED_SHA"
echo "Alvo Web:       $WEB_URL"
echo "Hash Web Alvo:  $EXPECTED_WEB_HASH"
echo "Tentativas max: $MAX_ATTEMPTS (intervalo: ${DELAY_SECONDS}s)"
echo "=========================================================="

ATTEMPT=1
LAST_API_STATUS=""
LAST_API_REVISION=""
LAST_WEB_HASH=""
API_OK=0
WEB_OK=0

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
  echo "🔍 [Tentativa $ATTEMPT/$MAX_ATTEMPTS] Consultando endpoints públicos de produção..."

  # 1. Validação da API
  API_OK=0
  API_RAW=$(curl --fail --silent --show-error --max-time "$TIMEOUT_SECONDS" "$API_URL" 2>/dev/null || true)
  if [ -n "$API_RAW" ]; then
    LAST_API_STATUS=$(echo "$API_RAW" | jq -r '.status // empty' 2>/dev/null || true)
    LAST_API_REVISION=$(echo "$API_RAW" | jq -r '.revision // empty' 2>/dev/null || true)
    if [ "$LAST_API_STATUS" = "ok" ] && [ "$LAST_API_REVISION" = "$EXPECTED_SHA" ]; then
      API_OK=1
    fi
  fi

  # 2. Validação do Frontend Web (main.dart.js)
  WEB_OK=0
  TMP_WEB=$(mktemp -t web_check_XXXXXX 2>/dev/null || mktemp)
  if curl --fail --silent --show-error --max-time "$TIMEOUT_SECONDS" "$WEB_URL" -o "$TMP_WEB" 2>/dev/null; then
    if [ -s "$TMP_WEB" ]; then
      if command -v sha256sum >/dev/null 2>&1; then
        LAST_WEB_HASH=$(sha256sum "$TMP_WEB" | awk '{print $1}')
      else
        LAST_WEB_HASH=$(shasum -a 256 "$TMP_WEB" | awk '{print $1}')
      fi
      if [ "$LAST_WEB_HASH" = "$EXPECTED_WEB_HASH" ]; then
        WEB_OK=1
      fi
    fi
  fi
  rm -f "$TMP_WEB"

  if [ "$API_OK" -eq 1 ] && [ "$WEB_OK" -eq 1 ]; then
    echo "=========================================================="
    echo "🎉 BARREIRA DUPLA DE RELEASE APROVADA COM SUCESSO!"
    echo "=========================================================="
    echo "✅ API pública íntegra e sincronizada:"
    echo "   Status:   $LAST_API_STATUS"
    echo "   Revisão:  $LAST_API_REVISION (bate com $EXPECTED_SHA)"
    echo "✅ Frontend Web público íntegro e sincronizado:"
    echo "   SHA-256:  $LAST_WEB_HASH (bate com $EXPECTED_WEB_HASH)"
    echo "=========================================================="
    exit 0
  fi

  echo "   Estado parcial:"
  if [ "$API_OK" -eq 1 ]; then
    echo "   - API: OK (revisão $LAST_API_REVISION)"
  else
    echo "   - API: PENDENTE (status='$LAST_API_STATUS', revisão='$LAST_API_REVISION', esperado='$EXPECTED_SHA')"
  fi
  if [ "$WEB_OK" -eq 1 ]; then
    echo "   - Web: OK (hash $LAST_WEB_HASH)"
  else
    echo "   - Web: PENDENTE (hash='$LAST_WEB_HASH', esperado='$EXPECTED_WEB_HASH')"
  fi

  if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
    sleep "$DELAY_SECONDS"
  fi
  ATTEMPT=$((ATTEMPT + 1))
done

echo ""
echo "=========================================================="
echo "❌ FALHA NA BARREIRA DE RELEASE: PRODUÇÃO DIVERGENTE"
echo "=========================================================="
if [ "$API_OK" -ne 1 ]; then
  echo "❌ API pública não sincronizou com a release:"
  echo "   Endpoint: $API_URL"
  echo "   Esperado: revisão $EXPECTED_SHA com status 'ok'"
  echo "   Obtido:   status='$LAST_API_STATUS', revisão='$LAST_API_REVISION'"
fi
if [ "$WEB_OK" -ne 1 ]; then
  echo "❌ Frontend Web público (main.dart.js) não sincronizou com o build da release:"
  echo "   Endpoint: $WEB_URL"
  echo "   Esperado SHA-256: $EXPECTED_WEB_HASH"
  echo "   Obtido SHA-256:   ${LAST_WEB_HASH:-<vazio / download falhou>}"
fi
echo "=========================================================="
exit 1
