# syntax=docker/dockerfile:1

# =============================================================================
# Backend Laravel — build multi-stage con DOS targets:
#
#   vendor   (etapa intermedia)  Composer instala dependencias. NO llega a producción.
#   backend  (target)            PHP-FPM con el código y solo vendor/ de la etapa anterior.
#   nginx    (target)            Nginx proxy inverso + solo los archivos estáticos de public/.
#
# docker-compose construye `backend` y `nginx` desde este mismo Dockerfile.
# =============================================================================
ARG PHP_VERSION=8.2
ARG NGINX_VERSION=1.27

# ---------- Etapa 1: dependencias de Composer ----------
FROM composer:2 AS vendor
WORKDIR /app
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

# Capa cacheable: solo se invalida si cambian composer.json / composer.lock.
# (composer.lock* con asterisco: el build no falla si el lock aún no existe.)
COPY composer.json composer.lock* ./
RUN --mount=type=cache,target=/tmp/composer-cache \
    composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-progress

# Con el código ya presente, se genera el autoloader optimizado.
# --no-scripts: `artisan package:discover` se ejecuta en la imagen final, con el PHP real de producción.
COPY . .
RUN composer dump-autoload --optimize --no-dev --no-scripts


# ---------- Target: backend (PHP-FPM) ----------
FROM php:${PHP_VERSION}-fpm-alpine AS backend

# La imagen oficial ya trae compilado: mbstring, openssl, tokenizer, xml, ctype, json, curl, fileinfo...
# Solo hay que añadir pdo_mysql (acceso a MySQL) y opcache (rendimiento).
# bash lo necesita el entrypoint. Sin git/curl/unzip/composer: no hacen falta para ejecutar.
RUN apk add --no-cache bash \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql opcache \
    && php -r 'foreach (["pdo_mysql","mbstring","openssl","tokenizer","xml","ctype","json"] as $e) { if (!extension_loaded($e)) { fwrite(STDERR, "Falta la extensión PHP: $e\n"); exit(1); } }'

COPY docker/php/php.ini /usr/local/etc/php/conf.d/99-app.ini
COPY docker/php/fpm-env.conf /usr/local/etc/php-fpm.d/zz-env.conf
COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
# Defensivo: si Git en Windows convirtió el script a CRLF, lo normalizamos a LF.
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html

# Solo la carpeta vendor/ de la etapa de build (capa estable: cambia poco).
COPY --from=vendor /app/vendor ./vendor
# Luego el código (capa que cambia seguido, por eso va después).
COPY . .

RUN mkdir -p storage/app/public storage/api-docs storage/logs \
             storage/framework/cache storage/framework/sessions storage/framework/views \
             bootstrap/cache \
    && php artisan package:discover --ansi \
    && chown -R www-data:www-data storage bootstrap/cache

EXPOSE 9000
ENTRYPOINT ["entrypoint.sh"]
CMD ["php-fpm"]


# ---------- Target: nginx (proxy inverso) ----------
FROM nginx:${NGINX_VERSION}-alpine AS nginx
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
# Nginx solo necesita public/ (estáticos); el PHP lo ejecuta el contenedor `backend`.
COPY public /var/www/html/public
EXPOSE 80
