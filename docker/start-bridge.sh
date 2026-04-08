#!/bin/bash
# Start WhatsApp Bridge manually in a running container
# Use this after pairing to avoid container restart

set -e

HERMES_HOME="/opt/data"
INSTALL_DIR="/opt/hermes"

# Check if bridge is already running
if pgrep -f "bridge.js" > /dev/null; then
    echo "✅ WhatsApp Bridge is already running."
    
    # Check health
    if curl -s http://127.0.0.1:3000/health > /dev/null 2>&1; then
        echo "   Bridge is healthy and responding."
    else
        echo "   ⚠️ Bridge process exists but not responding to health checks."
        echo "   You may need to restart the container."
    fi
    exit 0
fi

# Verify session exists and is registered
CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"
if [ ! -f "$CREDS_FILE" ]; then
    echo "❌ No WhatsApp session found."
    echo "   Run /opt/hermes/docker/pair-whatsapp.sh first to pair."
    exit 1
fi

if ! grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
    echo "❌ WhatsApp session is not registered."
    echo "   Run /opt/hermes/docker/pair-whatsapp.sh first to pair."
    exit 1
fi

echo "Starting WhatsApp Bridge..."

mkdir -p "$HERMES_HOME/whatsapp"
cd "$INSTALL_DIR/scripts/whatsapp-bridge"

nohup node bridge.js \
    --port 3000 \
    --session "$HERMES_HOME/whatsapp/session" \
    --mode "${WHATSAPP_MODE:-bot}" \
    > "$HERMES_HOME/whatsapp/bridge.log" 2>&1 &

BRIDGE_PID=$!
echo "Bridge started with PID: $BRIDGE_PID"

# Wait for health check
echo "Waiting for bridge to be ready..."
for i in {1..30}; do
    sleep 1
    if curl -s http://127.0.0.1:3000/health > /dev/null 2>&1; then
        echo "✅ WhatsApp Bridge is ready and responding!"
        echo "   Logs: $HERMES_HOME/whatsapp/bridge.log"
        exit 0
    fi
done

echo "⚠️ Bridge started but not responding to health checks yet."
echo "   Check logs: tail -f $HERMES_HOME/whatsapp/bridge.log"
