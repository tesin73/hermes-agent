"""
WhatsApp Contact Memory Store - Persistencia ligera por contacto
NO usa MEMORY.md (limitado), archivos JSON separados ilimitados

Este módulo permite al agente recordar mensajes de contactos de WhatsApp
para poder referirse a ellos posteriormente con el formato correcto:
"Juanito te dijo..." en lugar de asumir la identidad del remitente.
"""

import json
import os
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any
from dataclasses import dataclass, asdict


@dataclass
class WhatsAppMessage:
    timestamp: str
    from_me: bool  # False = ellos te escribieron, True = tú respondiste
    body: str
    chat_id: str   # Para grupos vs DMs


class WhatsAppContactStore:
    """
    Almacén persistente de mensajes de contactos de WhatsApp.
    
    Diseñado para ser ligero y no bloqueante:
    - Guarda en JSONL (append-only, rápido)
    - Índice en memoria con sync a JSON
    - Sin dependencias externas (SQLite, etc.)
    """
    
    def __init__(self, base_path: Optional[Path] = None):
        self.base_path = base_path or Path.home() / ".hermes" / "whatsapp_memory"
        self.base_path.mkdir(parents=True, exist_ok=True)
        self._index = self._load_index()
    
    def _load_index(self) -> dict:
        """Carga el índice de contactos desde disco."""
        index_file = self.base_path / "index.json"
        if index_file.exists():
            try:
                return json.loads(index_file.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, IOError):
                return {}
        return {}
    
    def _save_index(self):
        """Guarda el índice de contactos a disco."""
        try:
            index_file = self.base_path / "index.json"
            index_file.write_text(
                json.dumps(self._index, indent=2, ensure_ascii=False),
                encoding="utf-8"
            )
        except IOError as e:
            # No fallar si no podemos escribir el índice
            pass
    
    def _contact_dir(self, phone: str) -> Path:
        """Retorna el directorio de un contacto, creándolo si no existe."""
        # Normalizar: quitar @s.whatsapp.net, @lid, etc.
        clean = phone.split("@")[0]
        # Remover caracteres no alfanuméricos para nombre de directorio seguro
        clean = "".join(c for c in clean if c.isalnum())
        path = self.base_path / clean
        path.mkdir(exist_ok=True)
        return path
    
    def store_message(self, phone: str, name: str, body: str, from_me: bool, chat_id: str):
        """
        Guarda un mensaje en el store del contacto.
        
        Args:
            phone: ID de WhatsApp (ej: 56912345678@s.whatsapp.net)
            name: Nombre mostrado del contacto
            body: Contenido del mensaje
            from_me: True si es mensaje enviado por el usuario, False si recibido
            chat_id: ID del chat (para diferenciar grupos vs DMs)
        """
        if not body or not phone:
            return
        
        now = datetime.utcnow().isoformat()
        
        # Actualizar índice si es necesario
        needs_save = False
        if phone not in self._index:
            self._index[phone] = {
                "name": name or phone.split("@")[0],
                "first_seen": now,
                "last_active": now
            }
            needs_save = True
        elif name and name != self._index[phone].get("name"):
            # Actualizar nombre si cambió
            self._index[phone]["name"] = name
            self._index[phone]["last_active"] = now
            needs_save = True
        else:
            # Solo actualizar last_active si pasaron más de 5 minutos
            last = self._index[phone].get("last_active", "")
            if last:
                try:
                    last_dt = datetime.fromisoformat(last)
                    if datetime.utcnow() - last_dt > timedelta(minutes=5):
                        self._index[phone]["last_active"] = now
                        needs_save = True
                except:
                    self._index[phone]["last_active"] = now
                    needs_save = True
            else:
                self._index[phone]["last_active"] = now
                needs_save = True
        
        if needs_save:
            self._save_index()
        
        # Guardar mensaje en JSONL (append-only)
        msg = WhatsAppMessage(
            timestamp=now,
            from_me=from_me,
            body=body[:2000],  # Truncar mensajes muy largos
            chat_id=chat_id
        )
        
        try:
            contact_dir = self._contact_dir(phone)
            messages_file = contact_dir / "messages.jsonl"
            
            with open(messages_file, "a", encoding="utf-8") as f:
                f.write(json.dumps(asdict(msg), ensure_ascii=False) + "\n")
        except IOError:
            # No bloquear el flujo principal si falla escritura
            pass
    
    def search_by_contact(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Busca contacto por nombre o número, retorna últimos mensajes.
        
        Args:
            query: Nombre del contacto, número parcial, etc.
            limit: Máximo de mensajes por contacto
            
        Returns:
            Lista de dicts con contacto y mensajes
        """
        query_lower = query.lower()
        matches = []
        
        # Buscar en índice
        for phone, info in self._index.items():
            name = info.get("name", "").lower()
            phone_clean = phone.lower()
            if query_lower in name or query_lower in phone_clean:
                matches.append((phone, info))
        
        # Limitar a top 3 contactos para no sobrecargar
        results = []
        for phone, info in matches[:3]:
            messages = self._get_recent_messages(phone, limit)
            results.append({
                "contact": info["name"],
                "phone": phone,
                "first_seen": info.get("first_seen", ""),
                "last_active": info.get("last_active", ""),
                "messages": messages
            })
        
        return results
    
    def search_by_content(self, text_query: str, limit: int = 20) -> List[Dict[str, Any]]:
        """
        Busca mensajes que contengan cierto texto en cualquier contacto.
        
        Args:
            text_query: Texto a buscar en el contenido de mensajes
            limit: Máximo de mensajes por contacto
            
        Returns:
            Lista de contactos con mensajes que coinciden
        """
        results = []
        query_lower = text_query.lower()
        
        for phone, info in self._index.items():
            contact_dir = self._contact_dir(phone)
            messages_file = contact_dir / "messages.jsonl"
            
            if not messages_file.exists():
                continue
            
            try:
                matching = []
                with open(messages_file, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            msg = json.loads(line)
                            if query_lower in msg.get("body", "").lower():
                                matching.append(msg)
                        except json.JSONDecodeError:
                            continue
                
                if matching:
                    results.append({
                        "contact": info["name"],
                        "phone": phone,
                        "matches": matching[-limit:]  # Más recientes
                    })
            except IOError:
                continue
        
        # Limitar a top 5 contactos
        return results[:5]
    
    def get_contact_by_phone(self, phone: str, limit: int = 20) -> Optional[Dict[str, Any]]:
        """
        Obtiene mensajes de un contacto específico por su número exacto.
        
        Args:
            phone: Número exacto de WhatsApp
            limit: Máximo de mensajes a retornar
            
        Returns:
            Dict con contacto y mensajes, o None si no existe
        """
        if phone not in self._index:
            return None
        
        info = self._index[phone]
        messages = self._get_recent_messages(phone, limit)
        
        return {
            "contact": info["name"],
            "phone": phone,
            "first_seen": info.get("first_seen", ""),
            "last_active": info.get("last_active", ""),
            "messages": messages
        }
    
    def _get_recent_messages(self, phone: str, limit: int) -> List[Dict[str, Any]]:
        """Lee los últimos N mensajes de un contacto."""
        contact_dir = self._contact_dir(phone)
        messages_file = contact_dir / "messages.jsonl"
        
        if not messages_file.exists():
            return []
        
        try:
            # Leer todas las líneas y tomar las últimas N
            # Para archivos muy grandes, esto podría optimizarse con seek
            with open(messages_file, "r", encoding="utf-8") as f:
                lines = f.readlines()
            
            # Parsear últimas N líneas válidas
            messages = []
            for line in reversed(lines):  # De atrás hacia adelante
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    messages.append(msg)
                    if len(messages) >= limit:
                        break
                except json.JSONDecodeError:
                    continue
            
            # Devolver en orden cronológico
            return list(reversed(messages))
        
        except IOError:
            return []
    
    def format_for_agent(self, search_results: List[Dict[str, Any]]) -> str:
        """
        Formatea resultados para que el agente diga 'Juanito te dijo...'
        
        Args:
            search_results: Resultados de búsqueda
            
        Returns:
            String formateado para presentar al usuario
        """
        if not search_results:
            return "No encontré mensajes recientes de ese contacto."
        
        lines = []
        for contact_data in search_results:
            name = contact_data["contact"]
            last_active = contact_data.get("last_active", "")
            
            # Formatear fecha relativa
            time_str = ""
            if last_active:
                try:
                    dt = datetime.fromisoformat(last_active)
                    delta = datetime.utcnow() - dt
                    if delta.days > 0:
                        time_str = f" (hace {delta.days} día{'s' if delta.days > 1 else ''})"
                    elif delta.seconds > 3600:
                        hours = delta.seconds // 3600
                        time_str = f" (hace {hours} hora{'s' if hours > 1 else ''})"
                    elif delta.seconds > 60:
                        mins = delta.seconds // 60
                        time_str = f" (hace {mins} min)"
                except:
                    pass
            
            lines.append(f"\n## Mensajes con {name}{time_str}:")
            
            messages = contact_data.get("messages", [])
            if contact_data.get("matches"):
                messages = contact_data["matches"]
            
            for msg in messages:
                ts = msg.get("timestamp", "")[:16].replace("T", " ") if msg.get("timestamp") else ""
                body = msg.get("body", "")[:150]  # Truncar para display
                if len(msg.get("body", "")) > 150:
                    body += "..."
                
                if msg.get("from_me"):
                    lines.append(f"- [{ts}] Tú: {body}")
                else:
                    lines.append(f"- [{ts}] {name} te dijo: {body}")
        
        return "\n".join(lines)
    
    def get_stats(self) -> Dict[str, Any]:
        """Retorna estadísticas del store para debugging."""
        total_contacts = len(self._index)
        total_messages = 0
        
        for phone in self._index.keys():
            contact_dir = self._contact_dir(phone)
            messages_file = contact_dir / "messages.jsonl"
            if messages_file.exists():
                try:
                    with open(messages_file, "r", encoding="utf-8") as f:
                        total_messages += sum(1 for _ in f if _.strip())
                except IOError:
                    pass
        
        return {
            "total_contacts": total_contacts,
            "total_messages": total_messages,
            "storage_path": str(self.base_path)
        }
