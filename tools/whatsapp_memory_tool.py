"""
Tool para buscar en memoria de WhatsApp (tanto bot como personal).

Permite al agente consultar mensajes previos para dar contexto a las respuestas.
Integra con WhatsAppContactStore para búsqueda persistente.

Uso:
    search_whatsapp_memory(query="presupuesto", contact="Juanito", hours_ago=24)
"""
import logging
import time
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Schema para el tool
SEARCH_WHATSAPP_MEMORY_SCHEMA = {
    "name": "search_whatsapp_memory",
    "description": "Busca en mensajes de WhatsApp guardados del bot o del número personal. Usa esta herramienta cuando el usuario pregunte sobre conversaciones previas, contactos, o necesites contexto de mensajes anteriores. IMPORTANTE: cuando pregunten sobre un contacto específico, usa el parámetro 'contact' con el nombre — esto retorna TODOS los mensajes recientes de esa persona para que puedas razonar sobre la conversación completa. No necesitás keywords exactos.",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "Palabra clave o frase a buscar en el contenido de los mensajes"
            },
            "contact": {
                "type": "string", 
                "description": "Nombre o número de contacto específico (opcional)"
            },
            "source": {
                "type": "string",
                "description": "Origen de los mensajes: 'bot', 'personal', o dejar vacío para ambos",
                "enum": ["bot", "personal", ""]
            },
            "limit": {
                "type": "integer",
                "description": "Máximo número de mensajes a retornar (default: 10, max: 50)",
                "minimum": 1,
                "maximum": 50,
                "default": 10
            },
            "hours_ago": {
                "type": "integer",
                "description": "Buscar solo mensajes de las últimas N horas (opcional)"
            }
        }
    }
}


def _handle_search_whatsapp_memory(args: dict, **kw) -> str:
    """
    Handler para buscar en memoria de WhatsApp.
    
    Args:
        args: Dict con query, contact, source, limit, hours_ago
        
    Returns:
        String con los mensajes encontrados
    """
    query = args.get("query")
    contact = args.get("contact")
    source = args.get("source")
    limit = args.get("limit", 10)
    hours_ago = args.get("hours_ago")

    # Limite máximo para evitar sobrecarga
    limit = min(limit, 50)
    
    # Intentar importar WhatsAppContactStore (lazy import para evitar circulares)
    try:
        import sys
        gateway_path = Path(__file__).resolve().parents[1]
        if str(gateway_path) not in sys.path:
            sys.path.insert(0, str(gateway_path))
        
        from gateway.platforms.whatsapp_contact_store import WhatsAppContactStore
        store = WhatsAppContactStore()
        
    except ImportError as e:
        logger.warning(f"Could not import WhatsAppContactStore: {e}")
        return "❌ El sistema de memoria de WhatsApp no está disponible."
    except Exception as e:
        logger.error(f"Error initializing contact store: {e}")
        return f"❌ Error al acceder a la memoria: {str(e)}"
    
    # Calcular timestamp "since" si se especificó hours_ago
    since = None
    if hours_ago:
        since = time.time() - (hours_ago * 3600)
    
    # Normalizar source vacío a None
    if source == "":
        source = None
    
    # Ejecutar búsqueda
    try:
        results = store.search_messages(
            query=query,
            contact=contact,
            source=source,
            limit=limit,
            since=since,
        )
        
        if not results:
            search_desc = []
            if query:
                search_desc.append(f'query="{query}"')
            if contact:
                search_desc.append(f'contact="{contact}"')
            if source:
                search_desc.append(f'source="{source}"')
            
            desc = ", ".join(search_desc) if search_desc else "criterios especificados"
            return f"🔍 No se encontraron mensajes con {desc}."
        
        # Formatear resultados
        lines = [
            f"📱 {len(results)} mensajes encontrados",
            "",
        ]
        
        for msg in results:
            sender = msg.get("sender", "Desconocido")
            content = msg.get("content", "")
            dt = msg.get("datetime", "Fecha desconocida")
            msg_source = msg.get("source", "bot")
            
            # Truncar contenido largo
            if len(content) > 200:
                content = content[:200] + "..."
            
            # Icono según fuente
            icon = "👤" if msg_source == "personal" else "🤖"
            
            lines.append(f"{icon} {sender} ({dt}):")
            lines.append(f"   {content}")
            lines.append("")
        
        return "\n".join(lines)
        
    except Exception as e:
        logger.error(f"Error searching messages: {e}")
        return f"❌ Error al buscar mensajes: {str(e)}"


def _check_whatsapp_memory_requirements():
    """Check if WhatsApp memory is available."""
    try:
        from hermes_cli.config import get_hermes_home
        memory_dir = get_hermes_home() / "whatsapp_memory"
        return memory_dir.exists() or True  # Siempre disponible, se crea al usar
    except Exception:
        return True


# Registrar tool al importar el módulo
from tools.registry import registry
registry.register(
    name="search_whatsapp_memory",
    toolset="whatsapp",
    schema=SEARCH_WHATSAPP_MEMORY_SCHEMA,
    handler=_handle_search_whatsapp_memory,
    check_fn=_check_whatsapp_memory_requirements,
    emoji="📱",
)
