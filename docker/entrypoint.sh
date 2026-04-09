#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run hermes.
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
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
# WHATSAPP SETUP
# =============================================================================
# Setup WhatsApp session directory even if not paired yet
mkdir -p "$HERMES_HOME/whatsapp"
rm -rf ~/.hermes/whatsapp 2>/dev/null || true
mkdir -p ~/.hermes
ln -sf "$HERMES_HOME/whatsapp" ~/.hermes/whatsapp

CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"
WHATSAPP_READY=false

# Check if WhatsApp session exists and is registered
if [ -f "$CREDS_FILE" ]; then
    if grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
        WHATSAPP_READY=true
        echo "[entrypoint] ✅ WhatsApp session found and registered"
        # Extract phone number for display
        PHONE=$(grep '"id":' "$CREDS_FILE" 2>/dev/null | head -1 | sed 's/.*: "//' | sed 's/@.*//')
        echo "[entrypoint]    Phone: $PHONE"
    else
        echo "[entrypoint] ⚠️  WhatsApp session exists but NOT registered"
    fi
else
    echo "[entrypoint] ℹ️  No WhatsApp session found"
fi

# =============================================================================
# START WHATSAPP BRIDGE IF SESSION EXISTS
# =============================================================================
if [ "$WHATSAPP_READY" = "true" ] && [ "${WHATSAPP_ENABLED:-false}" = "true" ]; then
    echo "[entrypoint] 🚀 Starting WhatsApp Bridge (port 3000)..."
    
    cd "$INSTALL_DIR/scripts/whatsapp-bridge"
    
    nohup node bridge.js \
        --port 3000 \
        --session "$HERMES_HOME/whatsapp/session" \
        --mode "${WHATSAPP_MODE:-self-chat}" \
        > "$HERMES_HOME/whatsapp/bridge.log" 2>&1 &
    
    BRIDGE_PID=$!
    echo "[entrypoint]    Bridge PID: $BRIDGE_PID"
    
    # Wait for bridge health check
    echo "[entrypoint]    Waiting for bridge to be ready..."
    for i in {1..30}; do
        sleep 1
        if curl -s http://127.0.0.1:3000/health > /dev/null 2>&1; then
            echo "[entrypoint]    ✅ Bridge is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "[entrypoint]    ⚠️  Bridge did not respond in 30s"
        fi
    done
elif [ "$WHATSAPP_READY" = "false" ] && [ "${WHATSAPP_ENABLED:-false}" = "true" ]; then
    echo ""
    echo "=========================================="
    echo "📱 WHATSAPP PAIRING REQUIRED"
    echo "=========================================="
    echo ""
    echo "To pair WhatsApp, run in Coolify Terminal:"
    echo "  /opt/hermes/docker/pair-whatsapp.sh"
    echo ""
    echo "Then scan the QR code with your phone."
    echo "=========================================="
    echo ""
fi

# =============================================================================
# DEBUG OUTPUT
# =============================================================================
if [ "${WHATSAPP_DEBUG:-false}" = "true" ]; then
    echo ""
    echo "[entrypoint] Debug Info:"
    echo "    WHATSAPP_ENABLED=${WHATSAPP_ENABLED:-not set}"
    echo "    WHATSAPP_MODE=${WHATSAPP_MODE:-not set}"
    echo "    WHATSAPP_ALLOWED_USERS=${WHATSAPP_ALLOWED_USERS:-not set}"
    echo "    HERMES_MODEL=${HERMES_MODEL:-not set}"
    echo ""
fi

# =============================================================================
# START GATEWAY
# =============================================================================
echo "[entrypoint] 🚀 Starting Hermes Gateway..."
exec hermes gateway
