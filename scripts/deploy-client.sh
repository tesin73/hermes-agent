#!/bin/bash
# Deploy Hermes Agent for a new client
# Usage: ./deploy-client.sh <client-name> <admin-phone-number>
#
# Example: ./deploy-client.sh acme-corp +56912345678

set -e

CLIENT_NAME=$1
ADMIN_PHONE=$2

if [ -z "$CLIENT_NAME" ] || [ -z "$ADMIN_PHONE" ]; then
    echo "Usage: ./deploy-client.sh <client-name> <admin-phone-number>"
    echo "Example: ./deploy-client.sh acme-corp +56912345678"
    exit 1
fi

# Sanitize client name for docker/container names
CLIENT_ID=$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')
SESSION_NAME="${CLIENT_ID}-session"
CONTAINER_NAME="hermes-${CLIENT_ID}"
VOLUME_NAME="hermes_data_${CLIENT_ID}"
ENV_FILE=".env.${CLIENT_ID}"

echo "═══════════════════════════════════════════════════════════"
echo "  Deploying Hermes Agent for: $CLIENT_NAME"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Client ID:      $CLIENT_ID"
echo "  Session Name:   $SESSION_NAME"
echo "  Container:      $CONTAINER_NAME"
echo "  Volume:         $VOLUME_NAME"
echo "  Admin Phone:    $ADMIN_PHONE"
echo "  Env File:       $ENV_FILE"
echo ""

# Check if OpenRouter key is set
if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "❌ ERROR: OPENROUTER_API_KEY environment variable not set"
    echo "Set it first: export OPENROUTER_API_KEY=sk-or-v1-..."
    exit 1
fi

# Create .env file for this client
cat > "$ENV_FILE" << EOF
# Hermes Agent - $CLIENT_NAME Deployment
# Generated: $(date)

OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
AGENT_NAME=${CLIENT_NAME}
CONTAINER_NAME=${CONTAINER_NAME}
VOLUME_NAME=${VOLUME_NAME}
WHATSAPP_SESSION_NAME=${SESSION_NAME}
WHATSAPP_MODE=bot
WHATSAPP_ALLOWED_USERS=${ADMIN_PHONE}
MODEL=openrouter:moonshotai/kimi-k2.5
MAX_TURNS=60
TOOL_PROGRESS=off
SHOW_REASONING=false
WHATSAPP_DEBUG=false
GATEWAY_ALLOW_ALL_USERS=false
EOF

echo "✅ Created $ENV_FILE"
echo ""

# Build if needed
echo "🔨 Building Docker image (if needed)..."
docker-compose build 2>/dev/null || docker build -t hermes-agent .

# Deploy
echo "🚀 Starting container..."
docker-compose --env-file "$ENV_FILE" up -d

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Deployment Complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "Container: $CONTAINER_NAME"
echo ""
echo "Next steps:"
echo "  1. View logs to see QR code:"
echo "     docker logs -f $CONTAINER_NAME"
echo ""
echo "  2. Scan the QR code with WhatsApp:"
echo "     Settings → Linked Devices → Link a Device"
echo ""
echo "  3. Once paired, the agent will start automatically"
echo ""
echo "  4. To stop:"
echo "     docker-compose --env-file $ENV_FILE down"
echo ""
echo "  5. To view logs later:"
echo "     docker logs -f $CONTAINER_NAME"
echo ""
