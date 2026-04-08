# Hermes Agent - Docker Mass Deployment Guide

Guía para desplegar múltiples instancias de Hermes Agent con WhatsApp, totalmente automatizado via Docker Compose.

## Características

- ✅ **Auto-pairing**: El QR aparece automáticamente en los logs
- ✅ **Un comando**: Solo `docker-compose up -d`
- ✅ **Escalable**: Script para desplegar múltiples clientes
- ✅ **Persistente**: Sesiones y datos guardados en volúmenes Docker

## Quick Start

### 1. Configurar variables de entorno

```bash
cp .env.docker.example .env
# Editar .env con tus valores
```

Variables críticas:
```bash
OPENROUTER_API_KEY=sk-or-v1-...          # Tu API key
WHATSAPP_SESSION_NAME=cliente-a-session  # ÚNICO por cliente
WHATSAPP_ALLOWED_USERS=+56912345678      # Tu número admin
```

### 2. Iniciar

```bash
docker-compose up -d
```

### 3. Ver QR y emparejar

```bash
docker logs -f hermes-agent
```

Verás:
```
╔════════════════════════════════════════════════════════════════╗
║  📱 WHATSAPP PAIRING REQUIRED                                  ║
╚════════════════════════════════════════════════════════════════╝
...
[QR code aparece aquí]
```

Escanea el QR con WhatsApp → Linked Devices → Link a Device

### 4. Listo!

Una vez emparejado, el agente inicia automáticamente. El QR solo aparece la primera vez.

---

## Despliegue Masivo (Múltiples Clientes)

### Opción A: Script Automático

```bash
# Exportar tu API key una vez
export OPENROUTER_API_KEY=sk-or-v1-...

# Desplegar nuevo cliente
./scripts/deploy-client.sh "Acme Corp" "+56912345678"
```

Esto crea:
- `.env.acme-corp` - Configuración del cliente
- Contenedor `hermes-acme-corp`
- Volumen `hermes_data_acme_corp`

### Opción B: Manual por Cliente

Para cada cliente, crear un archivo `.env.cliente-X`:

```bash
# .env.cliente-a
OPENROUTER_API_KEY=sk-or-v1-...
WHATSAPP_SESSION_NAME=cliente-a-session
WHATSAPP_ALLOWED_USERS=+56911111111
CONTAINER_NAME=hermes-cliente-a
VOLUME_NAME=hermes_data_cliente_a
AGENT_NAME="Cliente A"
```

Luego:
```bash
docker-compose --env-file .env.cliente-a up -d
```

---

## Comandos Útiles

```bash
# Ver todos los contenedores Hermes
docker ps --filter name=hermes

# Logs de un cliente específico
docker logs -f hermes-cliente-a

# Detener un cliente
docker-compose --env-file .env.cliente-a down

# Detener todos los clientes
docker stop $(docker ps -q --filter name=hermes-)

# Ver sesiones WhatsApp guardadas
docker volume ls | grep hermes_data

# Backup de sesión de un cliente
docker run --rm -v hermes_data_cliente_a:/data -v $(pwd):/backup alpine tar czf /backup/cliente-a-backup.tar.gz -C /data whatsapp
```

---

## Solución de Problemas

### "WHATSAPP_SESSION_NAME is required"

Asegúrate de definir `WHATSAPP_SESSION_NAME` en tu `.env`. Debe ser único por cliente.

### El QR no aparece

Verifica que la variable esté definida:
```bash
docker exec hermes-agent echo $WHATSAPP_SESSION_NAME
```

Si está vacía, reconstruye:
```bash
docker-compose down
docker-compose up -d --build
```

### "Pairing failed"

1. Verifica que el número esté en formato internacional: `+56912345678`
2. Asegúrate de escanear el QR antes de que expire (30 segundos)
3. Revisa los logs: `docker logs hermes-agent | grep -i error`

### Sesión perdida después de reinicio

Las sesiones se guardan en volúmenes Docker. Verifica:
```bash
docker volume inspect hermes_data
```

Si el volumen se perdió, empareja nuevamente (el QR aparecerá automáticamente).

---

## Estructura de Datos

Cada cliente tiene:

```
/opt/data/                     (volumen Docker)
├── whatsapp/
│   ├── session/
│   │   └── creds.json        # Sesión WhatsApp (persistente)
│   └── bridge.log            # Logs del bridge
├── memories/                  # Memoria del agente
├── skills/                    # Skills instaladas
├── logs/                      # Logs de sesiones
└── .env                       # Configuración
```

---

## Coolify Deployment

Para Coolify (PaaS), usar el mismo `docker-compose.yml`:

1. Create New Resource → Docker Compose
2. Pegar contenido de `docker-compose.yml`
3. En Environment Variables, agregar todas las variables del `.env`
4. Asegúrate de que `WHATSAPP_SESSION_NAME` esté definida
5. Deploy

El QR aparecerá en los logs de Coolify (Deployments → View Logs).

---

## Seguridad

- Nunca commitees archivos `.env` con API keys
- Cada cliente debe tener `WHATSAPP_SESSION_NAME` único
- `WHATSAPP_ALLOWED_USERS` limita quién puede usar el bot
- Las sesiones WhatsApp están aisladas por volumen Docker
