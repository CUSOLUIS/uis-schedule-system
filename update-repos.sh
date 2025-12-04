#!/bin/bash

LOGFILE=/home/dev/proyects/logs/update-repos.log

# Cargar variables de entorno desde .env
if [ -f /home/dev/proyects/.env ]; then
  export $(grep -v '^#' /home/dev/proyects/.env | xargs)
fi

# Rota los logs: si el archivo supera 10MB, comprime y mantiene máximo 4 comprimidos + 1 normal
if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
    gzip "$LOGFILE"
    for i in {3..1}; do
        if [ -f "${LOGFILE}.${i}.gz" ]; then
            mv "${LOGFILE}.${i}.gz" "${LOGFILE}.$((i+1)).gz"
        fi
    done
    mv "${LOGFILE}.gz" "${LOGFILE}.1.gz"
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

log_warning() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    LOG_BUFFER+="[$DATE] [WARNING] $*\n"
}

# Verificar cambios en el backend
cd /home/dev/proyects/uis-schedule-system-backend || exit
log_info "Backend: verificando cambios remotos..."
git fetch origin >> "$LOGFILE" 2>&1 || log_error "Backend: error en git fetch"

CURRENT_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/develop 2>/dev/null || echo "")

if [ -n "$REMOTE_COMMIT" ] && [ "$CURRENT_COMMIT" != "$REMOTE_COMMIT" ]; then
  log_info "Backend: cambios detectados, haciendo pull..."
  git pull origin develop >> "$LOGFILE" 2>&1 || log_error "Backend: error en git pull"
  
  cd backend || exit
  log_info "Backend: compilando proyecto..."
  mvn compile -Dmaven.compiler.release=17 -q >> "$LOGFILE" 2>&1 || log_error "Backend: error en mvn compile"
  cd .. || exit
  
  if command -v sonar-scanner >/dev/null 2>&1; then
    log_info "Backend: ejecutando análisis SonarQube..."
    sonar-scanner \
      -Dsonar.projectKey=uis-schedule-system-backend \
      -Dsonar.sources=backend/src/main/java \
      -Dsonar.java.binaries=backend/target/classes \
      -Dsonar.host.url=${SONAR_HOST_URL:-http://100.108.184.57:9000} \
      -Dsonar.token=${SONAR_BACKEND_TOKEN} >> "$LOGFILE" 2>&1 || \
      log_warning "Backend: análisis SonarQube falló (no crítico)"
  else
    log_warning "Backend: sonar-scanner no está disponible; omitiendo análisis."
  fi
  
  BACKEND_UPDATED=true
fi

# Verificar cambios en el frontend
cd /home/dev/proyects/uis-schedule-system-frontend || exit
log_info "Frontend: verificando cambios remotos..."
git fetch origin >> "$LOGFILE" 2>&1 || log_error "Frontend: error en git fetch"

CURRENT_COMMIT=$(git rev-parse HEAD)
REMOTE_COMMIT=$(git rev-parse origin/develop 2>/dev/null || echo "")

if [ -n "$REMOTE_COMMIT" ] && [ "$CURRENT_COMMIT" != "$REMOTE_COMMIT" ]; then
  log_info "Frontend: cambios detectados, haciendo pull..."
  git pull origin develop >> "$LOGFILE" 2>&1 || log_error "Frontend: error en git pull"
  
  log_info "Frontend: instalando dependencias..."
  npm install --silent >> "$LOGFILE" 2>&1 || log_error "Frontend: error en npm install"
  
  log_info "Frontend: compilando aplicación..."
  npm run build --silent >> "$LOGFILE" 2>&1 || log_error "Frontend: error en npm run build"
  
  if command -v sonar >/dev/null 2>&1; then
    log_info "Frontend: ejecutando análisis con sonar..."
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      sonar \
        -Dsonar.host.url=${SONAR_HOST_URL:-http://100.108.184.57:9000} \
        -Dsonar.token=${SONAR_FRONTEND_TOKEN} \
        -Dsonar.projectKey=Sistemas-de-horarios-Front) >> "$LOGFILE" 2>&1 || \
      log_warning "Frontend: análisis sonar falló (no crítico)"
  elif command -v sonar-scanner >/dev/null 2>&1; then
    log_info "Frontend: ejecutando análisis con sonar-scanner..."
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      sonar-scanner \
        -Dsonar.host.url=${SONAR_HOST_URL:-http://100.108.184.57:9000} \
        -Dsonar.login=${SONAR_FRONTEND_TOKEN} \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      log_warning "Frontend: análisis sonar-scanner falló (no crítico)"
  elif command -v docker >/dev/null 2>&1; then
    log_info "Frontend: ejecutando análisis con Docker..."
    (cd /home/dev/proyects/uis-schedule-system-frontend && \
      docker run --rm -v "$PWD":/usr/src -w /usr/src sonarsource/sonar-scanner-cli \
        -Dsonar.host.url=${SONAR_HOST_URL:-http://100.108.184.57:9000} \
        -Dsonar.login=${SONAR_FRONTEND_TOKEN} \
        -Dsonar.projectKey=uis-schedule-system-frontend) >> "$LOGFILE" 2>&1 || \
      log_warning "Frontend: análisis Sonar via Docker falló (no crítico)"
  else
    log_warning "Frontend: ningún escáner Sonar disponible; omitiendo análisis."
  fi
  
  FRONTEND_UPDATED=true
fi

# Si hubo cambios en backend o frontend, reconstruir y relanzar servicios específicos
if [ "$BACKEND_UPDATED" = true ] || [ "$FRONTEND_UPDATED" = true ]; then
  cd /home/dev/proyects || exit
  
  if command -v docker-compose >/dev/null 2>&1 || command -v docker >/dev/null 2>&1; then
    SERVICES_TO_RESTART=""
    
    if [ "$BACKEND_UPDATED" = true ]; then
      SERVICES_TO_RESTART="$SERVICES_TO_RESTART backend-spring-api"
    fi
    
    if [ "$FRONTEND_UPDATED" = true ]; then
      SERVICES_TO_RESTART="$SERVICES_TO_RESTART frontend"
    fi
    
    if [ -n "$SERVICES_TO_RESTART" ]; then
      log_info "Reconstruyendo y relanzando servicios:$SERVICES_TO_RESTART"
      docker-compose stop $SERVICES_TO_RESTART >> "$LOGFILE" 2>&1 || log_warning "Advertencia al detener servicios"
      docker-compose rm -f $SERVICES_TO_RESTART >> "$LOGFILE" 2>&1 || log_warning "Advertencia al eliminar contenedores"
      docker-compose build --no-cache $SERVICES_TO_RESTART >> "$LOGFILE" 2>&1 || log_warning "Advertencia al construir servicios"
      docker-compose up -d $SERVICES_TO_RESTART >> "$LOGFILE" 2>&1 || log_warning "Advertencia al lanzar servicios"
    fi
  else
    log_warning "Docker no está disponible; omitiendo reconstrucción."
  fi
  
  # Actualizar referencias de submódulos en el repositorio principal
  cd /home/dev/proyects || exit
  if [ "$BACKEND_UPDATED" = true ]; then
    git add uis-schedule-system-backend >> "$LOGFILE" 2>&1
    log_info "Referencia del submódulo backend actualizada"
  fi
  if [ "$FRONTEND_UPDATED" = true ]; then
    git add uis-schedule-system-frontend >> "$LOGFILE" 2>&1
    log_info "Referencia del submódulo frontend actualizada"
  fi
fi

if [ -n "$LOG_BUFFER" ]; then
  echo -e "$LOG_BUFFER" >> "$LOGFILE"
  echo "" >> "$LOGFILE"
fi
