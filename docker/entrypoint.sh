#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run hermes.
set -e

HERMES_HOME="/opt/data"
INSTALL_DIR="/opt/hermes"

# Create essential directory structure.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills}

# .env - copy example if not exists
if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

# config.yaml - copy example if not exists
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

# SOUL.md
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Sync bundled skills
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

# Detect mode: if WHATSAPP_SESSION_NAME is set, run WhatsApp Bridge (headless)
if [ -n "$WHATSAPP_SESSION_NAME" ]; then
    echo "[Hermes] WhatsApp mode enabled (session: $WHATSAPP_SESSION_NAME)"
    
    # =============================================================================
    # PERSISTENCIA DE SESIÓN WHATSAPP
    # =============================================================================
    mkdir -p "$HERMES_HOME/whatsapp"
    rm -rf ~/.hermes/whatsapp 2>/dev/null || true
    mkdir -p ~/.hermes
    ln -sf "$HERMES_HOME/whatsapp" ~/.hermes/whatsapp
    
    # Auto-start the gateway (which will wait for the bridge)
    echo "[Hermes] Starting Hermes Gateway..."
    echo "[Hermes] The gateway will wait for the WhatsApp bridge to be available."
    echo "[Hermes] To start the bridge manually, run:"
    echo "  docker exec -it <container> node /opt/hermes/scripts/whatsapp-bridge/bridge.js --session /opt/data/whatsapp/session --port 3000 --mode bot"
    echo "[Hermes] Then scan the QR code with your phone."
    exec hermes gateway
else
    # Interactive CLI mode - but check if we have a terminal
    if [ -t 0 ]; then
        # Terminal available - run interactively
        exec hermes "$@"
    else
        # No terminal - keep container alive for manual exec
        echo "[Hermes] Container ready. Run commands manually with:"
        echo "  docker exec <container> hermes <command>"
        echo "  docker exec <container> hermes gateway"
        echo "[Hermes] Waiting for manual commands..."
        tail -f /dev/null
    fi
fi
