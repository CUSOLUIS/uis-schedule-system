#!/usr/bin/env bash
# Respaldo verificable de scheduleDB (PostgreSQL) desde el contenedor `postgres`
# del docker-compose.yml raíz. Lo usan los workflows de despliegue antes de
# reconstruir contenedores y también se puede ejecutar a mano.
#
# Uso:
#   ./scripts/db-backup.sh
#
# Variables de entorno:
#   ENV_FILE          Archivo con DB_NAME y DB_USERNAME (por defecto: .env de la
#                     raíz o, si no existe, uis-schedule-system-backend/backend/.env).
#                     Si no hay ninguno, se toman POSTGRES_DB y POSTGRES_USER del contenedor.
#   DB_CONTAINER      Contenedor de PostgreSQL (por defecto: postgres)
#   BACKUP_DIR        Carpeta de los respaldos, fuera del volumen de la base y de
#                     los checkouts (por defecto: /home/dev/backups/scheduleDB)
#   BACKUP_RETENTION  Cantidad de respaldos que se conservan (por defecto: 7)
#   ALLOW_NO_DB       1 = si el contenedor no está corriendo, termina sin error
#                     (solo para un primer despliegue sin base)
#
# Termina con error si el dump falla, queda vacío o no es legible por
# pg_restore: un respaldo inválido nunca se presenta como correcto.
# Nunca imprime credenciales ni contenido del respaldo.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -z "${ENV_FILE:-}" ]; then
  ENV_FILE="$ROOT_DIR/.env"
  [ -f "$ENV_FILE" ] || ENV_FILE="$ROOT_DIR/uis-schedule-system-backend/backend/.env"
fi
DB_CONTAINER="${DB_CONTAINER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-/home/dev/backups/scheduleDB}"
BACKUP_RETENTION="${BACKUP_RETENTION:-7}"
ALLOW_NO_DB="${ALLOW_NO_DB:-0}"

log() { echo "[db-backup] $*"; }
fail() { echo "[db-backup] ERROR: $*" >&2; exit 1; }

# Lee una sola clave del .env sin ejecutarlo (source correría cualquier comando
# y exportaría también la contraseña).
read_env_var() {
  local key="$1" value
  value="$(grep -E "^[[:space:]]*${key}=" "$ENV_FILE" | tail -n1 | cut -d= -f2- | tr -d '\r')" || true
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "$value"
}

[[ "$BACKUP_RETENTION" =~ ^[1-9][0-9]*$ ]] || fail "BACKUP_RETENTION debe ser un entero positivo"

if ! docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  if [ "$ALLOW_NO_DB" = "1" ]; then
    log "El contenedor '$DB_CONTAINER' no está corriendo y ALLOW_NO_DB=1: no se genera respaldo."
    exit 0
  fi
  fail "el contenedor '$DB_CONTAINER' no está corriendo; no se puede respaldar. Si es el primer despliegue, ejecutar con ALLOW_NO_DB=1."
fi

# Sin .env (p. ej. el checkout limpio del runner) se usan las variables con las
# que se creó el contenedor; la contraseña no hace falta para pg_dump local.
if [ -f "$ENV_FILE" ]; then
  DB_NAME="$(read_env_var DB_NAME)"
  DB_USERNAME="$(read_env_var DB_USERNAME)"
  ORIGEN="$ENV_FILE"
else
  DB_NAME="$(docker exec "$DB_CONTAINER" printenv POSTGRES_DB || true)"
  DB_USERNAME="$(docker exec "$DB_CONTAINER" printenv POSTGRES_USER || true)"
  ORIGEN="el entorno del contenedor '$DB_CONTAINER'"
fi
[ -n "$DB_NAME" ] || fail "no se encontró el nombre de la base en $ORIGEN"
[ -n "$DB_USERNAME" ] || fail "no se encontró el usuario de la base en $ORIGEN"

# Los respaldos contienen datos de la base: solo los lee el dueño.
umask 077
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR" 2>/dev/null || true

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_NAME="scheduleDB_${TIMESTAMP}.dump"
CONTAINER_TMP="/tmp/${DUMP_NAME}.partial"
LOCAL_TMP="$BACKUP_DIR/${DUMP_NAME}.partial"

# Si algo falla, no quedan archivos a medias que parezcan respaldos.
cleanup() {
  docker exec "$DB_CONTAINER" rm -f "$CONTAINER_TMP" >/dev/null 2>&1 || true
  rm -f "$LOCAL_TMP"
}
trap cleanup EXIT

log "Generando dump de '$DB_NAME' desde el contenedor '$DB_CONTAINER'..."
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USERNAME" -F c -f "$CONTAINER_TMP" "$DB_NAME" \
  || fail "pg_dump falló; no se generó respaldo."

docker exec "$DB_CONTAINER" pg_restore --list "$CONTAINER_TMP" >/dev/null 2>&1 \
  || fail "el dump generado no es legible por pg_restore; se descarta."

docker cp "$DB_CONTAINER:$CONTAINER_TMP" "$LOCAL_TMP" >/dev/null \
  || fail "no se pudo copiar el dump fuera del contenedor."

[ -s "$LOCAL_TMP" ] || fail "el archivo de respaldo quedó vacío; se descarta."

# docker cp conserva los permisos del contenedor; umask no aplica aquí.
chmod 600 "$LOCAL_TMP"
mv "$LOCAL_TMP" "$BACKUP_DIR/$DUMP_NAME"
(cd "$BACKUP_DIR" && sha256sum "$DUMP_NAME" > "$DUMP_NAME.sha256")

SIZE="$(wc -c < "$BACKUP_DIR/$DUMP_NAME" | tr -d ' ')"
CHECKSUM="$(cut -d' ' -f1 "$BACKUP_DIR/$DUMP_NAME.sha256")"
log "Respaldo creado: $BACKUP_DIR/$DUMP_NAME"
log "Tamaño: $SIZE bytes"
log "SHA-256: $CHECKSUM"

# Rotación: solo después de un respaldo correcto, y cada dump con su checksum.
mapfile -t DUMPS < <(ls -1t "$BACKUP_DIR"/scheduleDB_*.dump 2>/dev/null)
if [ "${#DUMPS[@]}" -gt "$BACKUP_RETENTION" ]; then
  log "Rotando respaldos antiguos (se conservan $BACKUP_RETENTION de ${#DUMPS[@]})..."
  for old_dump in "${DUMPS[@]:$BACKUP_RETENTION}"; do
    log "Eliminando $old_dump"
    rm -f "$old_dump" "$old_dump.sha256"
  done
fi

log "Listo."
