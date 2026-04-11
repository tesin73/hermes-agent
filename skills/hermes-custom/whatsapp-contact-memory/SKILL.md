---
name: whatsapp-contact-memory
title: WhatsApp Contact Memory for Tiamat
description: |
  Memoria persistente de contactos de WhatsApp que permite al agente recordar
  mensajes recibidos para referirse a ellos posteriormente con el formato
  correcto: "Juanito te dijo..." en lugar de asumir la identidad del remitente.
  
  Soporte para DOS números WhatsApp simultáneos:
  1. Número del BOT - para responder clientes (bidireccional)
  2. Número PERSONAL - para contexto/memoria (solo lectura)
category: hermes-custom
version: 1.1.0
---

# WhatsApp Contact Memory

Sistema de memoria por contacto para WhatsApp que captura todos los mensajes entrantes (no solo los que mencionan al bot) y permite buscarlos bajo demanda sin quemar tokens en el contexto.

## Arquitectura Dual: Bot + Personal

Esta implementación soporta **DOS** conexiones WhatsApp simultáneamente:

| Componente | Número | Función | Dirección |
|------------|--------|---------|-----------|
| WhatsApp Bot | MOVISTAR (chip dedicado) | Responder clientes, cotizaciones, soporte | Bidireccional |
| WhatsApp Personal Monitor | TIGO (tu número) | Contexto de tus conversaciones para preguntas | Solo lectura |

### Casos de uso

**Bot (MOVISTAR):**
- Cliente: "Necesito presupuesto de emergencia"
- Agente: "El presupuesto es $400k CLP..."

**Personal Monitor (TIGO):**
- Tú: "Agente, qué me dijo Juanito ayer?"
- Agente: "Juanito te dijo: 'El presupuesto está aprobado'"

**Combinado:**
- Tú: "Resume mis mensajes importantes de hoy"
- Agente busca en AMBAS fuentes (bot + personal)

## Cómo Funciona

```
Mensaje entra (de cualquier contacto)
         ↓
[bridge.js] → /messages endpoint
         ↓
[whatsapp.py] → Guarda en contact store (TODOS los mensajes)
         ↓
¿Es para el bot? → Procesa respuesta
         ↓
Usuario pregunta: "qué me dijo Juanito?"
         ↓
Agente usa tool: search_whatsapp_memory(query="Juanito")
         ↓
Retorna: "Juanito te dijo: [mensaje]"
```

## Componentes

### 1. Contact Store (`gateway/platforms/whatsapp_contact_store.py`)

- Guarda mensajes en JSONL (append-only, eficiente)
- Índice en `index.json` con nombres y timestamps
- Un directorio por contacto (`~/.hermes/whatsapp_memory/56912345678/`)
- Sin límites arbitrarios (guarda todo desde que se activó)

### 2. Tool de Búsqueda (`tools/whatsapp_memory_tool.py`)

Tools registrados:
- `search_whatsapp_memory(query, search_type, limit)` - Busca mensajes
- `get_whatsapp_memory_stats()` - Estadísticas del store

### 3. Integración en WhatsApp Adapter (`gateway/platforms/whatsapp.py`)

Modificaciones:
- Inicializa `_contact_store` en `__init__`
- Llama `_store_in_contact_memory()` para cada mensaje entrante
- Captura TODOS los mensajes, no solo los del bot

## Uso

### Búsqueda por Contacto

```python
# El agente puede buscar automáticamente
search_whatsapp_memory(
    query="Juanito",
    search_type="contact",  # o "auto" para detectar
    limit=10
)

# Retorna:
{
  "success": True,
  "query": "Juanito",
  "results_count": 1,
  "formatted_context": "\n## Mensajes con Juanito (hace 10 min):\n- [2025-01-15 10:30] Juanito te dijo: Necesito el presupuesto de emergencia"
}
```

### Búsqueda por Contenido

```python
# Buscar quién mencionó "presupuesto"
search_whatsapp_memory(
    query="presupuesto",
    search_type="content"
)
```

## Almacenamiento

Ubicación: `~/.hermes/whatsapp_memory/`

```
~/.hermes/whatsapp_memory/
├── index.json                          # Mapeo número → nombre
├── 56912345678/                        # Directorio por contacto
│   └── messages.jsonl                  # Mensajes en formato JSONL
└── 56998765432/
    └── messages.jsonl
```

### Formato de mensaje (JSONL)

```json
{"timestamp": "2025-01-15T10:30:00", "from_me": false, "body": "Necesito el presupuesto", "chat_id": "56912345678@s.whatsapp.net"}
```

## Configuración

No requiere configuración adicional. Se activa automáticamente cuando:
1. `WHATSAPP_ENABLED=true` en el entorno
2. El gateway de WhatsApp está corriendo
3. El bot tiene modo `bot` (número propio) o `self-chat`

## Ventajas

| Aspecto | Beneficio |
|---------|-----------|
| **Tokens** | Bajo demanda, no inyecta nada al system prompt |
| **Persistencia** | JSON local, sin dependencias de DB |
| **Formato** | "Juanito te dijo..." correcto |
| **Completo** | Captura todos los mensajes, no solo menciones |
| **Eficiente** | Append-only, no reescribe archivos |

## Limitaciones

- Solo guarda mensajes desde que se activó (no histórico anterior)
- No hace summarización automática (guarda mensajes tal cual)
- Búsqueda es por string matching, no semántica
- Archivos JSONL pueden crecer indefinidamente (no hay rotación automática)

## Debugging

```bash
# Ver estadísticas
curl -s http://localhost:8000/health  # o usar tool get_whatsapp_memory_stats

# Ver archivos
ls -la ~/.hermes/whatsapp_memory/

# Ver mensajes de un contacto
cat ~/.hermes/whatsapp_memory/56912345678/messages.jsonl | tail -20

# Ver índice
cat ~/.hermes/whatsapp_memory/index.json
```

## Integración con System Prompt

Para que el agente use esta memoria efectivamente, agrega al system prompt de WhatsApp:

```
Tienes acceso a la memoria de contactos de WhatsApp. Si el usuario pregunta 
sobre conversaciones previas o qué dijo alguien, usa la herramienta 
search_whatsapp_memory para buscar el contexto.

Siempre refiere a los mensajes como "[Nombre] te dijo..." - el usuario es 
el dueño de la cuenta, tú solo tienes acceso de lectura a sus mensajes.
```

## Troubleshooting

### No se guardan mensajes

1. Verificar que el gateway está corriendo: `hermes gateway status`
2. Verificar logs: `tail -f ~/.hermes/logs/gateway.log`
3. Verificar permisos: `ls -la ~/.hermes/whatsapp_memory/`

### Tool no aparece

1. Reiniciar sesión: `/reset`
2. Verificar que `whatsapp_memory_tool.py` se importó sin errores
3. Check: `hermes tools list | grep whatsapp`

### Búsqueda no encuentra nada

1. Verificar que hay mensajes guardados: `get_whatsapp_memory_stats`
2. El contacto puede tener nombre diferente al buscado
3. Intentar búsqueda por número: `search_whatsapp_memory(query="56912345678")`

## Configuración Dual (Bot + Personal)

### Paso 1: Configurar número del Bot (MOVISTAR)

```bash
hermes whatsapp
# Seleccionar "Separate bot number"
# Escanear QR con WhatsApp Business del chip MOVISTAR
```

### Paso 2: Configurar número Personal (TIGO)

```bash
hermes whatsapp-personal
# Escanear QR con tu WhatsApp personal (TIGO)
# Esto habilita: WHATSAPP_PERSONAL_ENABLED=true
```

### Paso 3: Iniciar Gateway

```bash
hermes gateway

# Deberías ver algo como:
# ✅ WhatsApp connected (puerto 3000, modo bot)
# 🔍 WhatsApp Personal Monitor active (puerto 3001, solo lectura)
```

### Variables de Entorno

```bash
# Archivo: ~/.hermes/.env

# Bot principal (clientes)
WHATSAPP_ENABLED=true
WHATSAPP_MODE=bot
WHATSAPP_ALLOWED_USERS=*

# Monitor personal (solo lectura)
WHATSAPP_PERSONAL_ENABLED=true
```

### Estructura de Sesiones

```
~/.hermes/whatsapp/
├── session/              # Bot (MOVISTAR)
│   ├── creds.json
│   └── ...
└── session-personal/     # Tu número (TIGO)
    ├── creds.json
    └── ...
```

## Seguridad y Privacidad

### ¿Puede el agente enviar mensajes desde mi número personal?

**NO.** El WhatsApp Personal Monitor:
- Usa modo `personal-monitor` en el bridge (bloquea POST /send)
- El adaptador `WhatsAppPersonalMonitor` no implementa `send_message()` para salir
- Solo guarda en el contact store, nunca responde

### ¿Qué mensajes se guardan?

- **Bot:** Todos los mensajes de clientes que escriben al MOVISTAR
- **Personal:** Todos tus mensajes (enviados y recibidos) del TIGO
- **Ambos:** Van al mismo contact store (`~/.hermes/whatsapp_memory/`)

### ¿Dónde están los datos?

Local, en tu máquina:
- `~/.hermes/whatsapp_memory/` - Mensajes
- Nunca salen de tu servidor/contenedor
- Encriptación: WhatsApp Web (E2E) hasta tu instancia

## Changelog

### v1.1.0
- Soporte dual WhatsApp (bot + personal)
- Comando `hermes whatsapp-personal`
- Adapter `WhatsAppPersonalMonitor` (solo lectura)
- Modo `personal-monitor` en bridge.js

### v1.0.0
- Initial release para Tiamat
- Contact store con JSONL
- Tools de búsqueda
- Integración en WhatsApp adapter
