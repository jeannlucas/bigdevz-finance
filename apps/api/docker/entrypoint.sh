#!/bin/sh
# Inicialização do runtime da API e dos comandos Artisan.
set -eu

if [ ! -f vendor/autoload.php ]; then
    composer install --no-interaction --prefer-dist
fi

# Sem .env local, usa uma chave efêmera só em memória. A API autentica por
# token Sanctum e não depende de dados criptografados com APP_KEY.
if [ -z "${APP_KEY:-}" ] && ! grep -qs '^APP_KEY=base64:' .env; then
    APP_KEY="base64:$(php -r 'echo base64_encode(random_bytes(32));')"
    export APP_KEY
fi

# O volume /app preserva bootstrap/cache entre releases.
if [ "${APP_ENV:-}" = production ] && [ "${1:-}" = php ] &&
    [ "${2:-}" = artisan ] && [ "${3:-}" = serve ]; then
    php artisan route:cache
fi

exec "$@"
