# Multi-stage build: extração de ferramentas do composer
FROM composer:2 AS composer-bin

# Imagem final de runtime
FROM php:8.3-cli-alpine
LABEL com.bigdevz.project="finance" com.bigdevz.service="api"

RUN apk add --no-cache postgresql-dev icu-dev \
    && docker-php-ext-install pdo_pgsql intl bcmath

COPY --from=composer-bin /usr/bin/composer /usr/bin/composer

# Usuário não-root para execução sem privilégios administrativos
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -s /bin/sh -D appuser

WORKDIR /app

COPY docker/entrypoint.sh /usr/local/bin/bigdevz-entrypoint
RUN chmod +x /usr/local/bin/bigdevz-entrypoint

USER appuser

EXPOSE 8000
ENTRYPOINT ["bigdevz-entrypoint"]
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000"]

