# WhatsApp Meow - Integración con WhatsMeow (Go)

## ¿Qué es esto?

Sistema para leer mensajes de números WhatsApp personales usando **WhatsMeow** (librería Go). 

**Importante:** Esto NO reemplaza el bot oficial de Baileys. Es complementario:
- **Bot oficial (Baileys/Node)**: Responde mensajes de clientes
- **WhatsMeow (Go)**: Lee mensajes de números personales (fuentes de información)

## Arquitectura

```
Usuario pregunta: "¿qué dijo Gatita?"
         ↓
Agente consulta whatsapp_personal_monitor
         ↓
Consulta HTTP a WhatsMeow API (puerto 3002)
         ↓
WhatsMeow retorna mensajes almacenados
         ↓
Agente responde con contexto
```

## Primer uso (emparejamiento)

1. **Deploy en Coolify**
   - El codigo ya está pusheado
   - Hacer Redeploy

2. **Verificar que el binario existe**
   ```bash
   ls -la /opt/hermes/whatsapp-meow
   ```
   Si no existe, compilar:
   ```bash
   /opt/hermes/scripts/build-whatsapp-meow.sh
   ```

3. **Emparejar WhatsApp personal**
   ```bash
   # Iniciar WhatsMeow manualmente para ver QR
   cd /opt/hermes/scripts/whatsapp-meow
   WHATSMEOW_SESSION=default WHATSMEOW_PORT=3002 go run main.go
   ```
   
   Escanea el QR con tu teléfono.
   
   Cuando veas "Conectado!", presiona Ctrl+C.

4. **Reiniciar contenedor**
   - Coolify → Restart

5. **Verificar conexión**
   ```bash
   curl http://127.0.0.1:3002/status
   ```

## Uso desde el agente

El agente puede ahora responder preguntas como:
- "¿Qué me dijo Gatita?"
- "¿Cuál fue el último mensaje de [contacto]?"
- "Busca mensajes donde hablen de [tema]"

## API Endpoints

- `GET /health` - Verificar conexión WhatsApp
- `GET /status` - Estado del servicio (mensajes, conectado, etc.)
- `GET /messages` - Todos los mensajes almacenados
- `GET /contacts` - Contactos conocidos

## Troubleshooting

**WhatsMeow no inicia:**
```bash
# Verificar logs
tail -f /opt/data/whatsapp-meow/meow.log

# Compilar manualmente
cd /opt/hermes/scripts/whatsapp-meow
go build -o /opt/hermes/whatsapp-meow main.go
```

**Sesión expirada:**
- Borrar `/opt/data/whatsapp-meow/default/`
- Volver a emparejar

**No veo mensajes:**
- WhatsMeow solo guarda mensajes que llegan DESPUÉS de conectar
- No tiene acceso al historial previo
