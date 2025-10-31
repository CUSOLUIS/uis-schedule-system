#!/bin/bash

# Script maestro para gestionar la ejecución del sistema UIS Schedule

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

show_menu() {
    clear
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         UIS Schedule System - Gestor de Ejecución             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📦 EJECUCIÓN CON DOCKER (Todo el sistema)"
    echo "   1) Iniciar todos los servicios (Backend + Frontend + SonarQube)"
    echo "   2) Detener todos los servicios"
    echo "   3) Reconstruir y reiniciar todos los servicios"
    echo "   4) Ver estado de todos los contenedores"
    echo "   5) Ver logs de todos los servicios"
    echo ""
    echo "🔧 EJECUCIÓN INDIVIDUAL CON DOCKER"
    echo "   6) Solo Backend (Docker)"
    echo "   7) Solo Frontend (Docker)"
    echo ""
    echo "💻 EJECUCIÓN LOCAL (Desarrollo)"
    echo "   8) Backend (local con hot-reload)"
    echo "   9) Frontend (local con hot-reload)"
    echo ""
    echo "🧹 MANTENIMIENTO"
    echo "  10) Limpiar todo (contenedores, volúmenes, imágenes)"
    echo "  11) Ver uso de recursos (Docker)"
    echo ""
    echo "   0) Salir"
    echo ""
    read -p "Selecciona una opción: " option
}

start_all_docker() {
    echo "🚀 Iniciando todos los servicios con Docker..."
    cd "$SCRIPT_DIR" || exit 1
    docker-compose up -d
    echo ""
    echo "⏳ Esperando a que los servicios estén listos..."
    sleep 20
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "✅ Servicios disponibles:"
    echo "   - Frontend: http://localhost"
    echo "   - Backend: http://localhost:8080"
    echo "   - Swagger: http://localhost:8080/swagger-ui"
    echo "   - SonarQube: http://localhost:9000"
}

stop_all_docker() {
    echo "🛑 Deteniendo todos los servicios..."
    cd "$SCRIPT_DIR" || exit 1
    docker-compose down
    echo "✅ Todos los servicios detenidos"
}

rebuild_all() {
    echo "🔨 Reconstruyendo y reiniciando todos los servicios..."
    cd "$SCRIPT_DIR" || exit 1
    docker-compose down
    docker-compose build
    docker-compose up -d
    echo ""
    echo "⏳ Esperando a que los servicios estén listos..."
    sleep 25
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "✅ Servicios reconstruidos y disponibles"
}

show_status() {
    echo "📊 Estado de los contenedores:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    echo "📦 Volúmenes de Docker:"
    docker volume ls | grep proyects
    echo ""
    echo "🌐 Redes de Docker:"
    docker network ls | grep proyects
}

show_logs() {
    echo "📋 Logs de los servicios (últimas 50 líneas):"
    echo ""
    echo "--- BACKEND ---"
    docker logs backend-spring-api-container --tail 50 2>&1 || echo "Backend no está corriendo"
    echo ""
    echo "--- FRONTEND ---"
    docker logs uis-schedule-frontend --tail 50 2>&1 || echo "Frontend no está corriendo"
    echo ""
    echo "--- SONARQUBE ---"
    docker logs sonarqube --tail 50 2>&1 || echo "SonarQube no está corriendo"
}

backend_docker() {
    echo "🔧 Iniciando solo Backend con Docker..."
    cd "$SCRIPT_DIR/uis-schedule-system-backend/backend" || exit 1
    ./test-docker.sh
}

frontend_docker() {
    echo "🔧 Iniciando solo Frontend con Docker..."
    cd "$SCRIPT_DIR/uis-schedule-system-frontend" || exit 1
    ./test-docker.sh
}

backend_local() {
    echo "💻 Iniciando Backend en modo local..."
    cd "$SCRIPT_DIR/uis-schedule-system-backend/backend" || exit 1
    ./run-local.sh
}

frontend_local() {
    echo "💻 Iniciando Frontend en modo local..."
    cd "$SCRIPT_DIR/uis-schedule-system-frontend" || exit 1
    ./run-local.sh
}

clean_all() {
    echo "⚠️  ADVERTENCIA: Esto eliminará todos los contenedores, volúmenes e imágenes"
    read -p "¿Estás seguro? (s/n): " confirm
    if [[ "$confirm" =~ ^[Ss]$ ]]; then
        echo "🧹 Limpiando todo..."
        cd "$SCRIPT_DIR" || exit 1
        docker-compose down -v
        docker system prune -a -f
        echo "✅ Limpieza completada"
    else
        echo "❌ Operación cancelada"
    fi
}

show_resources() {
    echo "💾 Uso de recursos de Docker:"
    echo ""
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
    echo ""
    echo "💽 Espacio en disco:"
    docker system df
}

# Bucle principal
while true; do
    show_menu
    
    case $option in
        1) start_all_docker ;;
        2) stop_all_docker ;;
        3) rebuild_all ;;
        4) show_status ;;
        5) show_logs ;;
        6) backend_docker ;;
        7) frontend_docker ;;
        8) backend_local ;;
        9) frontend_local ;;
        10) clean_all ;;
        11) show_resources ;;
        0) echo "👋 Saliendo..."; exit 0 ;;
        *) echo "❌ Opción inválida" ;;
    esac
    
    echo ""
    read -p "Presiona Enter para continuar..."
done
