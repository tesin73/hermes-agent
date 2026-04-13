---
id: whatsapp-meow-memory
name: WhatsApp Meow Memory
description: Lee mensajes de números WhatsApp personales conectados via WhatsMeow
version: "1.0.0"
category: memory
tags: [whatsapp, messages, context]
---

# WhatsApp Meow Memory

Esta skill permite acceder a mensajes de números WhatsApp personales que están conectados mediante WhatsMeow.

## Cuándo usar

- Cuando el usuario pregunte "¿qué me dijo [alguien]?"
- Cuando necesites contexto de conversaciones de WhatsApp
- Cuando el usuario mencione "Gatita", "mi mujer", "mi socio", etc.

## Cómo usar

```python
from gateway.platforms.whatsmeow_client import get_whatsmeow_client, format_messages_for_context

async def get_whatsapp_context():
    client = get_whatsmeow_client()
    
    # Verificar conexión
    if not await client.health_check():
        return "WhatsApp personal no está conectado."
    
    # Obtener mensajes de un contacto
    messages = await client.get_messages_from("Gatita")
    context = format_messages_for_context(messages)
    
    return context
```

## Endpoints disponibles

- `http://127.0.0.1:3002/health` - Verificar conexión
- `http://127.0.0.1:3002/messages` - Todos los mensajes
- `http://127.0.0.1:3002/contacts` - Contactos conocidos
- `http://127.0.0.1:3002/status` - Estado del servicio
