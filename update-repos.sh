#!/bin/bash

# --- CONFIGURACIÓN DE RUTAS ---
BASE_DIR="/home/dev/proyects"
LOGFILE="$BASE_DIR/logs/update-repos.log"
BACKEND_DIR="$BASE_DIR/uis-schedule-system-backend"
FRONTEND_DIR="$BASE_DIR/uis-schedule-system-frontend"

# --- ROTACIÓN DE LOGS ---
# Si el archivo supera 10MB, rota y mantiene histórico
if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
    for i in {3..1}; do
        [ -f "${LOGFILE}.${i}.gz" ] && mv "${LOGFILE}.${i}.gz" "${LOGFILE}.$((i+1)).gz"
    done
    gzip -c "$LOGFILE" > "${LOGFILE}.1.gz" && > "$LOGFILE"
    [ -f "${LOGFILE}.5.gz" ] && rm "${LOGFILE}.5.gz"
fi

# --- FUNCIONES DE LOGGING ---
LOG_BUFFER=""
log_info() {
    local MSG="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
    LOG_BUFFER+="$MSG\n"
    echo "$MSG" # Salida en tiempo real para debug manual
}

log_error() {
    local MSG="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"
    LOG_BUFFER+="$MSG\n"
    echo "$MSG" >&2
}

log_warning() {
    local MSG="[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $*"
    LOG_BUFFER+="$MSG\n"
    echo "$MSG"
}

# --- INICIO DEL PROCESO ---
log_info "=== Iniciando proceso de actualización ==="

# 1. CARGAR VARIABLES DE ENTORNO
if [ -f "$BASE_DIR/.env" ]; then
    export $(grep -v '^#' "$BASE_DIR/.env" | xargs)
    log_info "Variables de entorno cargadas desde .env"
else
    log_warning "Archivo .env no encontrado en $BASE_DIR"
fi

# 2. ACTUALIZAR REPOSITORIO PRINCIPAL (ROOT)
cd "$BASE_DIR" || exit
log_info "Main Repo: Verificando cambios en el root..."
git fetch origin >> "$LOGFILE" 2>&1 || log_error "Main Repo: Error en git fetch"

MAIN_CURRENT=$(git rev-parse HEAD)
MAIN_REMOTE=$(git rev-parse origin/$(git branch --show-current) 2>/dev/null)

if [ "$MAIN_CURRENT" != "$MAIN_REMOTE" ]; then
    log_info "Main Repo: Cambios detectados en el root. Actualizando..."
    git pull origin $(git branch --show-current) >> "$LOGFILE" 2>&1 || log_error "Main Repo: Error en git pull"
fi

# 3. VERIFICAR BACKEND (SUBMÓDULO)
cd "$BACKEND_DIR" || exit
log_info "Backend: Verificando cambios..."
git fetch origin >> "$LOGFILE" 2>&1 || log_error "Backend: error en git fetch"

BE_CURRENT=$(git rev-parse HEAD)
BE_REMOTE=$(git rev-parse origin/develop 2>/dev/null || echo "")

if [ -n "$BE_REMOTE" ] && [ "$BE_CURRENT" != "$BE_REMOTE" ]; then
    log_info "Backend: Cambios detectados, haciendo pull..."
    git pull origin develop >> "$LOGFILE" 2>&1 || log_error "Backend: error en git pull"

    # Compilación (Asumiendo estructura Spring Boot)
    if [ -d "backend" ]; then cd backend; fi
    log_info "Backend: Compilando proyecto con Maven..."
    mvn compile -Dmaven.compiler.release=17 -q >> "$LOGFILE" 2>&1 || log_error "Backend: error en mvn compile"
    [ -d "../backend" ] && cd ..

    # Analíticas SonarQube Backend
    if command -v sonar-scanner >/dev/null 2>&1; then
        log_info "Backend: Ejecutando análisis SonarQube..."
        sonar-scanner \
            -Dsonar.projectKey=uis-schedule-system-backend \
            -Dsonar.sources=backend/src/main/java \
            -Dsonar.java.binaries=backend/target/classes \
            -Dsonar.host.url=${SONAR_HOST_URL:-http://100.108.184.57:9000} \
            -Dsonar.token=${SONAR_BACKEND_TOKEN} >> "$LOGFILE" 2>&1 || log_warning "Backend: Sonar falló"
    fi
    BACKEND_UPDATED=true
fi

# 4. VERIFICAR FRONTEND (SUBMÓDULO)
cd "$FRONTEND_DIR" || exit
log_info "Frontend: Verificando cambios..."
git fetch origin >> "$LOGFILE" 2>&1 || log_error "Frontend: error en git fetch"

FE_CURRENT=$(git rev-parse HEAD)
FE_REMOTE=$(git rev-parse origin/develop 2>/dev/null || echo "")

if [ -n "$FE_REMOTE" ] && [ "$FE_CURRENT" != "$FE_REMOTE" ]; then
    log_info "Frontend: Cambios detectados, haciendo pull..."
    git pull origin develop >> "$LOGFILE" 2>&1 || log_error "Frontend: error en git pull"

    log_info "Frontend: Instalando dependencias y build..."
    npm install --silent >> "$LOGFILE" 2>&1 && npm run build --silent >> "$LOGFILE" 2>&1 || log_error "Frontend: Error en build"

    # Analíticas SonarQube Frontend
    if command -v sonar-scanner >/dev/null 2>&1; then
        log_info "Frontend: Ejecutando análisis SonarQube..."
        sonar-scanner \
            -Dsonar.host.url=${SONAR_HOST_URL:-http://100.108.184.57:9000} \
            -Dsonar.token=${SONAR_FRONTEND_TOKEN} \
            -Dsonar.projectKey=uis-schedule-system-frontend >> "$LOGFILE" 2>&1 || log_warning "Frontend: Sonar falló"
    fi
    FRONTEND_UPDATED=true
fi

# 5. REINICIO DE SERVICIOS DOCKER
if [ "$BACKEND_UPDATED" = true ] || [ "$FRONTEND_UPDATED" = true ]; then
    cd "$BASE_DIR" || exit

    SERVICES=""
    [ "$BACKEND_UPDATED" = true ] && SERVICES+=" backend-spring-api"
    [ "$FRONTEND_UPDATED" = true ] && SERVICES+=" frontend"

    if [ -n "$SERVICES" ]; then
        log_info "Docker: Reconstruyendo servicios:$SERVICES"
        docker-compose stop $SERVICES >> "$LOGFILE" 2>&1
        docker-compose rm -f $SERVICES >> "$LOGFILE" 2>&1
        docker-compose build --no-cache $SERVICES >> "$LOGFILE" 2>&1
        docker-compose up -d $SERVICES >> "$LOGFILE" 2>&1

        # Actualizar punteros de submódulos en el repo principal
        git add uis-schedule-system-backend uis-schedule-system-frontend >> "$LOGFILE" 2>&1
        log_info "Git: Referencias de submódulos actualizadas en el root."
    fi
fi

# ESCRIBIR BUFFER AL LOG Y FINALIZAR
echo -e "$LOG_BUFFER" >> "$LOGFILE"
log_info "=== Proceso finalizado correctamente ==="
