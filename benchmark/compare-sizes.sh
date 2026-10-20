#!/usr/bin/env bash
# Compara tamaño y tiempo de build (SIN caché) de los Dockerfiles "antes" y "después".
# Uso, desde la raíz del repo:   bash benchmark/compare-sizes.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export DOCKER_BUILDKIT=1

measure() {
    local tag=$1; shift
    local start=$SECONDS
    docker build --no-cache -q -t "$tag" "$@" >/dev/null
    local secs=$((SECONDS - start))
    local bytes; bytes=$(docker image inspect "$tag" --format '{{.Size}}')
    printf '%-32s %8s MB %8ss\n' "$tag" "$((bytes / 1024 / 1024))" "$secs"
}

# El "antes" del frontend usa `next start`, que no admite output: "standalone".
# Se construye desde una copia temporal sin esa línea para que sea una comparación válida.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -r frontend "$tmp/fe"
sed -i '/output:/d' "$tmp/fe/next.config.ts"

printf '%-32s %11s %9s\n' "IMAGEN" "TAMAÑO" "BUILD"
echo "------------------------------------------------------------"
measure ecommerce-frontend:before -f benchmark/Dockerfile.frontend.before "$tmp/fe"
measure ecommerce-frontend:after  frontend
measure ecommerce-backend:before  -f benchmark/Dockerfile.backend.before backend
measure ecommerce-backend:after   --target backend backend
measure ecommerce-nginx:after     --target nginx backend
echo "------------------------------------------------------------"
echo "Copia esta tabla en la sección 'Resultados' del README."
