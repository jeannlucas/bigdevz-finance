#!/bin/sh
# Desenvolvimento apenas. Nenhum segredo é gravado em disco por este script.
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

exec "$@"
