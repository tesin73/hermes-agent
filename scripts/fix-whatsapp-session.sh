#!/bin/bash
# Fix WhatsApp Session Corruption for Hermes Agent (Coolify/Docker deployments)
# Usage: sudo ./fix-whatsapp-session.sh <container_name>
#
# This script fixes "PreKeyError" and session corruption issues by:
# 1. Stopping the container
# 2. Backing up the corrupted session
# 3. Clearing all session files
# 4. Restarting the container
# 5. Showing the command to re-pair with QR code
#
# IMPORTANT: Each container has its OWN isolated volume, so this only affects
# the specified container, not others.

set -e

CONTAINER_NAME="${1:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo -e "${RED}Error: This script requires root or sudo privileges${NC}"
    echo "Usage: sudo $0 <container_name>"
    exit 1
fi

# Validate container name
if [ -z "$CONTAINER_NAME" ]; then
    echo -e "${RED}Error: Container name is required${NC}"
    echo ""
    echo "Usage: sudo $0 <container_name>"
    echo ""
    echo "To find your container name, run:"
    echo "  docker ps | grep -v 'traefik\|postgres\|redis\|coolify'"
    echo ""
    echo "Example:"
    echo "  sudo $0 ntkv37t2m7lkoea6ov1svky4-044255085820"
    exit 1
fi

echo -e "${BLUE}🔍 Analyzing container: $CONTAINER_NAME${NC}"

# Check if container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}❌ Container not found: $CONTAINER_NAME${NC}"
    echo ""
    echo "Available containers:"
    docker ps -a --format '  - {{.Names}} ({{.Status}})' | grep -v 'traefik\|postgres\|redis\|coolify' || true
    exit 1
fi

# Get volume path for this container
echo -e "${BLUE}📁 Finding volume path...${NC}"
VOLUME_PATH=$(docker inspect "$CONTAINER_NAME" --format='{{range .Mounts}}{{if eq .Destination "/opt/data"}}{{.Source}}{{end}}{{end}}')

if [ -z "$VOLUME_PATH" ]; then
    echo -e "${RED}❌ No volume mounted at /opt/data found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Volume found: $VOLUME_PATH${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: This affects ONLY this container.${NC}"
echo -e "${YELLOW}   Other containers use different volumes and are NOT affected.${NC}"
echo ""

# Check for corruption symptoms
echo -e "${BLUE}🔍 Checking for corruption symptoms...${NC}"
ERROR_COUNT=$(docker logs --tail 500 "$CONTAINER_NAME" 2>&1 | grep -c "PreKeyError" || echo "0")

if [ "$ERROR_COUNT" -gt 5 ]; then
    echo -e "${YELLOW}⚠️  Found $ERROR_COUNT PreKeyError entries - Session likely corrupted${NC}"
else
    echo -e "${GREEN}✓ Only $ERROR_COUNT PreKeyError entries found${NC}"
fi

# Check current registration status
echo -e "${BLUE}🔍 Checking registration status...${NC}"
REG_STATUS=$(docker exec "$CONTAINER_NAME" cat /opt/data/whatsapp/session/creds.json 2>/dev/null | grep '"registered"' || echo "No creds.json found")
echo "  Current status: $REG_STATUS"
echo ""

# Create backup
BACKUP_NAME="whatsapp-session-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
BACKUP_PATH="/tmp/${CONTAINER_NAME}-${BACKUP_NAME}"

echo -e "${BLUE}💾 Creating backup...${NC}"
if [ -d "$VOLUME_PATH/whatsapp/session" ]; then
    sudo tar czf "$BACKUP_PATH" -C "$VOLUME_PATH/whatsapp" session/ 2>/dev/null || true
    echo -e "${GREEN}✓ Backup created: $BACKUP_PATH${NC}"
    FILE_COUNT=$(sudo find "$VOLUME_PATH/whatsapp/session/" -type f | wc -l)
    echo "  Files in session: $FILE_COUNT"
else
    echo -e "${YELLOW}⚠️  No session directory found (might already be clean)${NC}"
fi
echo ""

# Stop container
echo -e "${BLUE}🛑 Stopping container...${NC}"
docker stop "$CONTAINER_NAME" > /dev/null 2>&1
echo -e "${GREEN}✓ Container stopped${NC}"

# Clean session
echo -e "${BLUE}🧹 Clearing corrupted session files...${NC}"
if [ -d "$VOLUME_PATH/whatsapp/session" ]; then
    sudo find "$VOLUME_PATH/whatsapp/session/" -type f -delete
    echo -e "${GREEN}✓ Session files cleared${NC}"
else
    echo -e "${YELLOW}⚠️  Session directory does not exist${NC}"
fi

# Verify cleanup
REMAINING=$(sudo find "$VOLUME_PATH/whatsapp/session/" -type f 2>/dev/null | wc -l)
if [ "$REMAINING" -eq 0 ]; then
    echo -e "${GREEN}✓ Directory is now empty (only . and .. remain)${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: $REMAINING files still present${NC}"
fi
echo ""

# Start container
echo -e "${BLUE}🚀 Starting container...${NC}"
docker start "$CONTAINER_NAME" > /dev/null 2>&1

# Wait for container to be ready
echo -e "${BLUE}⏳ Waiting for container to be ready...${NC}"
sleep 5

# Verify container is running
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo -e "${GREEN}✓ Container is running${NC}"
else
    echo -e "${RED}❌ Container failed to start${NC}"
    exit 1
fi
echo ""

# Success message
WIDTH=70
printf '%*s\n' "$WIDTH" '' | tr ' ' '═'
echo -e "${GREEN}✅ Container restarted successfully!${NC}"
printf '%*s\n' "$WIDTH" '' | tr ' ' '═'
echo ""
echo -e "${YELLOW}📱 NEXT STEP: Re-pair with WhatsApp${NC}"
echo ""
echo "Run this command to get the QR code:"
echo ""
echo -e "${BLUE}docker exec -it $CONTAINER_NAME node /opt/hermes/scripts/whatsapp-bridge/bridge.sh \\"${NC}"
echo -e "${BLUE}  --pair-only \\"${NC}"
echo -e "${BLUE}  --session /opt/data/whatsapp/session \\"${NC}"
echo -e "${BLUE}  --mode bot${NC}"
echo ""
echo "Then scan the QR code with your phone:"
echo "  WhatsApp → ⋮ → Linked Devices → Link a Device"
echo ""
printf '%*s\n' "$WIDTH" '' | tr ' ' '═'
echo ""
echo -e "${YELLOW}💾 Backup saved to:${NC}"
echo "  $BACKUP_PATH"
echo ""
echo -e "${YELLOW}📝 After confirming everything works, you can delete the backup:${NC}"
echo "  sudo rm $BACKUP_PATH"
echo ""
