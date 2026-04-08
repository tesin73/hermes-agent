# Hermes Agent - Docker Deployment

Despliegue de Hermes Agent en Docker con WhatsApp opcional y control manual.

## Características

- ✅ Gateway siempre disponible (con o sin WhatsApp)
- ✅ Emparejamiento WhatsApp manual cuando TÚ decidas
- ✅ No requiere reinicio de contenedor después de emparejar
- ✅ Scripts simples para control manual

## Quick Start

### 1. Configurar

```bash
cp .env.docker.example .env
# Editar .env con tu OPENROUTER_API_KEY y WHATSAPP_ALLOWED_USERS
```

### 2. Iniciar

```bash
docker-compose up -d --build
```

El gateway iniciará inmediatamente. WhatsApp estará desconectado hasta que lo emparejes.

### 3. Emparejar WhatsApp (cuando TÚ quieras)

```bash
docker exec -it hermes-agent /opt/hermes/docker/pair-whatsapp.sh
```

Escanea el QR con tu teléfono. Cuando termine, el bridge se activará automáticamente.

### 4. Verificar

```bash
# Ver logs del bridge
docker exec hermes-agent tail -f /opt/data/whatsapp/bridge.log

# Verificar que responde
docker exec hermes-agent curl http://localhost:3000/health
```

---

## Comandos Disponibles

| Comando | Descripción |
|---------|-------------|
| `docker-compose up -d` | Iniciar Hermes (gateway siempre activo) |
| `docker-compose down` | Detener Hermes |
| `docker exec -it hermes-agent /opt/hermes/docker/pair-whatsapp.sh` | Emparejar WhatsApp |
| `docker exec hermes-agent /opt/hermes/docker/start-bridge.sh` | Iniciar bridge manualmente (si no inició automático) |
| `docker logs -f hermes-agent` | Ver logs del gateway |

---

## Flujo Detallado

### Inicio sin WhatsApp

```
Container starts
  ├── Gateway starts (port 8080) ✓
  ├── WhatsApp check: "No session found"
  └── Message: "WhatsApp will be available after pairing"
```

### Después de Emparejar

```
docker exec pair-whatsapp.sh
  ├── Muestra QR
  ├── Espera escaneo
  ├── Guarda credenciales
  └── Mensaje: "Pairing complete!"

Bridge starts automatically (or run start-bridge.sh)
  └── WhatsApp now connected ✓
```

---

## Solución de Problemas

### "Bridge not responding"

Verifica si el bridge está corriendo:
```bash
docker exec hermes-agent pgrep -f bridge.js
```

Si no está corriendo, inícialo manualmente:
```bash
docker exec hermes-agent /opt/hermes/docker/start-bridge.sh
```

### "QR code not appearing"

Asegúrate de que el contenedor tenga TTY:
```bash
docker exec -it hermes-agent /opt/hermes/docker/pair-whatsapp.sh
```

### Re-emparejar (cambiar de número)

```bash
# 1. Detener contenedor
docker-compose down

# 2. Borrar sesión anterior
docker volume rm hermes_data
# o: docker exec hermes-agent rm -rf /opt/data/whatsapp/session

# 3. Reconstruir
docker-compose up -d --build

# 4. Emparejar de nuevo
docker exec -it hermes-agent /opt/hermes/docker/pair-whatsapp.sh
```

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Container                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Gateway   │    │   Bridge    │    │   Pairing   │     │
│  │  (:8080)    │◄──►│  (:3000)    │    │   Script    │     │
│  │  Always ON  │    │  Optional   │    │  (manual)   │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                                                   │
│    ┌────┴────┐                                              │
│    │ Volume  │ /opt/data                                    │
│    │  Data   │ (persistente)                                │
│    └─────────┘                                              │
└─────────────────────────────────────────────────────────────┘
```

- **Gateway**: Siempre corre, puerto 8080
- **Bridge**: Solo si hay sesión emparejada
- **Pairing Script**: Ejecutable bajo demanda
