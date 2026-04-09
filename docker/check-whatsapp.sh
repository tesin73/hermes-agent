#!/bin/bash
# Check current WhatsApp session status

HERMES_HOME="/opt/data"
CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  📱 WHATSAPP SESSION STATUS                                    ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if session exists
if [ ! -f "$CREDS_FILE" ]; then
    echo "❌ No session found"
    echo ""
    echo "To pair a new number, run:"
    echo "  /opt/hermes/docker/pair-whatsapp.sh"
    exit 1
fi

# Check if registered
if grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
    echo "✅ Session is REGISTERED"
    
    # Extract phone number
    PHONE_FULL=$(grep '"id":' "$CREDS_FILE" 2>/dev/null | head -1 | sed 's/.*: "//' | sed 's/@.*//')
    if [ -n "$PHONE_FULL" ]; then
        echo ""
        echo "Phone Number: $PHONE_FULL"
        
        # Extract just the number
        PHONE_NUM=$(echo "$PHONE_FULL" | grep -o '[0-9]*' | head -1)
        if [ -n "$PHONE_NUM" ]; then
            echo "Number only: $PHONE_NUM"
        fi
    fi
    
    # Check if bridge is running
    echo ""
    if pgrep -f "bridge.js" > /dev/null; then
        echo "Bridge Status: 🟢 Running"
        
        # Check health
        if curl -s http://localhost:3000/health > /dev/null 2>&1; then
            echo "Health Check: ✅ Responding"
        else
            echo "Health Check: ❌ Not responding (may need restart)"
        fi
    else
        echo "Bridge Status: 🔴 Not running"
        echo "Start with: /opt/hermes/docker/start-bridge.sh"
    fi
    
else
    echo "⚠️  Session exists but NOT registered"
    echo "Pairing is incomplete. Re-run:"
    echo "  /opt/hermes/docker/pair-whatsapp.sh"
fi

echo ""
echo "Session files:"
ls -la "$HERMES_HOME/whatsapp/session/" 2>/dev/null | grep -E "^-\|total" --color=never | head -10

echo ""
echo "To RESET and use a NEW number:"
echo "  /opt/hermes/docker/reset-whatsapp.sh"
