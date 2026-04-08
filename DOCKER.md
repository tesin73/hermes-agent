# Hermes Agent - Docker Deployment

Despliegue de Hermes Agent en Docker con WhatsApp opcional y control manual.

## Características

- ✅ Gateway siempre disponible (con o sin WhatsApp)
- ✅ Emparejamiento WhatsApp manual cuando TÚ decidas
- ✅ No requiere reinicio de contenedor después de emparejar
- ✅ Compatible con Coolify PaaS
- ✅ Sesión WhatsApp persistente entre rebuilds

---

## Quick Start (Docker Compose Local)

```bash
# 1. Configurar
cp .env.docker.example .env
# Editar .env con tu OPENROUTER_API_KEY y WHATSAPP_ALLOWED_USERS

# 2. Iniciar
docker-compose up -d --build

# 3. Emparejar WhatsApp (cuando quieras)
docker exec -it hermes-agent /opt/hermes/docker/pair-whatsapp.sh

# 4. Listo!
```

---

## Deploy en Coolify PaaS

### ⚠️ CRITICAL: Configurar Persistent Storage

Coolify reconstruye contenedores en cada deploy de Git. **Los volúmenes NO persisten automáticamente** a menos que configures el Storage en la UI.

### Paso 1: Configurar Volumen Persistente

1. Ve a tu servicio Hermes en Coolify
2. Click en **"Storage"** tab
3. Agregar volumen:
   - **Path in container:** `/opt/data/whatsapp/session`
   - **Path on host:** `/var/lib/coolify/volumes/hermes-whatsapp-session`
   - ✅ Marcar como **"Persistent"** (¡CRÍTICO!)

### Paso 2: Habilitar TTY y Stdin

En la configuración del servicio:
- ✅ **Enable TTY** - Requerido para mostrar el QR
- ✅ **Enable Stdin** - Requerido para el script de pairing

### Paso 3: Deploy

```bash
# Push a tu repo
git push origin main

# Coolify hará el deploy automáticamente
```

### Paso 4: Emparejar WhatsApp

1. Ve a la pestaña **Terminal** en Coolify UI
2. Ejecuta:
```bash
/opt/hermes/docker/pair-whatsapp.sh
```
3. Escanea el QR con tu teléfono
4. La sesión se guardará en el volumen persistente

### Paso 5: Verificar

```bash
# Verificar que el bridge está corriendo
/opt/hermes/docker/start-bridge.sh

# Ver logs
tail -f /opt/data/whatsapp/bridge.log

# Health check
curl http://localhost:3000/health
```

---

## Comandos Disponibles

| Comando | Descripción |
|---------|-------------|
| `docker-compose up -d` | Iniciar Hermes (gateway siempre activo) |
| `docker-compose down` | Detener Hermes |
| `docker exec -it hermes-agent /opt/hermes/docker/pair-whatsapp.sh` | Emparejar WhatsApp |
| `docker exec hermes-agent /opt/hermes/docker/start-bridge.sh` | Iniciar bridge manualmente |
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

```bash
docker exec pair-whatsapp.sh
  ├── Muestra QR
  ├── Espera escaneo
  ├── Guarda credenciales
  └── Mensaje: "Pairing complete!"
```

---

## Solución de Problemas

### "Session not persisting after redeploy" (Coolify)

**Problema**: Coolify reconstruye el contenedor y pierde la sesión.

**Solución**: 
- Verifica en Coolify Storage tab que el path esté marcado como **Persistent**
- El path debe ser: `/opt/data/whatsapp/session`

### "QR code not appearing"

**Problema**: No se muestra el código QR.

**Solución**:
- Habilitar **TTY** y **Stdin** en la configuración del servicio
- El terminal debe soportar Unicode (60+ columnas de ancho)
- En Coolify: usa la pestaña Terminal (no los logs)

### "Bridge not responding"

```bash
# Verificar si el bridge está corriendo
docker exec hermes-agent pgrep -f bridge.js

# Si no está, iniciar manualmente
docker exec hermes-agent /opt/hermes/docker/start-bridge.sh
```

### Re-emparejar (cambiar de número)

```bash
# 1. Detener contenedor
docker-compose down

# 2. Borrar sesión
docker volume rm hermes_data_whatsapp_session

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
│    ┌────┴─────────────────────────────────────────────┐    │
│    │ Volume /opt/data/whatsapp/session               │    │
│    │ (MUST be Persistent in Coolify!)               │    │
│    └──────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

- **Gateway**: Siempre corre, puerto 8080
- **Bridge**: Solo si hay sesión emparejada
- **Pairing Script**: Ejecutable bajo demanda
- **Volumen**: DEBE configurarse como Persistent en Coolify

---

## Alternativas a Coolify

Si persisten problemas con Coolify:

| Alternativa | Pros | Ideal Para |
|-------------|------|------------|
| **Docker Compose puro** | Volúmenes nativos persistentes | VPS propio |
| **Dokku** | PaaS maduro, mejor soporte de volúmenes | Git deploy |
| **Railway/Render** | Discos persistentes nativos | Hosting manejado |

---

## Notas Importantes

1. **Coolify Storage**: Sin configurar el Storage tab como Persistent, perderás la sesión WhatsApp en cada deploy
2. **TTY/Stdin**: Son requeridos para el QR, no solo para estética
3. **WHATSAPP_ALLOWED_USERS**: Configurar antes del primer mensaje para seguridad
