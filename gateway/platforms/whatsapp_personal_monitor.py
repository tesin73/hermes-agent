"""
WhatsApp Personal Monitor - Adapter SOLO LECTURA para contexto del usuario.

Este adapter se conecta al WhatsApp personal del usuario (número TIGO) y:
- Lee todos los mensajes entrantes (read-only)
- Los guarda en WhatsAppContactStore para memoria/contexto
- NUNCA envía mensajes (garantía de seguridad)
- Funciona en paralelo al WhatsAppAdapter del bot (número MOVISTAR)

Arquitectura Dual:
  Bot (MOVISTAR)      Personal (TIGO)
     Port 3000            Port 3001
     Bidireccional        Read-only
     session/             session-personal/
"""
import asyncio
import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional, Any, Dict, List

_IS_WINDOWS = sys.platform.startswith("win")

# Asegurar que podemos importar desde el gateway
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from gateway.config import Platform, PlatformConfig
from gateway.platforms.base import (
    BasePlatformAdapter,
    MessageEvent,
    MessageType,
    SendResult,
)
from hermes_cli.config import get_hermes_home

logger = logging.getLogger(__name__)


class WhatsAppPersonalMonitor(BasePlatformAdapter):
    """
    Adapter SOLO LECTURA para monitorear WhatsApp personal.
    
    Diferencias clave con WhatsAppAdapter:
    - Puerto 3001 (vs 3000 del bot)
    - Sesión: session-personal/ (vs session/)
    - send_message() bloqueado (RuntimeError)
    - Solo almacena mensajes, nunca responde
    """
    
    # Default bridge location - use persistent volume if available
    _PERSISTENT_BRIDGE_DIR = Path("/opt/data/whatsapp-bridge")
    _DEFAULT_BRIDGE_DIR = _PERSISTENT_BRIDGE_DIR if (_PERSISTENT_BRIDGE_DIR / "node_modules").exists() else Path(__file__).resolve().parents[2] / "scripts" / "whatsapp-bridge"
    
    def __init__(self, config: Optional[PlatformConfig] = None):
        """Inicializar el adapter personal."""
        # Config por defecto si no se provee
        if config is None:
            config = PlatformConfig(
                enabled=True,
                extra={
                    "bridge_port": 3001,
                    "mode": "personal-monitor",
                    "session_path": str(get_hermes_home() / "whatsapp" / "session-personal"),
                }
            )
        
        super().__init__(config, Platform.WHATSAPP)
        
        # Identificación (name es property en base, usar _name para evitar conflicto)
        self._adapter_name = "whatsapp-personal"
        self._mode = "personal-monitor"  # Modo solo lectura
        
        # Configuración de conexión
        self._bridge_port: int = config.extra.get("bridge_port", 3001)
        self._bridge_host: str = config.extra.get("bridge_host", "127.0.0.1")
        self._bridge_script: Path = Path(config.extra.get(
            "bridge_script",
            str(self._DEFAULT_BRIDGE_DIR / "bridge.js"),
        ))
        self._session_path: Path = Path(config.extra.get(
            "session_path",
            get_hermes_home() / "whatsapp" / "session-personal"
        ))
        
        # Estado
        self._bridge_process: Optional[subprocess.Popen] = None
        self._poll_task: Optional[asyncio.Task] = None
        self._http_session: Optional[Any] = None
        self._is_running: bool = False
        
        # Contact Store para persistencia
        self._contact_store: Optional[Any] = None
        self._init_contact_store()
        
        logger.info(f"WhatsAppPersonalAdapter initialized (port {self._bridge_port})")
    
    def _init_contact_store(self):
        """Inicializar el contact store para guardar mensajes."""
        try:
            from .whatsapp_contact_store import WhatsAppContactStore
            self._contact_store = WhatsAppContactStore()
            logger.info("Contact store initialized for personal adapter")
        except ImportError as e:
            logger.warning(f"Could not import WhatsAppContactStore: {e}")
            self._contact_store = None
    
    async def check_ready(self) -> tuple[bool, str]:
        """
        Verificar si la sesión está lista para conectar.
        
        Returns:
            (is_ready, message)
        """
        # Verificar que existe sesión
        creds_file = self._session_path / "creds.json"
        if not creds_file.exists():
            return False, (
                f"Personal WhatsApp session not found at {self._session_path}.\n"
                f"Run: hermes whatsapp-personal"
            )
        
        # [TIAMAT HACK] Forzar conexión ignorando registered
        # Baileys a veces no marca registered=true pero funciona igual
        try:
            creds = json.loads(creds_file.read_text())
            # Ignorar check de registered
            phone = creds.get("me", {}).get("id", "unknown")
            registered = creds.get("registered", False)
            
            if not registered:
                logger.warning(f"[TIAMAT HACK] Session not officially registered but attempting connection anyway (registered: {registered})")
            
            return True, f"Personal WhatsApp ready (phone: {phone}, registered: {registered})"
            
            phone = creds.get("me", {}).get("id", "unknown")
            return True, f"Personal WhatsApp ready (phone: {phone})"
            
        except json.JSONDecodeError:
            return False, f"Invalid creds.json at {self._session_path}"
        except Exception as e:
            return False, f"Error checking session: {e}"
    
    async def start(self) -> bool:
        """
        Iniciar el adapter y conectar al bridge.
        
        Returns:
            True si se conectó exitosamente
        """
        # Verificar que estamos listos
        ready, msg = await self.check_ready()
        if not ready:
            logger.error(f"WhatsApp Personal not ready: {msg}")
            return False
        
        logger.info(f"Starting WhatsApp Personal adapter...")
        
        # Importar aiohttp
        try:
            import aiohttp
            self._http_session = aiohttp.ClientSession()
        except ImportError:
            logger.error("aiohttp is required for WhatsApp adapter")
            return False
        
        # Iniciar bridge como proceso separado
        if not await self._start_bridge():
            return False
        
        # Esperar a que el bridge esté listo
        if not await self._wait_for_bridge():
            logger.error("Bridge did not become ready")
            await self.stop()
            return False
        
        # Iniciar polling de mensajes
        self._is_running = True
        self._poll_task = asyncio.create_task(self._poll_messages_loop())
        
        logger.info("✅ WhatsApp Personal adapter started (read-only mode)")
        return True
    
    async def _start_bridge(self) -> bool:
        """Iniciar el bridge de Node.js."""
        if not self._bridge_script.exists():
            logger.error(f"Bridge script not found: {self._bridge_script}")
            return False
        
        # Construir comando
        cmd = [
            "node",
            str(self._bridge_script),
            "--port", str(self._bridge_port),
            "--session", str(self._session_path),
            "--mode", self._mode,
        ]
        
        try:
            logger.info(f"Starting bridge: {' '.join(cmd)}")
            
            # Redirigir output/logs
            log_file = self._session_path.parent / "bridge-personal.log"
            log_file.parent.mkdir(parents=True, exist_ok=True)
            
            with open(log_file, "a") as log_fh:
                self._bridge_process = subprocess.Popen(
                    cmd,
                    stdout=log_fh,
                    stderr=subprocess.STDOUT,
                )
            
            logger.info(f"Bridge process started (PID: {self._bridge_process.pid})")
            return True
            
        except Exception as e:
            logger.error(f"Failed to start bridge: {e}")
            return False
    
    async def _wait_for_bridge(self, timeout: int = 30) -> bool:
        """Esperar a que el bridge responda healthcheck."""
        import aiohttp
        
        url = f"http://{self._bridge_host}:{self._bridge_port}/health"
        
        for i in range(timeout):
            try:
                async with self._http_session.get(url) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        logger.info(f"Bridge ready: {data}")
                        return True
            except Exception:
                pass
            
            await asyncio.sleep(1)
        
        return False
    
    async def _poll_messages_loop(self):
        """Loop principal para obtener mensajes del bridge."""
        import aiohttp
        
        poll_url = f"http://{self._bridge_host}:{self._bridge_port}/messages"
        
        while self._is_running:
            try:
                async with self._http_session.get(poll_url) as resp:
                    if resp.status == 200:
                        data = await resp.json()
                        messages = data.get("messages", [])
                        
                        for msg_data in messages:
                            await self._process_message(msg_data)
                    else:
                        logger.warning(f"Poll returned {resp.status}")
                        
            except Exception as e:
                logger.debug(f"Poll error: {e}")
            
            await asyncio.sleep(2)  # Poll cada 2 segundos
    
    async def _process_message(self, msg_data: dict):
        """Procesar mensaje recibido - solo guardar, nunca responder."""
        try:
            sender = msg_data.get("sender", "")
            content = msg_data.get("content", "")
            msg_type = msg_data.get("type", "text")
            
            # Extraer contacto del sender (quitar sufijo @s.whatsapp.net)
            contact = sender.split("@")[0] if "@" in sender else sender
            
            logger.debug(f"Personal message from {contact}: {content[:50]}...")
            
            # Guardar en contact store
            if self._contact_store:
                self._contact_store.save_message(
                    contact_id=contact,
                    sender=sender,
                    content=content,
                    message_type=msg_type,
                    source="personal",  # Marcar como personal
                    metadata={"adapter": "whatsapp-personal"}
                )
            
            # NUNCA respondemos - solo guardamos
            # Este es el comportamiento clave "read-only"
            
        except Exception as e:
            logger.error(f"Error processing message: {e}")
    
    async def send_message(
        self, 
        recipient: str, 
        content: str, 
        **kwargs
    ) -> SendResult:
        """
        BLOQUEADO: Este adapter es SOLO LECTURA.
        
        Raises:
            RuntimeError: Siempre, ya que no se pueden enviar mensajes
        """
        raise RuntimeError(
            "WhatsAppPersonalAdapter is READ-ONLY. "
            "Cannot send messages from personal number. "
            "Use the main WhatsAppAdapter for sending messages."
        )
    
    async def stop(self):
        """Detener el adapter y liberar recursos."""
        logger.info("Stopping WhatsApp Personal adapter...")
        
        self._is_running = False
        
        # Cancelar polling
        if self._poll_task and not self._poll_task.done():
            self._poll_task.cancel()
            try:
                await self._poll_task
            except asyncio.CancelledError:
                pass
        
        # Cerrar HTTP session
        if self._http_session:
            await self._http_session.close()
            self._http_session = None
        
        # Matar proceso del bridge
        if self._bridge_process:
            try:
                self._bridge_process.terminate()
                self._bridge_process.wait(timeout=5)
            except Exception:
                if self._bridge_process.poll() is None:
                    self._bridge_process.kill()
            self._bridge_process = None
        
        logger.info("WhatsApp Personal adapter stopped")
    

    # =========================================================================
    # Métodos abstractos requeridos por BasePlatformAdapter
    # =========================================================================
    
    async def connect(self) -> bool:
        """
        Conectar al bridge de WhatsApp personal.
        
        Este método es requerido por BasePlatformAdapter.
        Es un alias para start() para mantener compatibilidad.
        
        Returns:
            True si la conexión fue exitosa
        """
        return await self.start()
    
    async def disconnect(self) -> None:
        """
        Desconectar del bridge.
        
        Este método es requerido por BasePlatformAdapter.
        Es un alias para stop() para mantener compatibilidad.
        """
        await self.stop()
    
    async def get_chat_info(self, chat_id: str) -> dict:
        """
        Obtener información de un chat.
        
        Args:
            chat_id: ID del chat (número de teléfono o grupo)
            
        Returns:
            Dict con información del chat (nombre, participantes, etc.)
        """
        # Para el personal monitor, solo retornamos info básica
        # No hacemos llamadas al bridge para mantenerlo simple
        is_group = chat_id.endswith("@g.us")
        return {
            "id": chat_id,
            "name": chat_id.replace("@s.whatsapp.net", "").replace("@g.us", ""),
            "is_group": is_group,
            "participants": [],
            "source": "personal-monitor",
        }
    
    async def send(self, recipient: str, content: str, **kwargs) -> dict:
        """
        Enviar mensaje - BLOQUEADO para personal monitor.
        
        Este método es requerido por BasePlatformAdapter pero está
        deshabilitado ya que el personal monitor es SOLO LECTURA.
        
        Args:
            recipient: Destinatario del mensaje
            content: Contenido del mensaje
            **kwargs: Argumentos adicionales
            
        Raises:
            RuntimeError: Siempre, ya que no se pueden enviar mensajes
        """
        raise RuntimeError(
            "WhatsAppPersonalMonitor es SOLO LECTURA. "
            "No se pueden enviar mensajes desde el número personal. "
            "Use el WhatsAppAdapter principal (bot) para enviar mensajes."
        )

    def get_memory_stats(self) -> Dict[str, Any]:
        """Obtener estadísticas de memoria guardada."""
        if self._contact_store:
            return self._contact_store.get_stats()
        return {}
    
    def search_memory(
        self, 
        query: str, 
        limit: int = 10
    ) -> List[Dict[str, Any]]:
        """Buscar en la memoria de mensajes personales."""
        if self._contact_store:
            return self._contact_store.search_messages(
                query=query,
                source="personal",
                limit=limit
            )
        return []
