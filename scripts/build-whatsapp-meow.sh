#!/bin/bash
# Build script para WhatsMeow
# Ejecutar en Coolify Terminal si Go está disponible

set -e

echo "[build-whatsapp-meow] Construyendo WhatsMeow..."

# Verificar Go
if ! command -v go &> /dev/null; then
    echo "[build-whatsapp-meow] ERROR: Go no está instalado"
    echo "Instala Go en el Dockerfile o instala:"
    echo "  apk add --no-cache go gcc musl-dev sqlite-dev"
    exit 1
fi

cd /opt/hermes/scripts/whatsapp-meow

# Descargar dependencias
echo "[build-whatsapp-meow] Descargando dependencias..."
go mod tidy

# Compilar
echo "[build-whatsapp-meow] Compilando..."
go build -o /opt/hermes/whatsapp-meow main.go

echo "[build-whatsapp-meow] ✓ Binario creado: /opt/hermes/whatsapp-meow"
ls -lh /opt/hermes/whatsapp-meow
