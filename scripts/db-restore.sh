#!/usr/bin/env bash
# Restauración de la base de datos scheduleDB (Postgres) a partir de un
# dump generado por scripts/db-backup.sh.
#
# Operación DESTRUCTIVA: reemplaza el contenido actual de la base de datos.
# Uso manual / disaster-recovery, no se ejecuta automáticamente en CI/CD.
#
# Uso:
#   ./scripts/db-restore.sh <archivo.dump|latest> --yes
#
# Sin --yes, sólo muestra qué haría (dry-run).
#
# Variables de entorno configurables:
#   ENV_FILE       Archivo con DB_NAME/DB_USERNAME/DB_PASSWORD (default: ./.env)
#   DB_CONTAINER   Nombre del contenedor Postgres (default: postgres)
#   BACKUP_DIR     Carpeta donde están los dumps (default: ./backups)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
DB_CONTAINER="${DB_CONTAINER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"

DUMP_ARG="${1:-}"
CONFIRM="${2:-}"

if [ -z "$DUMP_ARG" ]; then
  echo "Uso: $0 <archivo.dump|latest> [--yes]" >&2
  exit 1
fi

if [ "$DUMP_ARG" = "latest" ]; then
  DUMP_FILE="$(ls -1t "$BACKUP_DIR"/scheduleDB_*.dump 2>/dev/null | head -n1)"
  if [ -z "$DUMP_FILE" ]; then
    echo "[db-restore] No se encontraron dumps en $BACKUP_DIR" >&2
    exit 1
  fi
else
  DUMP_FILE="$DUMP_ARG"
fi

if [ ! -f "$DUMP_FILE" ]; then
  echo "[db-restore] No existe el archivo de dump: $DUMP_FILE" >&2
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "[db-restore] No se encontró el archivo de entorno: $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

: "${DB_NAME:?DB_NAME no está definido en $ENV_FILE}"
: "${DB_USERNAME:?DB_USERNAME no está definido en $ENV_FILE}"

if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  echo "[db-restore] El contenedor '$DB_CONTAINER' no está corriendo." >&2
  exit 1
fi

echo "[db-restore] Se restaurará '$DUMP_FILE' sobre la base de datos '$DB_NAME' en el contenedor '$DB_CONTAINER'."
echo "[db-restore] Esto SOBRESCRIBE los datos actuales de '$DB_NAME'."

if [ "$CONFIRM" != "--yes" ]; then
  echo "[db-restore] Dry-run (no se ejecutó nada). Vuelve a correr con --yes para confirmar la restauración."
  exit 0
fi

CONTAINER_TMP="/tmp/$(basename "$DUMP_FILE")"
docker cp "$DUMP_FILE" "$DB_CONTAINER:$CONTAINER_TMP"

echo "[db-restore] Restaurando..."
docker exec "$DB_CONTAINER" pg_restore -U "$DB_USERNAME" -d "$DB_NAME" --clean --if-exists "$CONTAINER_TMP"
docker exec "$DB_CONTAINER" rm -f "$CONTAINER_TMP"

echo "[db-restore] Restauración completada."
