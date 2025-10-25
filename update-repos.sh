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
LOG_BUFFER=""
log_info() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    LOG_BUFFER+="[$DATE] [INFO] $*\n"
}

log_error() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    LOG_BUFFER+="[$DATE] [ERROR] $*\n"
}

cd /home/dev/proyects/uis-schedule-system-backend || exit
git fetch origin || log_error "Backend: error en git fetch"
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
  log_info "Backend: cambios detectados, deteniendo Docker..."
  cd backend || exit
  docker compose down >> "$LOGFILE" 2>&1 || log_error "Backend: error al detener Docker"
  cd .. || exit
  
  log_info "Backend: haciendo pull..."
  git pull >> "$LOGFILE" 2>&1 || log_error "Backend: error en git pull"
  
  cd backend || exit
  log_info "Backend: compilando proyecto..."
  mvn compile -Dmaven.compiler.release=17 >> "$LOGFILE" 2>&1 || log_error "Backend: error en mvn compile"
  cd .. || exit
  
  if command -v sonar-scanner >/dev/null 2>&1; then
    log_info "Backend: ejecutando sonar-scanner..."
    sonar-scanner \
      -Dsonar.projectKey=uis-schedule-system-backend \
      -Dsonar.sources=backend/src/main/java \
      -Dsonar.java.binaries=backend/target/classes \
      -Dsonar.host.url=http://100.108.184.57:9000 \
      -Dsonar.token=sqp_70792b2cb36159ac9409730b24fad9d5f6621f3c >> "$LOGFILE" 2>&1 || \
      log_error "Backend: sonar-scanner finalizó con error."
  else
    log_error "Backend: sonar-scanner no está disponible; omitiendo análisis."
  fi
  
  cd backend || exit
  log_info "Backend: reconstruyendo y lanzando Docker..."
  docker compose build >> "$LOGFILE" 2>&1 || log_error "Backend: error al construir Docker"
  docker compose up -d >> "$LOGFILE" 2>&1 || log_error "Backend: error al lanzar Docker"
  cd .. || exit
fi

cd /home/dev/proyects/uis-schedule-system-frontend || exit
git fetch origin || log_error "Frontend: error en git fetch"
if [ "$(git rev-parse HEAD)" != "$(git rev-parse @{u})" ]; then
  log_info "Frontend: deteniendo Docker..."
  docker compose down >> "$LOGFILE" 2>&1 || log_error "Frontend: error al detener Docker"
  
  log_info "Frontend: haciendo pull..."
  git pull >> "$LOGFILE" 2>&1 || log_error "Frontend: error en git pull"
  
  log_info "Frontend: instalando dependencias..."
  npm install >> "$LOGFILE" 2>&1 || log_error "Frontend: error en npm install"
  
  log_info "Frontend: compilando aplicación..."
  npm run build >> "$LOGFILE" 2>&1 || log_error "Frontend: error en npm run build"
  
  log_info "Frontend: reconstruyendo y lanzando Docker..."
  docker compose build >> "$LOGFILE" 2>&1 || log_error "Frontend: error al construir Docker"
  docker compose up -d >> "$LOGFILE" 2>&1 || log_error "Frontend: error al lanzar Docker"
  
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
fi

if [ -n "$LOG_BUFFER" ]; then
  echo -e "$LOG_BUFFER" >> "$LOGFILE"
  echo "" >> "$LOGFILE"
fi
