# Respaldo y restauración de scheduleDB

Procedimiento para respaldar la base `scheduleDB` (PostgreSQL 16, contenedor `postgres`) y restaurarla en un destino aislado.

| Script | Uso |
| --- | --- |
| `scripts/db-backup.sh` | Genera un respaldo verificado. Lo ejecutan los despliegues y también se puede correr a mano. |
| `scripts/db-restore.sh` | Restaura un respaldo en un destino explícito. Solo se usa a mano. |
| `scripts/tests/test-db-scripts.sh` | Pruebas de ambos scripts, sin Docker real. |

## 1. Respaldo

### Automático

- **Backend** (`uis-schedule-system-backend/.github/workflows/deploy.yml`): antes de actualizar la carpeta de despliegue y reconstruir `backend-spring-api`, el paso *Backup scheduleDB antes de reconstruir* ejecuta `scripts/db-backup.sh` del repo raíz. La ruta se calcula desde el submódulo.
- **Raíz** (`.github/workflows/cd-pipeline.yml`): el paso *Backup scheduleDB antes de desplegar* se ejecuta antes de `docker compose down`.

Los dos pasos se ejecutan en cada despliegue, sin depender de si hay migraciones nuevas. Así, un reintento después de un despliegue fallido también deja su copia. Si el respaldo falla, el despliegue se detiene.

### Manual

```bash
cd /home/dev/proyects
./scripts/db-backup.sh
```

| Variable | Por defecto | Para qué sirve |
| --- | --- | --- |
| `BACKUP_DIR` | `/home/dev/backups/scheduleDB` | Carpeta de los respaldos. Debe quedar fuera del volumen de PostgreSQL y de los checkouts del runner, porque estos se limpian en cada ejecución. |
| `BACKUP_RETENTION` | `7` | Cantidad de respaldos que se conservan. |
| `ENV_FILE` | `.env` de la raíz o `uis-schedule-system-backend/backend/.env` | Se leen solo `DB_NAME` y `DB_USERNAME`. Si no existe, se usan `POSTGRES_DB` y `POSTGRES_USER` del contenedor. |
| `DB_CONTAINER` | `postgres` | Contenedor que se respalda. |
| `ALLOW_NO_DB` | `0` | Con `1`, si el contenedor no está corriendo (primer despliegue), termina sin error y sin respaldo. |

### Qué garantiza

- Un error de `pg_dump`, un dump que `pg_restore --list` no puede leer o un archivo vacío terminan con error y no dejan archivo.
- Cada respaldo se guarda como `scheduleDB_AAAAMMDD_HHMMSS.dump` (formato custom), junto con su `.sha256`. Ambos archivos tienen permisos `600` y la carpeta `700`.
- El log muestra la ruta, el tamaño y el SHA-256. Nunca muestra credenciales ni contenido.
- La rotación solo se hace después de un respaldo correcto y borra cada dump junto con su checksum.

## 2. Restauración en un destino aislado (prueba)

La base operativa nunca se usa como destino de prueba. `db-restore.sh` rechaza el contenedor `postgres` salvo que se pase `--allow-operational`.

```bash
# 1. PostgreSQL 16 aislado, sin puertos publicados y en una red propia
docker network create restore-test
docker run -d --rm --name pg-restore-test --network restore-test \
  -e POSTGRES_PASSWORD="$(openssl rand -hex 16)" postgres:16

# 2. Simulación (dry-run): verifica el checksum y muestra qué haría
./scripts/db-restore.sh --file latest --target-container pg-restore-test --target-db scheduleDB

# 3. Restaurar
./scripts/db-restore.sh --file latest --target-container pg-restore-test --target-db scheduleDB --yes
```

Opciones:

- `--file`: un archivo concreto o `latest`.
- `--target-container` y `--target-db`: obligatorios.
- `--target-user`: por defecto `postgres`.
- `--yes`: ejecuta la restauración; sin él solo se hace la simulación.

El script verifica el `.sha256`, crea la base si no existe y restaura con `pg_restore --clean --if-exists --no-owner --exit-on-error`.

## 3. Comprobaciones después de restaurar

Ejecutar cada consulta en el origen (`postgres`, con su usuario) y en la copia (`pg-restore-test`, usuario `postgres`), y comparar los resultados.

```bash
# Filas por tabla
Q="SELECT string_agg(t||'='||n, ' ' ORDER BY t) FROM (SELECT relname t, (xpath('/row/c/text()', query_to_xml('select count(*) c from '||quote_ident(relname), false, true, '')))[1]::text n FROM pg_stat_user_tables) s"
docker exec pg-restore-test psql -U postgres -d scheduleDB -tAc "$Q"

# Versiones y checksums de Flyway
F="SELECT string_agg(version||':'||checksum||':'||success, ' ' ORDER BY installed_rank) FROM flyway_schema_history"
docker exec pg-restore-test psql -U postgres -d scheduleDB -tAc "$F"
```

Para validar las migraciones contra la copia:

```bash
docker run --rm --network restore-test \
  -v "$PWD/uis-schedule-system-backend/backend/src/main/resources/db/migration:/flyway/sql:ro" \
  flyway/flyway:10 -url=jdbc:postgresql://pg-restore-test:5432/scheduleDB \
  -user=postgres -password=<clave del contenedor de prueba> validate
```

Por último, se arranca el backend contra la copia: la imagen del backend, en la red `restore-test`, con `DB_HOST=pg-restore-test`. Debe iniciar sin errores de Flyway.

Al terminar:

```bash
docker rm -f pg-restore-test
docker network rm restore-test
```

## 4. Recuperación real (destructiva)

Solo ante una pérdida de datos y con acuerdo del equipo:

```bash
./scripts/db-backup.sh   # copia del estado actual antes de sobrescribirlo
./scripts/db-restore.sh --file <respaldo> --target-container postgres \
  --target-db <DB_NAME> --target-user <DB_USERNAME> --allow-operational --yes
docker compose restart backend-spring-api
```

## 5. Registro de evidencia

Cada respaldo custodiado y cada prueba de restauración se registran en la HU de Taiga con estos datos. No se adjunta el archivo ni su contenido.

| Campo | Valor |
| --- | --- |
| Origen | contenedor, base y SHA desplegado |
| Fecha | `AAAA-MM-DD HH:MM` |
| Ubicación | ruta absoluta en el servidor |
| Tamaño | bytes |
| SHA-256 | el que imprime `db-backup.sh` |
| Responsable de custodia | nombre |
| Restauración | destino aislado, conteos iguales (sí/no), Flyway válido (sí/no), backend arranca (sí/no) |

## 6. Pruebas de los scripts

```bash
./scripts/tests/test-db-scripts.sh
```

Simulan Docker y cubren estos casos:

- fallo de `pg_dump`;
- dump ilegible;
- archivo vacío;
- contenedor detenido;
- rotación;
- destino obligatorio;
- protección de la base operativa;
- simulación sin `--yes`;
- checksum alterado;
- ausencia de la contraseña en la salida.
