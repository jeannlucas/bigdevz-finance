FROM php:8.3-cli-alpine

RUN apk add --no-cache postgresql-dev icu-dev \
    && docker-php-ext-install pdo_pgsql intl bcmath

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app
COPY docker/entrypoint.sh /usr/local/bin/bigdevz-entrypoint
RUN chmod +x /usr/local/bin/bigdevz-entrypoint

EXPOSE 8000
ENTRYPOINT ["bigdevz-entrypoint"]
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000"]
