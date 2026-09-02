#!/usr/bin/env bash
# Respaldo de la base de datos scheduleDB (Postgres) corriendo en el
# contenedor Docker `postgres` del docker-compose.yml raíz.
#
# Uso:
#   ./scripts/db-backup.sh
#
# Variables de entorno configurables:
#   ENV_FILE          Archivo con DB_NAME/DB_USERNAME/DB_PASSWORD (default: ./.env)
#   DB_CONTAINER       Nombre del contenedor Postgres (default: postgres)
#   BACKUP_DIR         Carpeta donde se guardan los dumps (default: ./backups)
#   BACKUP_RETENTION   Cantidad de dumps a conservar (default: 7)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
DB_CONTAINER="${DB_CONTAINER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"

if [ ! -f "$ENV_FILE" ]; then
  echo "[db-backup] No se encontró el archivo de entorno: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

: "${DB_NAME:?DB_NAME no está definido en $ENV_FILE}"
: "${DB_USERNAME:?DB_USERNAME no está definido en $ENV_FILE}"

if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  echo "[db-backup] El contenedor '$DB_CONTAINER' no está corriendo; no hay nada que respaldar (probablemente es el primer despliegue). Saltando."
  exit 0
fi

mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_NAME="scheduleDB_${TIMESTAMP}.dump"
CONTAINER_TMP="/tmp/${DUMP_NAME}"

echo "[db-backup] Generando dump de '$DB_NAME' desde el contenedor '$DB_CONTAINER'..."
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USERNAME" -F c -f "$CONTAINER_TMP" "$DB_NAME"

docker cp "$DB_CONTAINER:$CONTAINER_TMP" "$BACKUP_DIR/$DUMP_NAME"
docker exec "$DB_CONTAINER" rm -f "$CONTAINER_TMP"

echo "[db-backup] Respaldo creado: $BACKUP_DIR/$DUMP_NAME"

# Rotación: conservar sólo los últimos BACKUP_RETENTION dumps
mapfile -t DUMPS < <(ls -1t "$BACKUP_DIR"/scheduleDB_*.dump 2>/dev/null)
if [ "${#DUMPS[@]}" -gt "$BACKUP_RETENTION" ]; then
  echo "[db-backup] Rotando dumps antiguos (conservando los últimos $BACKUP_RETENTION de ${#DUMPS[@]})..."
  for old_dump in "${DUMPS[@]:$BACKUP_RETENTION}"; do
    echo "[db-backup] Eliminando $old_dump"
    rm -f "$old_dump"
  done
fi

echo "[db-backup] Listo."
