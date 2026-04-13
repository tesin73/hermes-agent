"""
WhatsApp Personal Monitor usando WhatsMeow (Go).

Solo lectura de mensajes personales vía API HTTP local.
NO modifica ni afecta al bot oficial de Baileys.
"""

import asyncio
import logging
from typing import Optional, List, Dict
import aiohttp

from .whatsmeow_client import (
    get_whatsmeow_client,
    format_messages_for_context,
    WhatsMeowClient
)

logger = logging.getLogger(__name__)


class WhatsAppPersonalMonitor:
    """
    Monitor WhatsApp personal usando WhatsMeow.
    
    Proporciona acceso READ-ONLY a mensajes de números WhatsApp
    personales conectados vía WhatsMeow.
    
    NO envía mensajes, solo consulta mensajes almacenados.
    """
    
    def __init__(self, host: str = "127.0.0.1", port: int = 3002):
        self.client = WhatsMeowClient(host, port)
        self._connected = False
        
    async def check_ready(self) -> tuple[bool, str]:
        """
        Verificar si WhatsMeow está listo.
        
        Returns:
            (is_ready, message)
        """
        try:
            health = await self.client.health_check()
            if health:
                self._connected = True
                status = await self.client.get_status()
                count = status.get("messages_count", 0)
                return True, f"WhatsMeow conectado ({count} mensajes almacenados)"
            else:
                # No está conectado, pero podría estar emparejando
                status = await self.client.get_status()
                if status.get("logged_in"):
                    return True, "WhatsMeow conectado pero sin mensajes aún"
                return False, "WhatsMeow no está conectado. Necesita emparejamiento."
        except Exception as e:
            logger.warning(f"WhatsMeow no disponible: {e}")
            return False, f"WhatsMeow no responde: {e}"
    
    async def connect(self) -> bool:
        """Conectar y verificar estado."""
        ready, msg = await self.check_ready()
        if ready:
            self._connected = True
            logger.info(f"[TIAMAT] WhatsMeow conectado: {msg}")
        else:
            logger.warning(f"[TIAMAT] {msg}")
        return ready
    
    async def get_messages_from(self, contact: str, limit: int = 100) -> List[Dict]:
        """
        Obtener mensajes de un contacto específico.
        
        Args:
            contact: Nombre o número del contacto (ej: "Gatita", "56912345678")
            limit: Máximo de mensajes a retornar
            
        Returns:
            Lista de mensajes
        """
        if not self._connected:
            await self.connect()
        
        messages = await self.client.get_messages_from(contact)
        return messages[-limit:] if len(messages) > limit else messages
    
    async def get_last_message_from(self, contact: str) -> Optional[str]:
        """
        Obtener el último mensaje de un contacto como texto formateado.
        
        Args:
            contact: Nombre o número del contacto
            
        Returns:
            Texto del último mensaje o None
        """
        messages = await self.get_messages_from(contact, limit=1)
        if messages:
            msg = messages[-1]
            sender = msg.get("name", msg.get("sender", "Desconocido"))
            text = msg.get("message", "")
            time = msg.get("timestamp", "")
            return f"[{time}] {sender}: {text}"
        return None
    
    async def get_all_recent_messages(self, limit: int = 50) -> str:
        """
        Obtener mensajes recientes formateados como contexto.
        
        Returns:
            String con mensajes formateados
        """
        messages = await self.client.get_messages(limit)
        return format_messages_for_context(messages)
    
    async def search_messages(self, query: str) -> List[Dict]:
        """Buscar mensajes por texto."""
        return await self.client.search_messages(query)
    
    async def get_contacts(self) -> Dict[str, str]:
        """Obtener contactos conocidos."""
        return await self.client.get_contacts()
    
    @property
    def is_connected(self) -> bool:
        return self._connected


# Instancia global
_monitor: Optional[WhatsAppPersonalMonitor] = None

def get_personal_monitor() -> WhatsAppPersonalMonitor:
    """Obtener instancia del monitor personal."""
    global _monitor
    if _monitor is None:
        _monitor = WhatsAppPersonalMonitor()
    return _monitor
