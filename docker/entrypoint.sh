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
    
    # Verificar si la sesión ya está emparejada
    CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"
    SESSION_READY=false
    
    if [ -f "$CREDS_FILE" ]; then
        # Verificar si registered es true
        if grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
            SESSION_READY=true
            echo "[Hermes] WhatsApp session found and registered."
        else
            echo "[Hermes] WhatsApp session exists but is NOT registered (registered: false)."
            echo "[Hermes] The previous QR scan may have been incomplete."
        fi
    else
        echo "[Hermes] No WhatsApp session found."
    fi
    
    if [ "$SESSION_READY" = "true" ]; then
        # Sesión lista: iniciar bridge en background, luego gateway
        echo "[Hermes] Starting WhatsApp Bridge in background..."
        cd "$INSTALL_DIR/scripts/whatsapp-bridge"
        
        # Iniciar bridge en background, guardar logs
        nohup node bridge.js \
            --port 3000 \
            --session "$HERMES_HOME/whatsapp/session" \
            --mode "${WHATSAPP_MODE:-bot}" \
            > "$HERMES_HOME/whatsapp/bridge.log" 2>&1 &
        
        BRIDGE_PID=$!
        echo "[Hermes] Bridge started with PID: $BRIDGE_PID"
        
        # Esperar a que el bridge esté listo (health check)
        echo "[Hermes] Waiting for bridge to be ready..."
        for i in {1..30}; do
            sleep 1
            if curl -s http://127.0.0.1:3000/health > /dev/null 2>&1; then
                echo "[Hermes] Bridge is ready!"
                break
            fi
            if [ $i -eq 30 ]; then
                echo "[Hermes] WARNING: Bridge did not respond in 30s, but continuing..."
            fi
        done
        
        # Iniciar gateway
        echo "[Hermes] Starting Hermes Gateway..."
        exec hermes gateway
    else
        # Sesión NO lista: instrucciones claras
        echo ""
        echo "=========================================="
        echo "❌ WHATSAPP NOT CONFIGURED"
        echo "=========================================="
        echo ""
        echo "You need to pair WhatsApp before starting."
        echo ""
        echo "Step 1: Run this command to pair:"
        echo ""
        echo "  docker exec -it <container-name> node /opt/hermes/scripts/whatsapp-bridge/bridge.js --pair-only --session /opt/data/whatsapp/session --mode bot"
        echo ""
        echo "Step 2: Scan the QR code with your phone"
        echo ""
        echo "Step 3: Restart the container after pairing"
        echo ""
        echo "=========================================="
        echo ""
        echo "Container will keep running. Run the command above to pair."
        
        # Mantener contenedor vivo para que puedan ejecutar el comando
        tail -f /dev/null
    fi
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
