"""
WhatsApp Contact Store - Persistencia de mensajes para contexto/memoria.

Almacena mensajes de WhatsApp (tanto bot como personal) en formato JSONL
para búsqueda y recuperación posterior.
"""
import json
import logging
import os
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any

logger = logging.getLogger(__name__)


class WhatsAppContactStore:
    """
    Almacenamiento persistente de mensajes de WhatsApp.
    
    Formato: ~/.hermes/whatsapp_memory/{contact_id}.jsonl
    Cada línea es un JSON con: timestamp, sender, content, message_type, source
    """
    
    def __init__(self, memory_dir: Optional[Path] = None):
        """
        Inicializar el contact store.
        
        Args:
            memory_dir: Directorio para almacenar mensajes. 
                       Default: ~/.hermes/whatsapp_memory
        """
        if memory_dir is None:
            from hermes_cli.config import get_hermes_home
            self._memory_dir = get_hermes_home() / "whatsapp_memory"
        else:
            self._memory_dir = Path(memory_dir)
            
        # Asegurar que existe
        self._memory_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"WhatsAppContactStore initialized at {self._memory_dir}")
    
    def save_message(
        self, 
        contact_id: str, 
        sender: str, 
        content: str,
        message_type: str = "text",
        source: str = "bot",  # "bot" o "personal"
        timestamp: Optional[float] = None,
        metadata: Optional[Dict[str, Any]] = None
    ) -> bool:
        """
        Guardar un mensaje en el store.
        
        Args:
            contact_id: ID del contacto (número de teléfono o grupo)
            sender: Quién envió el mensaje
            content: Contenido del mensaje
            message_type: Tipo de mensaje (text, image, document, etc.)
            source: Origen del mensaje ("bot" o "personal")
            timestamp: Timestamp Unix (default: ahora)
            metadata: Metadatos adicionales
            
        Returns:
            True si se guardó correctamente
        """
        try:
            # Sanitizar contact_id para nombre de archivo
            safe_contact = self._sanitize_filename(contact_id)
            contact_file = self._memory_dir / f"{safe_contact}.jsonl"
            
            entry = {
                "timestamp": timestamp or time.time(),
                "datetime": datetime.fromtimestamp(timestamp or time.time()).isoformat(),
                "sender": sender,
                "content": content,
                "message_type": message_type,
                "source": source,
                "metadata": metadata or {}
            }
            
            # Append al archivo
            with open(contact_file, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
            
            logger.debug(f"Saved message from {sender} to {contact_file}")
            return True
            
        except Exception as e:
            logger.error(f"Error saving message: {e}")
            return False
    
    def search_messages(
        self,
        query: Optional[str] = None,
        contact: Optional[str] = None,
        source: Optional[str] = None,  # "bot", "personal", o None (todos)
        limit: int = 20,
        since: Optional[float] = None,
        until: Optional[float] = None
    ) -> List[Dict[str, Any]]:
        """
        Buscar mensajes en el store.
        
        Args:
            query: Texto a buscar en el contenido
            contact: Filtrar por contacto específico
            source: Filtrar por origen ("bot", "personal")
            limit: Máximo de resultados
            since: Timestamp Unix mínimo
            until: Timestamp Unix máximo
            
        Returns:
            Lista de mensajes ordenados por timestamp (más recientes primero)
        """
        results = []
        query_lower = query.lower() if query else None
        contact_lower = contact.lower() if contact else None
        
        # Always scan all files — contact filtering is done by sender name,
        # not by filename (files are named by phone number / LID).
        files = list(self._memory_dir.glob("*.jsonl"))
        
        for file_path in files:
            if not file_path.exists():
                continue
                
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    for line in f:
                        try:
                            entry = json.loads(line.strip())
                            
                            # Filtros
                            if source and entry.get("source") != source:
                                continue
                            if since and entry.get("timestamp", 0) < since:
                                continue
                            if until and entry.get("timestamp", 0) > until:
                                continue
                            # Filter by contact: match against sender name
                            if contact_lower and contact_lower not in entry.get("sender", "").lower():
                                continue
                            # Filter by query keywords — only when no contact
                            # was specified.  When a contact IS specified we
                            # return the full conversation so the model can
                            # reason semantically over it.
                            if query_lower and not contact_lower:
                                searchable = f"{entry.get('content', '')} {entry.get('sender', '')}".lower()
                                query_words = query_lower.split()
                                if not any(w in searchable for w in query_words):
                                    continue
                            
                            results.append(entry)
                            
                        except json.JSONDecodeError:
                            continue
                            
            except Exception as e:
                logger.warning(f"Error reading {file_path}: {e}")
        
        # Ordenar por timestamp (más recientes primero) y limitar
        results.sort(key=lambda x: x.get("timestamp", 0), reverse=True)
        return results[:limit]
    
    def get_recent_messages(
        self,
        contact: str,
        limit: int = 10,
        source: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        """
        Obtener mensajes recientes de un contacto.
        
        Args:
            contact: ID del contacto
            limit: Cuántos mensajes obtener
            source: Filtrar por origen
            
        Returns:
            Lista de mensajes ordenados cronológicamente (más antiguos primero)
        """
        messages = self.search_messages(
            contact=contact,
            source=source,
            limit=limit
        )
        # Revertir para orden cronológico
        messages.reverse()
        return messages
    
    def get_contacts(self) -> List[str]:
        """Obtener lista de todos los contactos con mensajes guardados."""
        contacts = []
        for file_path in self._memory_dir.glob("*.jsonl"):
            contact_id = file_path.stem
            contacts.append(contact_id)
        return sorted(contacts)
    
    def get_stats(self) -> Dict[str, Any]:
        """Obtener estadísticas del store."""
        stats = {
            "total_contacts": 0,
            "total_messages": 0,
            "by_source": {"bot": 0, "personal": 0},
            "oldest_message": None,
            "newest_message": None
        }
        
        for file_path in self._memory_dir.glob("*.jsonl"):
            stats["total_contacts"] += 1
            
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    for line in f:
                        try:
                            entry = json.loads(line.strip())
                            stats["total_messages"] += 1
                            
                            source = entry.get("source", "bot")
                            if source in stats["by_source"]:
                                stats["by_source"][source] += 1
                            
                            ts = entry.get("timestamp")
                            if ts:
                                if stats["oldest_message"] is None or ts < stats["oldest_message"]:
                                    stats["oldest_message"] = ts
                                if stats["newest_message"] is None or ts > stats["newest_message"]:
                                    stats["newest_message"] = ts
                                    
                        except json.JSONDecodeError:
                            continue
            except Exception as e:
                logger.warning(f"Error reading stats from {file_path}: {e}")
        
        return stats
    
    def clear_contact(self, contact: str) -> bool:
        """Eliminar todos los mensajes de un contacto."""
        try:
            safe_contact = self._sanitize_filename(contact)
            contact_file = self._memory_dir / f"{safe_contact}.jsonl"
            if contact_file.exists():
                contact_file.unlink()
            return True
        except Exception as e:
            logger.error(f"Error clearing contact {contact}: {e}")
            return False
    
    def _sanitize_filename(self, contact_id: str) -> str:
        """Sanitizar ID de contacto para nombre de archivo seguro."""
        # Reemplazar caracteres no seguros
        safe = "".join(c if c.isalnum() or c in "_-" else "_" for c in contact_id)
        return safe[:100]  # Limitar longitud
