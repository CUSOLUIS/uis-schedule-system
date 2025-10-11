#!/bin/bash

LOGFILE=/home/dev/proyects/update-repos.log
DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "[$DATE] === Comenzando actualización ===" >> "$LOGFILE"

cd /home/dev/proyects/uis-schedule-system-backend || exit
git fetch origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
  echo "[$DATE] Backend: cambios detectados, haciendo pull..." >> "$LOGFILE"
  git pull >> "$LOGFILE" 2>&1
else
  echo "[$DATE] Backend: sin cambios." >> "$LOGFILE"
fi

cd /home/dev/proyects/uis-schedule-system-frontend || exit
git fetch origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
  echo "[$DATE] Frontend: cambios detectados, haciendo pull..." >> "$LOGFILE"
  git pull >> "$LOGFILE" 2>&1
  # Ejecutar Sonar para actualizar información del proyecto en SonarQube
  # Intentar varias formas de ejecutar Sonar: sonar, sonar-scanner, o docker (fallback)
  if command -v sonar >/dev/null 2>&1; then
    echo "[$DATE] Frontend: ejecutando 'sonar' (desde carpeta frontend)..." >> "$LOGFILE"
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      sonar \
        -Dsonar.host.url=http://100.108.184.57:9000 \
        -Dsonar.token=sqp_e1d0355edd381d87168d228ac2338d133a5280a4 \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      echo "[$DATE] Frontend: 'sonar' finalizó con error." >> "$LOGFILE"
  elif command -v sonar-scanner >/dev/null 2>&1; then
    echo "[$DATE] Frontend: ejecutando 'sonar-scanner' (desde carpeta frontend)..." >> "$LOGFILE"
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      sonar-scanner \
        -Dsonar.host.url=http://100.108.184.57:9000 \
        -Dsonar.login=sqp_e1d0355edd381d87168d228ac2338d133a5280a4 \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      echo "[$DATE] Frontend: 'sonar-scanner' finalizó con error." >> "$LOGFILE"
  elif command -v docker >/dev/null 2>&1; then
    echo "[$DATE] Frontend: ejecutando Sonar con Docker (sonarsource/sonar-scanner-cli)..." >> "$LOGFILE"
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      docker run --rm -v "$PWD":/usr/src -w /usr/src sonarsource/sonar-scanner-cli \
        -Dsonar.host.url=http://100.108.184.57:9000 \
        -Dsonar.login=sqp_e1d0355edd381d87168d228ac2338d133a5280a4 \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      echo "[$DATE] Frontend: Sonar via Docker finalizó con error." >> "$LOGFILE"
  else
    echo "[$DATE] Frontend: ninguno de 'sonar', 'sonar-scanner' o 'docker' está disponible; omitiendo análisis." >> "$LOGFILE"
  fi
else
  echo "[$DATE] Frontend: sin cambios." >> "$LOGFILE"
fi

echo "[$DATE] === Actualización completada ===" >> "$LOGFILE"
echo "" >> "$LOGFILE"
