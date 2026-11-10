#!/bin/sh
# ==============================================================================
# BigDev.Z Finance — Entrypoint de Produção Seguro
# ==============================================================================
set -eu

# Validações estritas de variáveis obrigatórias em Produção
if [ -z "${APP_KEY:-}" ]; then
    echo "ERRO FATAL: A variável de ambiente APP_KEY é estritamente obrigatória em produção." >&2
    echo "Gere uma chave com 'php artisan key:generate --show' e configure no .env.production." >&2
    exit 1
fi

if [ -z "${DB_PASSWORD:-}" ] || [ "${DB_PASSWORD:-}" = "troque-por-uma-senha-local" ]; then
    echo "ERRO FATAL: A variável DB_PASSWORD deve conter uma senha forte e exclusiva de produção." >&2
    exit 1
fi

if [ -z "${APP_URL:-}" ]; then
    echo "ERRO FATAL: A variável APP_URL é obrigatória em produção (ex: https://finance.seudominio.com.br)." >&2
    exit 1
fi

exec "$@"
