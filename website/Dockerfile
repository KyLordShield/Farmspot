# ---------------------------------------------------------------------------
# Stage 1 — Build the admin web assets (Blade + Vite/Tailwind).
# ---------------------------------------------------------------------------
FROM node:22-alpine AS assets
WORKDIR /build
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2 — Install PHP dependencies.
# ---------------------------------------------------------------------------
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader \
        --ignore-platform-req=ext-fileinfo --ignore-platform-req=ext-intl
COPY . .
RUN composer install --no-dev --optimize-autoloader \
        --ignore-platform-req=ext-fileinfo --ignore-platform-req=ext-intl

# ---------------------------------------------------------------------------
# Stage 3 — Runtime: PHP 8.3 + Laravel.
#
# Demo-grade: uses Laravel's built-in server (one process, fine for a single
# demo instance). Swap for nginx/php-fpm or RoadRunner later if you ever need
# real traffic.
# ---------------------------------------------------------------------------
FROM php:8.3-cli-alpine

RUN apk add --no-cache oniguruma-dev libzip-dev icu-dev \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql mysqli mbstring fileinfo

WORKDIR /app

COPY --from=vendor /app /app
COPY --from=assets /build/public/build public/build

# Aiven requires TLS. This public CA bundle lets PDO verify the cloud DB cert
# (see MYSQL_ATTR_SSL_CA in render.yaml).
COPY storage/aiven-ca.pem storage/aiven-ca.pem

RUN mkdir -p bootstrap/cache \
        storage/logs \
        storage/framework/cache \
        storage/framework/sessions \
        storage/framework/views \
    && chmod -R ug+rw storage bootstrap/cache

COPY start.sh /app/start.sh

EXPOSE 8000
CMD ["sh", "/app/start.sh"]