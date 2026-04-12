"""
WhatsApp Personal Monitor - Solo lectura del número personal del usuario

Este adaptador se conecta al WhatsApp personal del usuario (no el bot)
y solo guarda mensajes en el contact store para que el agente tenga
contexto de las conversaciones. NUNCA responde mensajes.

Use case Tiamat:
- El usuario tiene un número de bot (MOVISTAR) para clientes
- El usuario tiene su número personal (TIGO) para comunicación normal
- Este monitor conecta el TIGO y guarda todo en memoria
- El usuario puede preguntar: "qué me dijo Juanito"
"""

import asyncio
import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Dict, Optional, Any

from gateway.config import Platform, PlatformConfig
from gateway.platforms.base import BasePlatformAdapter

logger = logging.getLogger(__name__)


class WhatsAppPersonalMonitor(BasePlatformAdapter):
    """
    Monitor pasivo de WhatsApp personal.
    
    Diferencias clave con WhatsAppAdapter normal:
    - NUNCA responde mensajes (solo lectura)
    - No tiene lógica de menciones/allowlist
    - No inyecta eventos al gateway
    - Solo guarda en contact store
    """
    
    _DEFAULT_BRIDGE_DIR = Path(__file__).resolve().parents[2] / "scripts" / "whatsapp-bridge"
    
    def __init__(self, config: PlatformConfig):
        # Usamos Platform.WHATSAPP pero con nombre diferente para distinguir
        super().__init__(config, Platform.WHATSAPP)
        self.name = "whatsapp-personal"  # Override name
        self._bridge_process: Optional[subprocess.Popen] = None
        self._bridge_port: int = config.extra.get("bridge_port", 3001)  # Puerto diferente
        self._bridge_script: Optional[str] = config.extra.get(
            "bridge_script",
            str(self._DEFAULT_BRIDGE_DIR / "bridge.js"),
        )
        self._session_path: Path = Path(config.extra.get(
            "session_path",
            self._get_default_session_path()
        ))
        self._poll_task: Optional[asyncio.Task] = None
        self._http_session: Optional["aiohttp.ClientSession"] = None
        
        # [TIAMAT] Contact store compartido con el bot principal
        self._contact_store: Optional[Any] = None
        try:
            from .whatsapp_contact_store import WhatsAppContactStore
            self._contact_store = WhatsAppContactStore()
        except Exception:
            pass
    
    def _get_default_session_path(self) -> Path:
        """Path por defecto para la sesión personal.
        
        En Docker/Coolify, las sesiones están en /opt/data (volumen persistente).
        En desarrollo local, usan ~/.hermes (HERMES_HOME).
        """
        from hermes_constants import get_hermes_dir
        
        # En Docker, el volumen se monta en /opt/data y se symlink a ~/.hermes
        # Pero si el symlink no existe, buscamos directamente en /opt/data
        docker_path = Path("/opt/data/whatsapp/session-personal")
        if docker_path.exists() or Path("/.dockerenv").exists():
            # Estamos en Docker o la sesión ya existe en /opt/data
            docker_path.parent.mkdir(parents=True, exist_ok=True)
            return docker_path
        
        # Fallback: usar el layout estándar de hermes
        return get_hermes_dir("platforms/whatsapp/session-personal", "whatsapp/session-personal")
    
    @property
    def requires_credentials(self) -> bool:
        """No requiere credenciales - usa QR pairing igual que el bot."""
        return False
    
    def check_ready(self) -> tuple[bool, str]:
        """Verifica si está listo para monitorear."""
        creds_file = self._session_path / "creds.json"
        if not creds_file.exists():
            return False, f"WhatsApp personal no emparejado. Ejecuta: hermes whatsapp-personal"
        
        try:
            with open(creds_file) as f:
                data = json.load(f)
            if not data.get("registered"):
                return False, "Sesión personal no registrada. Re-empareja con: hermes whatsapp-personal"
        except Exception as e:
            return False, f"Error leyendo sesión personal: {e}"
        
        return True, "Listo"
    
    async def start(self) -> bool:
        """Inicia el monitor (bridge + polling)."""
        ready, msg = self.check_ready()
        if not ready:
            logger.warning("[WhatsApp Personal] %s", msg)
            print(f"⚠️  {msg}")
            return False
        
        print(f"🔍 Iniciando WhatsApp Personal Monitor en puerto {self._bridge_port}")
        
        # Asegurar que el directorio de sesión existe
        self._session_path.mkdir(parents=True, exist_ok=True)
        
        # Iniciar bridge
        if not await self._start_bridge():
            return False
        
        # Iniciar polling
        self._running = True
        self._poll_task = asyncio.create_task(self._poll_messages())
        
        print("✅ WhatsApp Personal Monitor activo (solo lectura)")
        return True
    
    async def stop(self) -> None:
        """Detiene el monitor."""
        self._running = False
        
        if self._poll_task:
            self._poll_task.cancel()
            try:
                await self._poll_task
            except asyncio.CancelledError:
                pass
            self._poll_task = None
        
        if self._http_session:
            await self._http_session.close()
            self._http_session = None
        
        if self._bridge_process:
            self._bridge_process.terminate()
            try:
                await asyncio.wait_for(
                    asyncio.get_event_loop().run_in_executor(None, self._bridge_process.wait),
                    timeout=5
                )
            except asyncio.TimeoutError:
                self._bridge_process.kill()
            self._bridge_process = None
        
        print("🛑 WhatsApp Personal Monitor detenido")
    
    async def _start_bridge(self) -> bool:
        """Inicia el bridge de Baileys."""
        import aiohttp
        
        self._http_session = aiohttp.ClientSession()
        
        # Verificar si el bridge ya está corriendo
        try:
            async with self._http_session.get(
                f"http://127.0.0.1:{self._bridge_port}/health",
                timeout=aiohttp.ClientTimeout(total=2)
            ) as resp:
                if resp.status == 200:
                    logger.info("[WhatsApp Personal] Bridge ya está corriendo en puerto %s", self._bridge_port)
                    return True
        except Exception:
            pass
        
        # Iniciar proceso del bridge
        bridge_cmd = [
            "node",
            str(self._bridge_script),
            "--session", str(self._session_path),
            "--port", str(self._bridge_port),
            "--mode", "personal-monitor",  # Modo especial: no envía mensajes
        ]
        
        try:
            self._bridge_process = subprocess.Popen(
                bridge_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            
            # Esperar a que el bridge esté listo
            for attempt in range(30):
                await asyncio.sleep(0.5)
                try:
                    async with self._http_session.get(
                        f"http://127.0.0.1:{self._bridge_port}/health",
                        timeout=aiohttp.ClientTimeout(total=1)
                    ) as resp:
                        if resp.status == 200:
                            logger.info("[WhatsApp Personal] Bridge iniciado en puerto %s", self._bridge_port)
                            return True
                except Exception:
                    continue
            
            logger.error("[WhatsApp Personal] Bridge no respondió en 15 segundos")
            return False
            
        except Exception as e:
            logger.error("[WhatsApp Personal] Error iniciando bridge: %s", e)
            return False
    
    async def _poll_messages(self) -> None:
        """Poll del bridge para mensajes entrantes (solo lectura)."""
        import aiohttp
        
        while self._running:
            if not self._http_session:
                break
            
            try:
                async with self._http_session.get(
                    f"http://127.0.0.1:{self._bridge_port}/messages",
                    timeout=aiohttp.ClientTimeout(total=30)
                ) as resp:
                    if resp.status == 200:
                        messages = await resp.json()
                        for msg_data in messages:
                            # Solo guardar en contact store, NUNCA procesar como comando
                            self._store_message(msg_data)
                            
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.debug("[WhatsApp Personal] Error en poll: %s", e)
                await asyncio.sleep(5)
            
            await asyncio.sleep(1)
    
    def _store_message(self, msg_data: Dict[str, Any]) -> None:
        """
        Guarda mensaje en el contact store.
        Este método NUNCA genera respuestas - solo almacena.
        """
        if not self._contact_store:
            return
        
        try:
            sender_id = msg_data.get("senderId", "")
            sender_name = msg_data.get("senderName", "")
            body = msg_data.get("body", "")
            is_from_me = msg_data.get("fromMe", False)
            chat_id = msg_data.get("chatId", "")
            
            if not body:
                return
            
            # Guardar tanto mensajes recibidos como enviados por el usuario
            # Para tener contexto completo de la conversación
            self._contact_store.store_message(
                phone=sender_id,
                name=sender_name,
                body=body,
                from_me=is_from_me,
                chat_id=chat_id
            )
            
            # Log silencioso para debugging
            logger.debug("[WhatsApp Personal] Guardado mensaje de %s", sender_name or sender_id)
            
        except Exception as e:
            logger.debug("[WhatsApp Personal] Error guardando mensaje: %s", e)
    
    # =========================================================================
    # Abstract methods required by BasePlatformAdapter
    # =========================================================================
    
    async def connect(self) -> bool:
        """Connect to the platform and start receiving messages."""
        return await self.start()
    
    async def disconnect(self) -> None:
        """Disconnect from the platform."""
        await self.stop()
    
    async def send(self, chat_id: str, content: str, reply_to: Optional[str] = None, metadata: Optional[Dict[str, Any]] = None) -> Any:
        """
        BLOQUEADO: Este adaptador NUNCA envía mensajes.
        WhatsApp Personal Monitor es SOLO LECTURA.
        """
        from gateway.platforms.base import SendResult
        logger.warning("[WhatsApp Personal] Intento de enviar mensaje bloqueado: %s", chat_id)
        return SendResult(
            success=False,
            error="WhatsApp Personal Monitor es SOLO LECTURA. "
                  "No puede enviar mensajes. Usa el WhatsApp principal (bot) para responder."
        )
    
    async def send_message(self, recipient: str, content: str, **kwargs) -> None:
        """
        BLOQUEADO: Este adaptador NUNCA envía mensajes.
        """
        logger.warning("[WhatsApp Personal] Intento de enviar mensaje bloqueado: %s", recipient)
        raise RuntimeError(
            "WhatsApp Personal Monitor es SOLO LECTURA. "
            "No puede enviar mensajes. Usa el WhatsApp principal (bot) para responder."
        )
    
    async def get_chat_info(self, chat_id: str) -> Dict[str, Any]:
        """Obtiene info de un chat (para el agente cuando busca contexto)."""
        return {"id": chat_id, "name": chat_id, "type": "dm"}


def check_whatsapp_personal_requirements() -> bool:
    """Verifica si se pueden cumplir los requisitos del monitor personal."""
    session_path = Path.home() / ".hermes" / "whatsapp" / "session-personal"
    creds_file = session_path / "creds.json"
    
    if not creds_file.exists():
        return False
    
    try:
        with open(creds_file) as f:
            data = json.load(f)
        return data.get("registered", False)
    except Exception:
        return False
