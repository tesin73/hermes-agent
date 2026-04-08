#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run hermes.
# VERSION AUTO-PAIRING: Automatically handles WhatsApp pairing without manual commands
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
# WHATSAPP AUTO-PAIRING MODE
# =============================================================================
# Detect mode: if WHATSAPP_SESSION_NAME is set, run WhatsApp Bridge (headless)
if [ -n "$WHATSAPP_SESSION_NAME" ]; then
    echo "[Hermes] WhatsApp mode enabled (session: $WHATSAPP_SESSION_NAME)"
    
    # Setup session persistence
    mkdir -p "$HERMES_HOME/whatsapp"
    rm -rf ~/.hermes/whatsapp 2>/dev/null || true
    mkdir -p ~/.hermes
    ln -sf "$HERMES_HOME/whatsapp" ~/.hermes/whatsapp
    
    CREDS_FILE="$HERMES_HOME/whatsapp/session/creds.json"
    
    # Function to check if session is properly registered
    is_session_ready() {
        if [ -f "$CREDS_FILE" ]; then
            if grep -q '"registered": true' "$CREDS_FILE" 2>/dev/null; then
                return 0
            fi
        fi
        return 1
    }
    
    # Check session status
    if is_session_ready; then
        echo "[Hermes] WhatsApp session found and registered."
        SESSION_READY=true
    else
        echo "[Hermes] WhatsApp session NOT registered."
        SESSION_READY=false
    fi
    
    # If session not ready, run pairing mode first (foreground, shows QR in logs)
    if [ "$SESSION_READY" = "false" ]; then
        echo ""
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║  📱 WHATSAPP PAIRING REQUIRED                                  ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "No valid WhatsApp session found. Starting automatic pairing..."
        echo ""
        echo "INSTRUCTIONS:"
        echo "  1. Wait for the QR code to appear below"
        echo "  2. Open WhatsApp on your phone"
        echo "  3. Go to Settings → Linked Devices → Link a Device"
        echo "  4. Scan the QR code shown in the logs below"
        echo "  5. Wait for 'Pairing complete' message"
        echo ""
        echo "Starting bridge in PAIRING MODE..."
        echo "══════════════════════════════════════════════════════════════════"
        
        cd "$INSTALL_DIR/scripts/whatsapp-bridge"
        
        # Run pairing in foreground - QR will be visible in docker logs
        # This will exit with code 0 when pairing is complete
        node bridge.js \
            --session "$HERMES_HOME/whatsapp/session" \
            --mode "${WHATSAPP_MODE:-bot}" \
            --pair-only
        
        PAIRING_EXIT_CODE=$?
        
        echo "══════════════════════════════════════════════════════════════════"
        
        if [ $PAIRING_EXIT_CODE -eq 0 ]; then
            echo "[Hermes] ✅ Pairing completed successfully!"
            echo "[Hermes] Waiting 3 seconds for credentials to flush..."
            sleep 3
            
            # Verify session is now ready
            if is_session_ready; then
                echo "[Hermes] ✅ Session verified. Starting normal operation..."
                SESSION_READY=true
            else
                echo "[Hermes] ❌ Pairing reported success but session not found."
                echo "[Hermes] Check the logs above for errors."
                exit 1
            fi
        else
            echo "[Hermes] ❌ Pairing failed with exit code: $PAIRING_EXIT_CODE"
            echo "[Hermes] Check the logs above for errors."
            exit 1
        fi
    fi
    
    # Session is ready - start bridge in background and gateway in foreground
    if [ "$SESSION_READY" = "true" ]; then
        echo "[Hermes] Starting WhatsApp Bridge in background..."
        cd "$INSTALL_DIR/scripts/whatsapp-bridge"
        
        # Start bridge in background, save logs
        nohup node bridge.js \
            --port 3000 \
            --session "$HERMES_HOME/whatsapp/session" \
            --mode "${WHATSAPP_MODE:-bot}" \
            > "$HERMES_HOME/whatsapp/bridge.log" 2>&1 &
        
        BRIDGE_PID=$!
        echo "[Hermes] Bridge started with PID: $BRIDGE_PID"
        
        # Wait for bridge to be ready (health check)
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
        
        # Start gateway
        echo "[Hermes] Starting Hermes Gateway..."
        exec hermes gateway
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
