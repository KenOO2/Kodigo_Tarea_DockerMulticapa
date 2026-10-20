#!/usr/bin/env bash
set -e
cd /var/www/html

log() { echo ">> $*"; }

# --- 1. Sanear variables de entorno (fix CRLF de Windows) ---------------------
# Si el .env de la raíz se guardó con saltos de línea CRLF, algunas variables
# pueden llegar con un "\r" pegado al final (p. ej. DB_PASSWORD="abc\r") y la
# conexión a MySQL falla en silencio. Aquí se limpian todas antes de usarlas.
while IFS='=' read -r name value; do
    case "$name" in
        ''|*[!a-zA-Z0-9_]*) continue ;;
    esac
    cleaned="${value%$'\r'}"
    if [ "$cleaned" != "$value" ]; then
        export "$name=$cleaned"
    fi
done < <(env)

export DB_HOST="${DB_HOST:-db}" DB_PORT="${DB_PORT:-3306}"

# --- 2. Esperar a MySQL (con las credenciales reales) ------------------------
log "Esperando a MySQL (${DB_HOST}:${DB_PORT})..."
attempts=0
max_attempts=60
until php -r '
    try {
        new PDO(
            "mysql:host=" . getenv("DB_HOST") . ";port=" . getenv("DB_PORT") . ";dbname=" . getenv("DB_DATABASE"),
            getenv("DB_USERNAME"), getenv("DB_PASSWORD"), [PDO::ATTR_TIMEOUT => 3]
        );
    } catch (Throwable $e) { fwrite(STDERR, $e->getMessage()); exit(1); }
' 2>/tmp/db_error; do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge "$max_attempts" ]; then
        log "ERROR: no se pudo conectar a MySQL tras ${max_attempts} intentos."
        log "Último error: $(cat /tmp/db_error)"
        log "Revisa MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD en el .env (sin espacios ni comillas)."
        exit 1
    fi
    log "MySQL no disponible aún (${attempts}/${max_attempts}): $(cat /tmp/db_error)"
    sleep 2
done
log "MySQL disponible."

# --- 3. Claves de la aplicación ----------------------------------------------
# Lo correcto es definir APP_KEY y JWT_SECRET en el .env (ver README). Si faltan,
# se generan claves TEMPORALES para que el ecosistema arranque igualmente, pero
# cambiarán en cada reinicio del contenedor (invalida los tokens JWT emitidos).
if [ -z "${APP_KEY:-}" ]; then
    log "AVISO: APP_KEY vacío -> se genera una temporal. Defínela en .env para que persista."
    APP_KEY="$(php artisan key:generate --show --no-ansi | tail -n1 | tr -d '[:space:]')"
    export APP_KEY
fi
if [ -z "${JWT_SECRET:-}" ]; then
    log "AVISO: JWT_SECRET vacío -> se genera uno temporal. Defínelo en .env para que persista."
    JWT_SECRET="$(php artisan jwt:secret --show --no-ansi | tail -n1 | tr -d '[:space:]')"
    export JWT_SECRET
fi

# --- 4. Base de datos: migraciones y datos iniciales -------------------------
# La estructura de la BD vive en database/migrations (no hay .sql que mantener).
# Los seeders son idempotentes (updateOrCreate): reiniciar no duplica datos.
log "Ejecutando migraciones..."
php artisan migrate --force

if [ "${DB_SEED:-true}" = "true" ]; then
    log "Ejecutando seeders..."
    php artisan db:seed --force || log "AVISO: el seeder falló (se continúa)."
fi

# --- 5. Optimización y documentación -----------------------------------------
log "Cacheando configuración..."
php artisan config:cache

log "Generando documentación Swagger..."
php artisan l5-swagger:generate || log "AVISO: no se pudo generar Swagger (se continúa)."

# Este script corre como root; PHP-FPM atiende peticiones como www-data.
# Cualquier archivo creado arriba debe quedar escribible por www-data.
chown -R www-data:www-data storage bootstrap/cache

log "Listo. Iniciando: $*"
exec "$@"
