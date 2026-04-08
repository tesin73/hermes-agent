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

# =============================================================================
# WHATSAPP BRIDGE SETUP
# =============================================================================
# Setup WhatsApp session directory even if not paired yet
mkdir -p "$HERMES_HOME/whatsapp"
rm -rf ~/.hermes/whatsapp 2>/dev/null || true
mkdir -p ~/.hermes
ln -sf "$HERMES_HOME/whatsapp" ~/.hermes/whatsapp

# Check if WhatsApp session is ready
CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"
WHATSAPP_READY=false

if [ -f "$CREDS_FILE" ]; then
    if grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
        WHATSAPP_READY=true
        echo "[Hermes] WhatsApp session found and registered."
    else
        echo "[Hermes] WhatsApp session exists but is NOT registered."
    fi
else
    echo "[Hermes] No WhatsApp session found. WhatsApp will be available after pairing."
fi

# Start WhatsApp Bridge if session is ready
if [ "$WHATSAPP_READY" = "true" ]; then
    echo "[Hermes] Starting WhatsApp Bridge on port 3000..."
    cd "$INSTALL_DIR/scripts/whatsapp-bridge"
    
    nohup node bridge.js \
        --port 3000 \
        --session "$HERMES_HOME/whatsapp/session" \
        --mode "${WHATSAPP_MODE:-bot}" \
        > "$HERMES_HOME/whatsapp/bridge.log" 2>&1 &
    
    BRIDGE_PID=$!
    echo "[Hermes] Bridge started with PID: $BRIDGE_PID"
    
    # Wait for bridge health check
    echo "[Hermes] Waiting for bridge to be ready..."
    for i in {1..30}; do
        sleep 1
        if curl -s http://127.0.0.1:3000/health > /dev/null 2>&1; then
            echo "[Hermes] WhatsApp Bridge is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "[Hermes] WARNING: Bridge did not respond in 30s, but continuing..."
        fi
    done
else
    echo ""
    echo "=========================================="
    echo "📱 WHATSAPP PAIRING AVAILABLE"
    echo "=========================================="
    echo ""
    echo "To pair WhatsApp, run:"
    echo "  docker exec -it <container> /opt/hermes/docker/pair-whatsapp.sh"
    echo ""
    echo "Then scan the QR code with your phone."
    echo "=========================================="
    echo ""
fi

# =============================================================================
# START HERMES GATEWAY (Always)
# =============================================================================
echo "[Hermes] Starting Hermes Gateway..."
exec hermes gateway
