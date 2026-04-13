"""
WhatsMeow Python Client - Para consultar mensajes de WhatsApp personal.

Integra con el gateway existente para proveer lectura de mensajes
sin modificar el flujo de Baileys para el bot oficial.
"""

import asyncio
import json
import logging
from typing import List, Dict, Optional
import aiohttp

logger = logging.getLogger(__name__)

class WhatsMeowClient:
    """
    Cliente para consultar mensajes de WhatsMeow (números personales).
    
    NO envía mensajes, solo lee desde la API local.
    """
    
    def __init__(self, host: str = "127.0.0.1", port: int = 3002):
        self.base_url = f"http://{host}:{port}"
        self.session: Optional[aiohttp.ClientSession] = None
        
    async def _get_session(self) -> aiohttp.ClientSession:
        if self.session is None or self.session.closed:
            self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=10))
        return self.session
    
    async def health_check(self) -> bool:
        """Verificar si WhatsMeow está conectado."""
        try:
            session = await self._get_session()
            async with session.get(f"{self.base_url}/health") as resp:
                if resp.status == 200:
                    data = await resp.json()
                    return data.get("connected", False) and data.get("logged_in", False)
        except Exception as e:
            logger.debug(f"WhatsMeow health check failed: {e}")
        return False
    
    async def get_messages(self, limit: int = 100) -> List[Dict]:
        """Obtener mensajes recientes."""
        try:
            session = await self._get_session()
            async with session.get(f"{self.base_url}/messages") as resp:
                if resp.status == 200:
                    messages = await resp.json()
                    return messages[-limit:] if len(messages) > limit else messages
        except Exception as e:
            logger.error(f"Error getting messages: {e}")
        return []
    
    async def get_messages_from(self, contact: str) -> List[Dict]:
        """Obtener mensajes de un contacto específico.
        
        Args:
            contact: Nombre o JID del contacto (ej: "Gatita" o "56912345678@s.whatsapp.net")
        """
        messages = await self.get_messages(limit=1000)
        
        filtered = []
        for msg in messages:
            if contact.lower() in msg.get("name", "").lower() or                contact in msg.get("jid", "") or                contact in msg.get("sender", ""):
                filtered.append(msg)
        
        return filtered
    
    async def get_contacts(self) -> Dict[str, str]:
        """Obtener lista de contactos (basado en mensajes recibidos)."""
        try:
            session = await self._get_session()
            async with session.get(f"{self.base_url}/contacts") as resp:
                if resp.status == 200:
                    return await resp.json()
        except Exception as e:
            logger.error(f"Error getting contacts: {e}")
        return {}
    
    async def get_status(self) -> Dict:
        """Obtener estado de conexión."""
        try:
            session = await self._get_session()
            async with session.get(f"{self.base_url}/status") as resp:
                if resp.status == 200:
                    return await resp.json()
        except Exception as e:
            logger.error(f"Error getting status: {e}")
        return {"connected": False, "logged_in": False, "messages_count": 0}
    
    async def search_messages(self, query: str) -> List[Dict]:
        """Buscar mensajes por texto.
        
        Args:
            query: Texto a buscar en los mensajes
        """
        messages = await self.get_messages(limit=1000)
        
        results = []
        for msg in messages:
            if query.lower() in msg.get("message", "").lower():
                results.append(msg)
        
        return results
    
    async def close(self):
        """Cerrar sesión HTTP."""
        if self.session and not self.session.closed:
            await self.session.close()


# Instancia singleton para reutilizar
_whatsmeow_client: Optional[WhatsMeowClient] = None

def get_whatsmeow_client(host: str = "127.0.0.1", port: int = 3002) -> WhatsMeowClient:
    """Obtener instancia del cliente WhatsMeow."""
    global _whatsmeow_client
    if _whatsmeow_client is None:
        _whatsmeow_client = WhatsMeowClient(host, port)
    return _whatsmeow_client


# Funciones de conveniencia para skills
def format_messages_for_context(messages: List[Dict]) -> str:
    """Formatear mensajes como contexto para la IA."""
    if not messages:
        return "No hay mensajes disponibles."
    
    lines = []
    for msg in messages[-20:]:  # Últimos 20 mensajes
        time_str = msg.get("timestamp", "").split("T")[0] if "T" in str(msg.get("timestamp", "")) else ""
        name = msg.get("name", "Desconocido")
        text = msg.get("message", "")
        lines.append(f"[{time_str}] {name}: {text}")
    
    return "\n".join(lines)
