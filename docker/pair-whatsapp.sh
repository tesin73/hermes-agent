#!/bin/bash
# WhatsApp Pairing Script for Docker
# Run this inside the container to pair WhatsApp

set -e

HERMES_HOME="/opt/data"
INSTALL_DIR="/opt/hermes"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  📱 WHATSAPP PAIRING                                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if already paired
CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"
if [ -f "$CREDS_FILE" ]; then
    if grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
        echo "✅ WhatsApp is already paired and registered."
        echo ""
        echo "To re-pair (will disconnect existing session):"
        echo "  1. Stop the container"
        echo "  2. Delete session: rm -rf $HERMES_HOME/whatsapp/session"
        echo "  3. Restart container and run this script again"
        exit 0
    fi
fi

# Setup session directory
mkdir -p "$HERMES_HOME/whatsapp/session"

MODE="${WHATSAPP_MODE:-bot}"
echo "Mode: $MODE"
echo "Session: $HERMES_HOME/whatsapp/session"
echo ""
echo "INSTRUCTIONS:"
echo "  1. Wait for the QR code to appear below"
echo "  2. Open WhatsApp on your phone"
echo "  3. Go to Settings → Linked Devices → Link a Device"
echo "  4. Scan the QR code"
echo "  5. Wait for 'Pairing complete' message"
echo ""
echo "══════════════════════════════════════════════════════════════════"
echo ""

cd "$INSTALL_DIR/scripts/whatsapp-bridge"

# Run pairing
node bridge.js \
    --session "$HERMES_HOME/whatsapp/session" \
    --mode "$MODE" \
    --pair-only

PAIRING_EXIT_CODE=$?

echo ""
echo "══════════════════════════════════════════════════════════════════"

if [ $PAIRING_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "✅ Pairing completed successfully!"
    echo ""
    echo "The WhatsApp Bridge will be available at:"
    echo "  http://localhost:3000"
    echo ""
    echo "To activate WhatsApp in the running gateway:"
    echo "  docker exec <container> /opt/hermes/docker/start-bridge.sh"
    echo ""
    echo "Or simply restart the container:"
    echo "  docker-compose restart"
    echo ""
else
    echo ""
    echo "❌ Pairing failed with exit code: $PAIRING_EXIT_CODE"
    echo "Please check the error messages above and try again."
    exit 1
fi
