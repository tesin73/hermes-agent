# WhatsApp Session Troubleshooting Guide

Guía para diagnosticar y resolver problemas de sesión de WhatsApp en despliegues Docker/Coolify de Hermes Agent.

---

## Síntomas de Sesión Corrupta

| Síntoma | Descripción |
|---------|-------------|
| **PreKeyError** | `Invalid PreKey ID` en logs del bridge |
| **Session not found** | `No session found to decrypt message` |
| **Registered: false** | `creds.json` muestra `"registered": false` |
| **Mensajes no llegan** | El agente no responde a mensajes de WhatsApp |
| **Transaction failed** | Errores de `rolling back` en logs |
| **Reconexiones constantes** | `Connection closed (reason: 428)` repetido |

### Ejemplo de errores en logs:
```json
{"level":50,"err":{"type":"PreKeyError","message":"Invalid PreKey ID"}}
{"level":50,"err":{"type":"Error","message":"No session found to decrypt message"}}
```

---

## Causas Raíz

1. **Emparejamiento incompleto**: El escaneo del QR fue interrumpido o no se completó
2. **Desincronización Signal Protocol**: Las claves de cifrado para contactos/grupos quedaron inconsistentes
3. **Sesión multi-dispositivo**: La misma sesión fue usada en múltiples instancias simultáneamente
4. **Invalidación por WhatsApp**: WhatsApp invalidó las claves por seguridad después de múltiples errores
5. **Corrupción de archivos**: Los archivos de sesión (`pre-key-*.json`, `session-*.json`) quedaron en estado inconsistente

---

## Solución: Limpieza Completa y Re-emparejamiento

### Paso 0: Identificar el contenedor

```bash
docker ps -a | grep hermes
# Nota el nombre del contenedor, ej: ntkv37t2m7lkoea6ov1svky4-044255085820
```

### Paso 1: Detener el contenedor

```bash
docker stop <container_name>
# O desde la UI de Coolify
```

### Paso 2: Limpiar sesión corrupta desde el host

**Si usas Coolify con volumen persistente:**

```bash
# Verificar ubicación del volumen
docker inspect <container_name> --format='{{range .Mounts}}{{.Source}}:{{.Destination}}{{println}}{{end}}'
# Ejemplo: /var/lib/coolify/volumes/hermes-data:/opt/data

# Eliminar TODOS los archivos de sesión
sudo find /var/lib/coolify/volumes/hermes-data/whatsapp/session/ -type f -delete

# Verificar que quedó vacío (solo debe mostrar . y ..)
sudo ls -la /var/lib/coolify/volumes/hermes-data/whatsapp/session/
```

**Importante**: El wildcard `*` no funciona con miles de archivos (el shell no expande). Usa `find` siempre.

### Paso 3: Verificar creds.json eliminado

```bash
sudo ls -la /var/lib/coolify/volumes/hermes-data/whatsapp/
# Debe mostrar solo el directorio 'session' vacío
```

### Paso 4: Iniciar contenedor

```bash
docker start <container_name>
# O desde Coolify UI
```

### Paso 5: Emparejar nuevo dispositivo

```bash
# Ejecutar modo emparejamiento (muestra QR en terminal)
docker exec -it <container_name> node /opt/hermes/scripts/whatsapp-bridge/bridge.js \
  --pair-only \
  --session /opt/data/whatsapp/session \
  --mode bot
```

**Pasos para escanear QR:**
1. Abrir WhatsApp en tu teléfono
2. Menú (⋮) → "Dispositivos vinculados"
3. "Vincular dispositivo"
4. Escanea el QR que aparece en la terminal
5. Espera "Connected successfully"
6. Ctrl+C para salir del modo emparejamiento

### Paso 6: Reiniciar contenedor

```bash
docker restart <container_name>
```

El contenedor ahora arrancará con la nueva sesión válida.

---

## Verificación

### Verificar sesión registrada

```bash
docker exec <container_name> cat /opt/data/whatsapp/session/creds.json | grep '"registered"'
# Debe mostrar: "registered": true
```

### Verificar bridge funcionando

```bash
# Verificar proceso
docker exec <container_name> ps aux | grep node

# Verificar logs
docker logs <container_name> --tail 50
# Buscar: "Connection opened" o "Connected"
```

### Verificar health endpoint

```bash
docker exec <container_name> curl -s http://localhost:3000/health
# Debe retornar: {"status":"ok"}
```

---

## Prevención

### Monitorear errores PreKeyError

Agregar alerta en monitoreo:
```bash
# Contar errores PreKeyError en últimos 1000 logs
docker logs <container_name> --tail 1000 | grep -c "PreKeyError"
# Si > 10, investigar sesión
```

### Backup antes de cambios

Antes de modificaciones mayores:
```bash
sudo tar czf /backup/whatsapp-session-$(date +%Y%m%d-%H%M%S).tar.gz \
  /var/lib/coolify/volumes/hermes-data/whatsapp/session/
```

### No compartir sesión entre instancias

- Cada instancia de Hermes debe tener su propio `WHATSAPP_SESSION_NAME`
- Nunca copiar `/opt/data/whatsapp/session/` entre contenedores

---

## Comandos Rápidos (Cheatsheet)

```bash
# Diagnóstico rápido
docker logs <container> --tail 100 | grep -E "PreKeyError|registered|Connection closed"

# Estado de sesión
docker exec <container> cat /opt/data/whatsapp/session/creds.json | grep '"registered"'

# Contar archivos de sesión
docker exec <container> ls /opt/data/whatsapp/session/ | wc -l
# Si > 1000 con errores, probablemente corrupta

# Limpiar y re-emparejar (comando único)
docker stop <container> && \
sudo find /var/lib/coolify/volumes/hermes-data/whatsapp/session/ -type f -delete && \
docker start <container> && \
docker exec -it <container> node /opt/hermes/scripts/whatsapp-bridge/bridge.js \
  --pair-only --session /opt/data/whatsapp/session --mode bot
```

---

## Notas Específicas Coolify

- El volumen típico está en: `/var/lib/coolify/volumes/hermes-data`
- El contenedor usa nombre auto-generado, no `hermes-agent`
- Usar Coolify UI para reiniciar mantiene la consistencia del dashboard
- El `docker exec` debe hacerse después de que el contenedor esté en estado "Running"

---

## Automatización Segura por Contenedor

Este script limpia la sesión de **UN SOLO contenedor** sin afectar a otros:

```bash
#!/bin/bash
# Auto-fix WhatsApp session - SOLO afecta al contenedor especificado
CONTAINER="ntkv37t2m7lkoea6ov1svky4-044255085820"

# Detectar volumen de ESTE contenedor (aislado de los demás)
VOLUME=$(docker inspect "$CONTAINER" --format='{{range .Mounts}}{{if eq .Destination "/opt/data"}}{{.Source}}{{end}}{{end}}')

echo "Volumen afectado: $VOLUME"
echo "Los otros contenedores usan volúmenes diferentes - NO se ven afectados"

# Detener, limpiar, reiniciar
docker stop "$CONTAINER"
sudo find "$VOLUME/whatsapp/session/" -type f -delete
docker start "$CONTAINER"

# Emparejamiento manual requerido
docker exec -it "$CONTAINER" node /opt/hermes/scripts/whatsapp-bridge/bridge.js \
  --pair-only --session /opt/data/whatsapp/session --mode bot
```

### Cada contenedor tiene su propio volumen:

```
Contenedor 1 → /var/lib/coolify/volumes/hermes-cliente1-data/
Contenedor 2 → /var/lib/coolify/volumes/hermes-cliente2-data/
Contenedor N → /var/lib/coolify/volumes/hermes-clienteN-data/
```

**Aislados completamente** - borrar en uno no toca los otros.

---

## Referencias

- [Baileys Documentation](https://github.com/WhiskeySockets/Baileys)
- [Signal Protocol](https://signal.org/docs/)
- Skill relacionado: `whatsapp-docker-manual-pairing`
