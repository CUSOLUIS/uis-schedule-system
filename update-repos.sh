#!/bin/bash

LOGFILE=/home/dev/proyects/update-repos.log

# Rota los logs: si el archivo supera 10MB, comprime y mantiene máximo 4 comprimidos + 1 normal
if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
    # Comprime el log actual
    gzip "$LOGFILE"
    
    # Renumera los comprimidos existentes
    for i in {3..1}; do
        if [ -f "${LOGFILE}.${i}.gz" ]; then
            mv "${LOGFILE}.${i}.gz" "${LOGFILE}.$((i+1)).gz"
        fi
    done
    
    # Mueve el comprimido actual a .1.gz
    mv "${LOGFILE}.gz" "${LOGFILE}.1.gz"
    
    # Si hay más de 4 comprimidos, elimina el más antiguo (.5.gz si existe)
    if [ -f "${LOGFILE}.5.gz" ]; then
        rm "${LOGFILE}.5.gz"
    fi
fi

# Define funciones de logging
log_info() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$DATE] [INFO] $*" >> "$LOGFILE"
}

log_error() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$DATE] [ERROR] $*" >> "$LOGFILE"
}

log_info "=== Comenzando actualización ==="

cd /home/dev/proyects/uis-schedule-system-backend || exit
git fetch origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
  log_info "Backend: cambios detectados, haciendo pull..."
  git pull >> "$LOGFILE" 2>&1
else
  log_info "Backend: sin cambios."
fi

cd /home/dev/proyects/uis-schedule-system-frontend || exit
git fetch origin
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
  log_info "Frontend: cambios detectados, haciendo pull..."
  git pull >> "$LOGFILE" 2>&1
  # Ejecuta Sonar para actualizar información del proyecto en SonarQube
  # Intenta varias formas de ejecutar Sonar: sonar, sonar-scanner, o docker (fallback)
  if command -v sonar >/dev/null 2>&1; then
    log_info "Frontend: ejecutando 'sonar' (desde carpeta frontend)..."
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      sonar \
        -Dsonar.host.url=http://100.108.184.57:9000 \
        -Dsonar.token=sqp_e1d0355edd381d87168d228ac2338d133a5280a4 \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      log_error "Frontend: 'sonar' finalizó con error."
  elif command -v sonar-scanner >/dev/null 2>&1; then
    log_info "Frontend: ejecutando 'sonar-scanner' (desde carpeta frontend)..."
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      sonar-scanner \
        -Dsonar.host.url=http://100.108.184.57:9000 \
        -Dsonar.login=sqp_e1d0355edd381d87168d228ac2338d133a5280a4 \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      log_error "Frontend: 'sonar-scanner' finalizó con error."
  elif command -v docker >/dev/null 2>&1; then
    log_info "Frontend: ejecutando Sonar con Docker (sonarsource/sonar-scanner-cli)..."
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      docker run --rm -v "$PWD":/usr/src -w /usr/src sonarsource/sonar-scanner-cli \
        -Dsonar.host.url=http://100.108.184.57:9000 \
        -Dsonar.login=sqp_e1d0355edd381d87168d228ac2338d133a5280a4 \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      log_error "Frontend: Sonar via Docker finalizó con error."
  else
    log_error "Frontend: ninguno de 'sonar', 'sonar-scanner' o 'docker' está disponible; omitiendo análisis."
  fi
else
  log_info "Frontend: sin cambios."
fi

log_info "=== Actualización completada ==="
echo "" >> "$LOGFILE"
