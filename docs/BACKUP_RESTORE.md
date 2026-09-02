# Respaldo y restauración de scheduleDB

## Resumen

Antes de cualquier despliegue que pueda aplicar migraciones de Flyway
(arranque del contenedor `backend-spring-api`), el pipeline de CI/CD genera
automáticamente un respaldo (`pg_dump`, formato custom) de la base de datos
`scheduleDB`. Los dumps se guardan localmente en el Raspberry Pi de
despliegue, con rotación automática que conserva sólo los últimos N.

Los scripts viven en la raíz del monorepo:

- `scripts/db-backup.sh` — genera el respaldo (se ejecuta automáticamente).
- `scripts/db-restore.sh` — restaura un respaldo (uso manual, requiere confirmación explícita).

## Prerrequisitos

- El contenedor Docker `postgres` (definido en `docker-compose.yml` raíz) debe estar corriendo.
- Debe existir un archivo `.env` en la raíz con `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` (mismo `.env` que usa `docker-compose.yml`).
- Docker CLI disponible en la máquina que ejecuta el script.

## Respaldo automático en el pipeline

El respaldo se dispara automáticamente, **antes** de reconstruir/reiniciar
el backend, en dos puntos del pipeline (son dos rutas de despliegue
independientes que corren en el mismo Raspberry Pi):

1. `uis-schedule-system-backend/.github/workflows/deploy.yml` — paso
   *"Backup scheduleDB antes de aplicar migraciones"*, antes de *"Rebuild y
   reinicio del contenedor"*. **Condicional**: un paso previo
   (*"Detectar cambios en migraciones Flyway"*) compara, con
   `git diff`, el SHA que estaba desplegado en `/home/dev/proyects/uis-schedule-system-backend`
   contra el nuevo SHA, sólo en la ruta `backend/src/main/resources/db/migration/`.
   El backup sólo corre si ese push trae migraciones nuevas o modificadas —
   así se cumple literalmente el alcance de la historia ("previo a cualquier
   despliegue que **aplique migraciones**"), sin gastar tiempo/IO en cada
   push que no las toca.
2. `.github/workflows/cd-pipeline.yml` (raíz) — paso *"Backup scheduleDB
   antes de desplegar"*, justo antes de *"Deploy application (Frontend and
   Backend)"*. **Incondicional** (corre en cada ejecución): esta ruta parte
   de un checkout efímero sin un "SHA previamente desplegado" claro contra
   el cual diffear, así que se optó por simplicidad y seguridad sobre
   afinar la condición; el costo extra es bajo gracias a la rotación de dumps.

Si el contenedor `postgres` aún no existe (por ejemplo, en el primer
despliegue), el script lo detecta, no falla el pipeline y simplemente
informa que no hay nada que respaldar.

## Respaldo manual

```bash
cd uis-schedule-system   # raíz del monorepo
./scripts/db-backup.sh
```

Variables de entorno opcionales:

| Variable | Default | Descripción |
| --- | --- | --- |
| `ENV_FILE` | `./.env` | Archivo con `DB_NAME`/`DB_USERNAME`/`DB_PASSWORD` |
| `DB_CONTAINER` | `postgres` | Nombre del contenedor Postgres |
| `BACKUP_DIR` | `./backups` | Carpeta donde se guardan los dumps |
| `BACKUP_RETENTION` | `7` | Cantidad de dumps a conservar (rotación automática) |

El dump queda en `BACKUP_DIR/scheduleDB_<YYYYMMDD_HHMMSS>.dump`.

## Restauración manual (disaster recovery)

**Operación destructiva**: sobrescribe el contenido actual de `scheduleDB`.
No se ejecuta automáticamente en ningún pipeline; siempre es una acción manual.

```bash
# 1) Ver qué haría, sin ejecutar nada (dry-run):
./scripts/db-restore.sh latest

# 2) Ejecutar la restauración real:
./scripts/db-restore.sh latest --yes

# También se puede indicar un dump específico en vez de "latest":
./scripts/db-restore.sh ./backups/scheduleDB_20260901_153218.dump --yes
```

## Prueba realizada (verificación del criterio de cierre)

Se probó el ciclo completo de respaldo/restauración contra un contenedor
Postgres 16 descartable (no el de producción), el 2026-09-01:

1. Se creó una tabla de prueba con 3 filas.
2. `db-backup.sh` generó el dump correctamente.
3. Se generaron respaldos adicionales para confirmar la rotación: con
   `BACKUP_RETENTION=3`, tras generar 5 dumps sólo quedaron los 3 más
   recientes.
4. Se corrompieron los datos de la tabla (update, delete e insert de una
   fila espuria).
5. `db-restore.sh latest` en modo dry-run no modificó nada; con `--yes`
   restauró exactamente las 3 filas originales.

Resultado: **respaldo verificado y restauración probada con éxito.**

Adicionalmente se probó la condición de `deploy.yml` que sólo respalda
cuando el push trae migraciones nuevas, simulando un repo con un commit
"desplegado" y dos pushes posteriores (reproduciendo exactamente el `git diff`
que usa el workflow):

- Push que sólo cambia código de negocio (sin tocar `db/migration/`) →
  `changed=false` → el paso de backup se omite (0 dumps generados).
- Push siguiente que agrega `V2__add_aula.sql` → `changed=true` → el paso de
  backup se ejecuta y genera el dump (1 dump generado) contra el mismo
  contenedor Postgres descartable.

Resultado: **la condición "sólo respalda si hay migraciones nuevas" también quedó verificada.**

## Notas

- Los dumps quedan excluidos de git (`backups/` está en `.gitignore`).
- El formato de dump es `pg_dump -F c` (custom), compatible con
  `pg_restore --clean --if-exists`, lo que permite restaurar sobre una base
  de datos que ya tiene tablas sin necesidad de borrarla manualmente antes.
