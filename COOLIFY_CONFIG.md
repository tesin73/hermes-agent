# Configuración para Coolify

## Variables de Entorno Requeridas

Agrega estas variables en tu servicio de Coolify (Resource > Environment Variables):

### Required
```
OPENROUTER_API_KEY=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
HERMES_MODEL=openrouter:moonshotai/kimi-k2.5
AGENT_NAME=Tiamat
MAX_TURNS=60
TOOL_PROGRESS=off
SHOW_REASONING=false
WHATSAPP_ENABLED=true           # <-- AGREGAR
WHATSAPP_MODE=self-chat          # <-- AGREGAR (o "bot" si usas número dedicado)
TERMINAL_TIMEOUT=300
TERMINAL_ENV=docker
```

### Optional (para que funcione correctamente)
```
WHATSAPP_ALLOWED_USERS=569XXXXXXXX   # Tu número sin el +
WHATSAPP_DEBUG=false                   # Cambiar a "true" para debugging
```

## Storage Configuration (CRITICAL)

En Coolify Resource > Storage, agregar:

```
Type: Directory Mount
Source: /data/coolify/volumes/hermes-data
Destination: /opt/data
Persistent: ✅ Yes
```

## Service Configuration

En Coolify Resource > Configuration:
- ✅ Enable TTY
- ✅ Enable Stdin
- Command: (dejar vacío, usa el default del Dockerfile)

## Pasos después del Deploy

1. Ve a la pestaña "Terminal" en Coolify
2. Empareja WhatsApp:
   ```bash
   /opt/hermes/docker/pair-whatsapp.sh
   ```
3. Escanea el QR con tu teléfono
4. Inicia el bridge:
   ```bash
   /opt/hermes/docker/start-bridge.sh
   ```
5. Prueba enviar un mensaje desde WhatsApp

## Solución de Problemas

### "WHATSAPP not responding"

Verifica variables:
```bash
# En terminal de Coolify
env | grep WHATSAPP
```

Debería mostrar:
```
WHATSAPP_ENABLED=true
WHATSAPP_MODE=self-chat
WHATSAPP_ALLOWED_USERS=569...
```

Si falta alguna, agrégala en Resource > Environment Variables y redeploya.

### Debug completo

```bash
/opt/hermes/scripts/debug-whatsapp.sh
```
