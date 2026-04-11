#!/usr/bin/env python3
"""
WhatsApp Memory Tool - Búsqueda en memoria de contactos de WhatsApp

Permite al agente buscar mensajes previos de contactos para poder
responder con contexto: "Juanito te dijo..." en lugar de perder la
referencia de quién dijo qué.

Este tool es "bajo demanda" - no inyecta nada al system prompt,
solo se usa cuando el agente decide que necesita contexto de 
conversaciones previas.
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, Any, Optional

# Asegurar que el path del proyecto esté disponible para imports
HERMES_ROOT = Path(__file__).resolve().parents[1]
if str(HERMES_ROOT) not in sys.path:
    sys.path.insert(0, str(HERMES_ROOT))

from tools.registry import registry


def check_whatsapp_memory_requirements() -> bool:
    """
    Verifica si el store de WhatsApp está disponible.
    Siempre retorna True - el tool está disponible pero puede no tener datos.
    """
    try:
        from gateway.platforms.whatsapp_contact_store import WhatsAppContactStore
        return True
    except ImportError:
        return False


def search_whatsapp_memory(
    query: str, 
    search_type: str = "auto", 
    limit: int = 10,
    task_id: str = None
) -> str:
    """
    Busca en la memoria de contactos de WhatsApp.
    
    Úsalo cuando el usuario pregunte sobre:
    - "qué me dijo [alguien]"
    - "recuerdas lo que dijo [alguien] sobre [tema]"
    - "qué conversamos con [alguien]"
    - Necesitas contexto de conversaciones previas con un contacto
    
    La búsqueda retorna mensajes en formato:
    "Juanito te dijo: [mensaje]"
    
    Args:
        query: Nombre del contacto (ej: "Juanito") o texto a buscar
        search_type: Tipo de búsqueda - "auto", "contact" (por nombre/número), 
                     "content" (buscar texto en mensajes)
        limit: Máximo de mensajes a retornar (default: 10)
        
    Returns:
        JSON string con resultados formateados
    """
    try:
        from gateway.platforms.whatsapp_contact_store import WhatsAppContactStore
    except ImportError as e:
        return json.dumps({
            "success": False,
            "error": f"WhatsAppContactStore no disponible: {e}",
            "query": query
        }, ensure_ascii=False)
    
    if not query or not query.strip():
        return json.dumps({
            "success": False,
            "error": "Query vacío. Proporciona un nombre de contacto o texto a buscar.",
            "query": query
        }, ensure_ascii=False)
    
    store = WhatsAppContactStore()
    
    # Ejecutar búsqueda según tipo
    if search_type == "contact":
        results = store.search_by_contact(query, limit)
    elif search_type == "content":
        results = store.search_by_content(query, limit)
    else:  # auto
        # Primero buscar como contacto (más común)
        results = store.search_by_contact(query, limit)
        # Si no hay resultados, buscar en contenido
        if not results:
            results = store.search_by_content(query, limit)
    
    # Formatear para el agente
    formatted = store.format_for_agent(results)
    
    return json.dumps({
        "success": True,
        "query": query,
        "search_type": search_type,
        "results_count": len(results),
        "formatted_context": formatted,
        "raw_results": results
    }, ensure_ascii=False, default=str)


def get_whatsapp_stats(task_id: str = None) -> str:
    """
    Retorna estadísticas de la memoria de WhatsApp.
    Útil para debugging o ver cuántos contactos/mensajes se han guardado.
    """
    try:
        from gateway.platforms.whatsapp_contact_store import WhatsAppContactStore
        store = WhatsAppContactStore()
        stats = store.get_stats()
        
        return json.dumps({
            "success": True,
            "stats": stats
        }, ensure_ascii=False)
    except Exception as e:
        return json.dumps({
            "success": False,
            "error": str(e)
        }, ensure_ascii=False)


# ============================================================================
# Registro de Tools
# ============================================================================

registry.register(
    name="search_whatsapp_memory",
    toolset="whatsapp",
    schema={
        "name": "search_whatsapp_memory",
        "description": (
            "Busca mensajes recientes de contactos de WhatsApp. "
            "Úsalo cuando el usuario pregunte 'qué me dijo X', 'recuerdas lo que dijo Y sobre Z', "
            "o necesites contexto de conversaciones previas con contactos. "
            "Siempre refiere a los mensajes como 'Juanito te dijo...' - el usuario es el dueño, "
            "tú solo ves sus mensajes. "
            "Ejemplos de uso: query='Juanito', query='presupuesto de emergencia', query='56912345678'"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "Nombre del contacto, número de teléfono, o texto a buscar. "
                        "Ejemplos: 'Juanito', 'Maria', '56912345678', 'presupuesto'"
                    )
                },
                "search_type": {
                    "type": "string",
                    "enum": ["auto", "contact", "content"],
                    "description": (
                        "Tipo de búsqueda: 'contact' busca por nombre/número, "
                        "'content' busca texto dentro de mensajes, 'auto' intenta ambos"
                    ),
                    "default": "auto"
                },
                "limit": {
                    "type": "integer",
                    "description": "Máximo de mensajes a retornar por contacto",
                    "default": 10,
                    "minimum": 1,
                    "maximum": 50
                }
            },
            "required": ["query"]
        }
    },
    handler=lambda args, **kw: search_whatsapp_memory(
        query=args.get("query", ""),
        search_type=args.get("search_type", "auto"),
        limit=args.get("limit", 10),
        task_id=kw.get("task_id")
    ),
    check_fn=check_whatsapp_memory_requirements,
)

registry.register(
    name="get_whatsapp_memory_stats",
    toolset="whatsapp",
    schema={
        "name": "get_whatsapp_memory_stats",
        "description": (
            "Obtiene estadísticas de la memoria de WhatsApp: "
            "cuántos contactos guardados, total de mensajes, etc. "
            "Útil para debugging o verificar que la memoria está funcionando."
        ),
        "parameters": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    handler=lambda args, **kw: get_whatsapp_stats(task_id=kw.get("task_id")),
    check_fn=check_whatsapp_memory_requirements,
)


def check_whatsapp_memory_tool():
    """Función auxiliar para verificar que el tool cargó correctamente."""
    return {
        "registered_tools": ["search_whatsapp_memory", "get_whatsapp_memory_stats"],
        "requirements_met": check_whatsapp_memory_requirements()
    }
