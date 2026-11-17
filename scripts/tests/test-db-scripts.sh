#!/usr/bin/env bash
# Pruebas de scripts/db-backup.sh y scripts/db-restore.sh sin Docker real:
# un `docker` falso en PATH simula el contenedor con una carpeta local.
#
# Uso: ./scripts/tests/test-db-scripts.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$TESTS_DIR/.." && pwd)"
SECRET="ClaveQueNoDebeVerse123"
PASSED=0
FAILED=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# docker falso. Variables: FAKE_ROOT, FAKE_RUNNING (nombres separados por
# espacios) y FAKE_DUMP_MODE (ok | fail | corrupt | cp-empty).
mkdir -p "$WORK/bin"
cat > "$WORK/bin/docker" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_ROOT/calls.log"
ctr_path() { echo "$FAKE_ROOT/ctr/$1$2"; }
case "$1" in
  ps) for n in $FAKE_RUNNING; do echo "$n"; done ;;
  cp)
    if [[ "$2" == *:* ]]; then
      src="$(ctr_path "${2%%:*}" "${2#*:}")"
      if [ "${FAKE_DUMP_MODE:-ok}" = "cp-empty" ]; then : > "$3"; else cp "$src" "$3"; fi
    else
      dst="$(ctr_path "${3%%:*}" "${3#*:}")"; mkdir -p "$(dirname "$dst")"; cp "$2" "$dst"
    fi ;;
  exec)
    ctr="$2"; shift 2
    case "$1" in
      pg_dump)
        out=""; while [ $# -gt 0 ]; do [ "$1" = "-f" ] && out="$2"; shift; done
        [ "${FAKE_DUMP_MODE:-ok}" = "fail" ] && { echo "pg_dump: error de conexión" >&2; exit 1; }
        f="$(ctr_path "$ctr" "$out")"; mkdir -p "$(dirname "$f")"
        if [ "${FAKE_DUMP_MODE:-ok}" = "corrupt" ]; then echo "basura" > "$f"; else echo "PGDMP datos" > "$f"; fi ;;
      pg_restore)
        path="${*: -1}"; head -c5 "$(ctr_path "$ctr" "$path")" | grep -q PGDMP ;;
      rm) rm -f "$(ctr_path "$ctr" "${*: -1}")" ;;
      psql) echo "" ;;
      printenv) [ "$1" = "printenv" ] && case "$2" in POSTGRES_DB) echo scheduleDB ;; POSTGRES_USER) echo admin ;; esac ;;
      createdb) : ;;
    esac ;;
esac
FAKE
chmod +x "$WORK/bin/docker"

# Prepara un caso limpio y exporta el entorno del docker falso.
setup() {
  CASE="$WORK/case$((PASSED + FAILED))"
  mkdir -p "$CASE/backups"
  printf 'DB_NAME=scheduleDB\nDB_USERNAME=admin\nDB_PASSWORD=%s\n' "$SECRET" > "$CASE/.env"
  : > "$CASE/calls.log"
  export PATH="$WORK/bin:$PATH" FAKE_ROOT="$CASE" FAKE_RUNNING="postgres pg-restore-test"
  export FAKE_DUMP_MODE=ok ENV_FILE="$CASE/.env" BACKUP_DIR="$CASE/backups"
  unset ALLOW_NO_DB BACKUP_RETENTION
}

check() {
  local name="$1"; shift
  if "$@"; then PASSED=$((PASSED + 1)); echo "ok   - $name"
  else FAILED=$((FAILED + 1)); echo "FAIL - $name"; fi
}

dumps() { ls "$BACKUP_DIR"/scheduleDB_*.dump 2>/dev/null | wc -l | tr -d ' '; }
partials() { ls "$BACKUP_DIR"/*.partial 2>/dev/null | wc -l | tr -d ' '; }
backup() { "$SCRIPTS_DIR/db-backup.sh" > "$CASE/out.log" 2>&1; }
restore() { "$SCRIPTS_DIR/db-restore.sh" "$@" > "$CASE/out.log" 2>&1; }

# --- db-backup.sh ---
setup; backup; rc=$?
check "respaldo correcto deja dump no vacío y checksum válido" \
  bash -c "[ $rc -eq 0 ] && [ $(dumps) -eq 1 ] && cd '$BACKUP_DIR' && sha256sum --status -c scheduleDB_*.dump.sha256"
check "la salida y los comandos no exponen la contraseña" \
  bash -c "! grep -q '$SECRET' '$CASE/out.log' '$CASE/calls.log'"

setup; ENV_FILE="$CASE/no-existe.env" backup; rc=$?
check "sin .env toma base y usuario del contenedor" \
  bash -c "[ $rc -eq 0 ] && [ $(dumps) -eq 1 ] && grep -q 'pg_dump -U admin .* scheduleDB' '$CASE/calls.log'"

setup; FAKE_DUMP_MODE=fail backup; rc=$?
check "fallo de pg_dump termina con error y no deja respaldo" \
  bash -c "[ $rc -ne 0 ] && [ $(dumps) -eq 0 ] && [ $(partials) -eq 0 ]"

setup; FAKE_DUMP_MODE=corrupt backup; rc=$?
check "dump ilegible por pg_restore se descarta" bash -c "[ $rc -ne 0 ] && [ $(dumps) -eq 0 ]"

setup; FAKE_DUMP_MODE=cp-empty backup; rc=$?
check "archivo vacío se descarta" bash -c "[ $rc -ne 0 ] && [ $(dumps) -eq 0 ] && [ $(partials) -eq 0 ]"

setup; FAKE_RUNNING="" backup; rc=$?
check "contenedor detenido termina con error" bash -c "[ $rc -ne 0 ]"

setup; FAKE_RUNNING="" ALLOW_NO_DB=1 backup; rc=$?
check "contenedor detenido con ALLOW_NO_DB=1 termina sin error y sin respaldo" \
  bash -c "[ $rc -eq 0 ] && [ $(dumps) -eq 0 ]"

setup
for i in 1 2 3; do
  touch -d "-$i hour" "$BACKUP_DIR/scheduleDB_2000010${i}_000000.dump" "$BACKUP_DIR/scheduleDB_2000010${i}_000000.dump.sha256"
done
BACKUP_RETENTION=2 backup; rc=$?
check "la rotación conserva BACKUP_RETENTION respaldos y borra sus checksums" \
  bash -c "[ $rc -eq 0 ] && [ $(dumps) -eq 2 ] && [ \$(ls '$BACKUP_DIR'/*.sha256 | wc -l) -eq 2 ]"

# --- db-restore.sh ---
setup; backup
DUMP="$(ls "$BACKUP_DIR"/scheduleDB_*.dump)"

restore --file "$DUMP" --yes; rc=$?
check "restaurar sin destino explícito aborta" bash -c "[ $rc -ne 0 ] && ! grep -q 'pg_restore -U' '$CASE/calls.log'"

restore --file "$DUMP" --target-container postgres --target-db scheduleDB --yes; rc=$?
check "restaurar en el contenedor operativo sin --allow-operational aborta" \
  bash -c "[ $rc -ne 0 ] && ! grep -q 'pg_restore -U' '$CASE/calls.log'"

restore --file latest --target-container pg-restore-test --target-db scheduleDB; rc=$?
check "sin --yes solo hace dry-run" bash -c "[ $rc -eq 0 ] && ! grep -q 'pg_restore -U' '$CASE/calls.log'"

restore --file latest --target-container pg-restore-test --target-db scheduleDB --yes; rc=$?
check "restauración en destino aislado ejecuta pg_restore en ese destino" \
  bash -c "[ $rc -eq 0 ] && grep -q 'exec pg-restore-test pg_restore -U postgres -d scheduleDB' '$CASE/calls.log'"

restore --file latest --target-container pg-restore-test --target-db "x; DROP" --yes; rc=$?
check "nombre de base no válido aborta" bash -c "[ $rc -ne 0 ]"

echo "alterado" >> "$DUMP"
restore --file "$DUMP" --target-container pg-restore-test --target-db scheduleDB --yes; rc=$?
check "checksum alterado aborta" bash -c "[ $rc -ne 0 ] && grep -q 'checksum no coincide' '$CASE/out.log'"

echo
echo "Pruebas: $PASSED correctas, $FAILED fallidas."
[ "$FAILED" -eq 0 ]
