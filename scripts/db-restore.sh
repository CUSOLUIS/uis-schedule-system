#!/usr/bin/env bash
# Restaura un respaldo generado por scripts/db-backup.sh en un destino explícito.
# Uso manual: no lo ejecuta ningún workflow.
#
# Uso:
#   ./scripts/db-restore.sh --file <archivo.dump|latest> \
#       --target-container <contenedor> --target-db <base> \
#       [--target-user <usuario>] [--allow-operational] [--yes]
#
#   --file               Respaldo a restaurar; "latest" toma el más reciente de BACKUP_DIR.
#   --target-container   Contenedor PostgreSQL destino (obligatorio).
#   --target-db          Base destino (obligatoria); se crea si no existe.
#   --target-user        Usuario de PostgreSQL en el destino (por defecto: postgres).
#   --allow-operational  Permite restaurar en el contenedor operativo (DB_CONTAINER).
#                        Solo para una recuperación real: reemplaza los datos.
#   --yes                Ejecuta la restauración; sin él solo muestra lo que haría.
#
# Variables de entorno:
#   BACKUP_DIR     Carpeta de los respaldos (por defecto: /home/dev/backups/scheduleDB)
#   DB_CONTAINER   Contenedor operativo que se protege (por defecto: postgres)
#
# Antes de restaurar, verifica el checksum (.sha256) que generó db-backup.sh.

set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/home/dev/backups/scheduleDB}"
DB_CONTAINER="${DB_CONTAINER:-postgres}"

DUMP_ARG=""
TARGET_CONTAINER=""
TARGET_DB=""
TARGET_USER="postgres"
ALLOW_OPERATIONAL=0
CONFIRM=0

log() { echo "[db-restore] $*"; }
fail() { echo "[db-restore] ERROR: $*" >&2; exit 1; }
usage() {
  echo "Uso: $0 --file <archivo.dump|latest> --target-container <contenedor> --target-db <base> [--target-user <usuario>] [--allow-operational] [--yes]" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --file) DUMP_ARG="${2:-}"; shift 2 ;;
    --target-container) TARGET_CONTAINER="${2:-}"; shift 2 ;;
    --target-db) TARGET_DB="${2:-}"; shift 2 ;;
    --target-user) TARGET_USER="${2:-}"; shift 2 ;;
    --allow-operational) ALLOW_OPERATIONAL=1; shift ;;
    --yes) CONFIRM=1; shift ;;
    -h|--help) usage ;;
    *) echo "[db-restore] Opción desconocida: $1" >&2; usage ;;
  esac
done

[ -n "$DUMP_ARG" ] || { echo "[db-restore] Falta --file." >&2; usage; }
[ -n "$TARGET_CONTAINER" ] && [ -n "$TARGET_DB" ] \
  || { echo "[db-restore] El destino es obligatorio: --target-container y --target-db." >&2; usage; }

# Los nombres van a comandos SQL y de shell dentro del contenedor.
[[ "$TARGET_DB" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "nombre de base no válido: $TARGET_DB"
[[ "$TARGET_USER" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail "nombre de usuario no válido: $TARGET_USER"

if [ "$TARGET_CONTAINER" = "$DB_CONTAINER" ] && [ "$ALLOW_OPERATIONAL" != "1" ]; then
  fail "'$TARGET_CONTAINER' es el contenedor operativo. Para probar, restaurar en un PostgreSQL aislado; para una recuperación real, agregar --allow-operational."
fi

if [ "$DUMP_ARG" = "latest" ]; then
  DUMP_FILE="$(ls -1t "$BACKUP_DIR"/scheduleDB_*.dump 2>/dev/null | head -n1 || true)"
  [ -n "$DUMP_FILE" ] || fail "no hay respaldos en $BACKUP_DIR"
else
  DUMP_FILE="$DUMP_ARG"
fi

[ -f "$DUMP_FILE" ] || fail "no existe el archivo de respaldo: $DUMP_FILE"
[ -s "$DUMP_FILE" ] || fail "el archivo de respaldo está vacío: $DUMP_FILE"
[ -f "$DUMP_FILE.sha256" ] || fail "falta el checksum $DUMP_FILE.sha256; no se puede verificar el respaldo."
(cd "$(dirname "$DUMP_FILE")" && sha256sum --status -c "$(basename "$DUMP_FILE").sha256") \
  || fail "el checksum no coincide: el respaldo está alterado o incompleto."
log "Checksum verificado: $(basename "$DUMP_FILE")"

docker ps --format '{{.Names}}' | grep -qx "$TARGET_CONTAINER" \
  || fail "el contenedor destino '$TARGET_CONTAINER' no está corriendo."

log "Se restaurará '$DUMP_FILE' en la base '$TARGET_DB' del contenedor '$TARGET_CONTAINER'."
[ "$ALLOW_OPERATIONAL" = "1" ] && log "ATENCIÓN: destino operativo; se reemplazan sus datos."

if [ "$CONFIRM" != "1" ]; then
  log "Dry-run: no se ejecutó nada. Volver a correr con --yes para restaurar."
  exit 0
fi

CONTAINER_TMP="/tmp/restore_$(basename "$DUMP_FILE")"
trap 'docker exec "$TARGET_CONTAINER" rm -f "$CONTAINER_TMP" >/dev/null 2>&1 || true' EXIT
docker cp "$DUMP_FILE" "$TARGET_CONTAINER:$CONTAINER_TMP" >/dev/null

EXISTS="$(docker exec "$TARGET_CONTAINER" psql -U "$TARGET_USER" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname = '$TARGET_DB'")"
if [ "$EXISTS" != "1" ]; then
  log "Creando la base '$TARGET_DB'..."
  docker exec "$TARGET_CONTAINER" createdb -U "$TARGET_USER" "$TARGET_DB"
fi

log "Restaurando..."
docker exec "$TARGET_CONTAINER" pg_restore -U "$TARGET_USER" -d "$TARGET_DB" \
  --clean --if-exists --no-owner --exit-on-error "$CONTAINER_TMP" \
  || fail "pg_restore falló; revisar la salida anterior."

log "Restauración completada."
