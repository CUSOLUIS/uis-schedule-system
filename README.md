# UIS Schedule System - Monorepo

Este es el repositorio principal que contiene el sistema de horarios de la UIS con backend y frontend como submódulos de Git.

## 📁 Estructura del Proyecto

```
uis-schedule-system/
├── .gitmodules                          # Configuración de submódulos
├── SETUP_LOCAL.md                       # Guía de configuración local
├── docker-compose.yml                   # Orquestación de contenedores
├── uis-schedule-system-backend/        # Submódulo: API Backend (Spring Boot)
└── uis-schedule-system-frontend/       # Submódulo: Aplicación Web (Angular)
```

## 🚀 Clonar el Proyecto

### Opción 1: Clonar con todos los submódulos (Recomendado)

```bash
git clone --recurse-submodules git@github.com:CUSOLUIS/uis-schedule-system.git
cd uis-schedule-system
```

### Opción 2: Clonar y luego inicializar submódulos

```bash
git clone git@github.com:CUSOLUIS/uis-schedule-system.git
cd uis-schedule-system
git submodule init
git submodule update
```

## 🔄 Actualizar Submódulos

### Actualizar todos los submódulos a la última versión

```bash
git submodule update --remote --merge
```

### Actualizar un submódulo específico

```bash
# Backend
cd uis-schedule-system-backend
git pull origin main
cd ..

# Frontend
cd uis-schedule-system-frontend
git pull origin main
cd ..
```

### Actualizar el repositorio principal y submódulos

```bash
git pull
git submodule update --init --recursive
```

## 📝 Trabajar con Submódulos

### Hacer cambios en un submódulo

```bash
# 1. Navegar al submódulo
cd uis-schedule-system-backend

# 2. Crear una rama y hacer cambios
git checkout -b feature/nueva-funcionalidad
# ... hacer cambios ...
git add .
git commit -m "feat: nueva funcionalidad"

# 3. Subir cambios al repositorio del submódulo
git push origin feature/nueva-funcionalidad

# 4. Volver al repositorio principal y actualizar la referencia
cd ..
git add uis-schedule-system-backend
git commit -m "chore: actualizar referencia del backend"
git push
```

### Ver el estado de los submódulos

```bash
git submodule status
```

### Ver qué commit está referenciado en cada submódulo

```bash
git submodule
```

## 🛠️ Configuración para Desarrollo

Consulta el archivo [SETUP_LOCAL.md](./SETUP_LOCAL.md) para instrucciones detalladas sobre cómo configurar el entorno de desarrollo local.

### Resumen rápido:

1. **Configurar Backend:**
   ```bash
   cd uis-schedule-system-backend/backend
   cp .env.example .env
   # Editar .env con tus valores
   ./mvnw spring-boot:run
   ```

2. **Configurar Frontend:**
   ```bash
   cd uis-schedule-system-frontend
   cp .env.example .env
   # Editar .env con tus valores
   npm install
   npm start
   ```

## 🐳 Docker

### Ejecutar con Docker Compose

```bash
docker-compose up -d
```

Esto levantará:
- Backend en `http://localhost:8080`
- Frontend en `http://localhost:4200`
- Base de datos PostgreSQL

## 📚 Documentación de Submódulos

- **Backend**: [uis-schedule-system-backend/README.md](./uis-schedule-system-backend/README.md)
- **Frontend**: [uis-schedule-system-frontend/README.md](./uis-schedule-system-frontend/README.md)

## ⚠️ Notas Importantes

### Archivos .env

Los archivos `.env` contienen información sensible y **NO deben ser versionados**:
- Cada submódulo tiene su propio `.env.example` como plantilla
- Copia `.env.example` a `.env` y configura tus valores locales
- Los archivos `.env` están incluidos en `.gitignore`

### Cambiar de rama con submódulos

```bash
git checkout otra-rama
git submodule update --init --recursive
```

### Eliminar un submódulo (si es necesario)

```bash
git submodule deinit -f path/al/submodulo
git rm -f path/al/submodulo
rm -rf .git/modules/path/al/submodulo
```

## 🤝 Contribuir

1. Fork el repositorio principal
2. Crea una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Si los cambios son en un submódulo, haz commit primero en el submódulo
4. Actualiza la referencia del submódulo en el repositorio principal
5. Haz commit de tus cambios (`git commit -m 'Add some AmazingFeature'`)
6. Push a la rama (`git push origin feature/AmazingFeature`)
7. Abre un Pull Request

## 📄 Licencia

Ver archivos LICENSE en cada submódulo:
- [Backend License](./uis-schedule-system-backend/LICENSE)
- [Frontend License](./uis-schedule-system-frontend/LICENSE)
