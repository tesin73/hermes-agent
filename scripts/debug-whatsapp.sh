#!/bin/bash
# Debug script for WhatsApp connectivity issues

echo "═══════════════════════════════════════════════════════════"
echo "  🔍 WHATSAPP DEBUG DIAGNOSTIC"
echo "═══════════════════════════════════════════════════════════"
echo ""

HERMES_HOME="/opt/data"

# 1. Check if bridge process is running
echo "1. Bridge Process Status:"
if pgrep -f "bridge.js" > /dev/null; then
    echo "   ✅ Bridge is running (PID: $(pgrep -f bridge.js))"
else
    echo "   ❌ Bridge is NOT running"
fi
echo ""

# 2. Check if bridge is responding on port 3000
echo "2. Bridge Health Check (port 3000):"
if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo "   ✅ Bridge responding on :3000"
    curl -s http://localhost:3000/health 2>/dev/null | head -1
else
    echo "   ❌ Bridge NOT responding on :3000"
fi
echo ""

# 3. Check gateway health
echo "3. Gateway Health Check (port 8080):"
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "   ✅ Gateway responding on :8080"
else
    echo "   ❌ Gateway NOT responding on :8080"
fi
echo ""

# 4. Check WhatsApp session
echo "4. WhatsApp Session Status:"
CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"
if [ -f "$CREDS_FILE" ]; then
    if grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
        echo "   ✅ Session registered"
        # Show phone number
        grep '"id":' "$CREDS_FILE" | head -1 | sed 's/.*: "\([^"]*\)".*/   Phone: \1/'
    else
        echo "   ❌ Session exists but NOT registered"
    fi
else
    echo "   ❌ No session file found"
fi
echo ""

# 5. Check environment variables
echo "5. Environment Variables:"
echo "   WHATSAPP_ENABLED=${WHATSAPP_ENABLED:-not set}"
echo "   WHATSAPP_MODE=${WHATSAPP_MODE:-not set}"
echo "   WHATSAPP_ALLOWED_USERS=${WHATSAPP_ALLOWED_USERS:-not set}"
echo ""

# 6. Check recent bridge logs
echo "6. Recent Bridge Logs (last 20 lines):"
if [ -f "$HERMES_HOME/whatsapp/bridge.log" ]; then
    tail -20 "$HERMES_HOME/whatsapp/bridge.log"
else
    echo "   No bridge.log found"
fi
echo ""

# 7. Check gateway logs
echo "7. Checking if gateway has WhatsApp adapter:"
ps aux | grep -i gateway | grep -v grep | head -2
echo ""

# 8. Test bridge message endpoint
echo "8. Testing bridge endpoints:"
echo "   Messages endpoint:"
curl -s http://localhost:3000/messages 2>/dev/null | head -c 100 || echo "   ❌ No response"
echo ""

echo "═══════════════════════════════════════════════════════════"
