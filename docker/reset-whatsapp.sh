#!/bin/bash
# Reset WhatsApp session completely - use this to pair a new number
# WARNING: This will delete the current WhatsApp session!

set -e

HERMES_HOME="/opt/data"
SESSION_DIR="$HERMES_HOME/whatsapp/session"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  🗑️  RESET WHATSAPP SESSION                                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "This will DELETE the current WhatsApp session."
echo "You will need to re-pair with a new number."
echo ""

# Check if session exists
if [ ! -d "$SESSION_DIR" ] || [ -z "$(ls -A "$SESSION_DIR" 2>/dev/null)" ]; then
    echo "ℹ️  No existing session found. Ready to pair new number."
    exit 0
fi

echo "Current session contents:"
ls -la "$SESSION_DIR" | head -10

echo ""
read -p "Are you sure you want to delete this session? [y/N]: " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Stopping bridge if running..."
    pkill -f "bridge.js" 2>/dev/null || true
    sleep 2
    
    echo "Deleting session files..."
    rm -rf "$SESSION_DIR"/*
    rm -rf "$SESSION_DIR"/.* 2>/dev/null || true
    
    echo "✅ Session deleted successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Run: /opt/hermes/docker/pair-whatsapp.sh"
    echo "  2. Scan QR with your NEW phone number"
    echo "  3. Start bridge: /opt/hermes/docker/start-bridge.sh"
    echo ""
else
    echo "Cancelled. Session preserved."
    exit 1
fi
