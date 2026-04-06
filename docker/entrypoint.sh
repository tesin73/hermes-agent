#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run hermes.
set -e

HERMES_HOME="/opt/data"
INSTALL_DIR="/opt/hermes"

# Create essential directory structure.  Cache and platform directories
# (cache/images, cache/audio, platforms/whatsapp, etc.) are created on
# demand by the application — don't pre-create them here so new installs
# get the consolidated layout from get_hermes_dir().
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills}

# .env - con inyección de variables de entorno para modo headless
if [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

# Inyectar variables de entorno críticas desde el contenedor al archivo .env
# Esto es necesario para que el WhatsApp Bridge vea las credenciales
if [ -n "$OPENROUTER_API_KEY" ]; then
    # Actualizar o agregar OPENROUTER_API_KEY
    grep -q "^OPENROUTER_API_KEY=" "$HERMES_HOME/.env" && \
        sed -i "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=$OPENROUTER_API_KEY|" "$HERMES_HOME/.env" || \
        echo "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" >> "$HERMES_HOME/.env"
fi

if [ -n "$MODEL" ]; then
    grep -q "^MODEL=" "$HERMES_HOME/.env" && \
        sed -i "s|^MODEL=.*|MODEL=$MODEL|" "$HERMES_HOME/.env" || \
        echo "MODEL=$MODEL" >> "$HERMES_HOME/.env"
fi

if [ -n "$AGENT_NAME" ]; then
    grep -q "^AGENT_NAME=" "$HERMES_HOME/.env" && \
        sed -i "s|^AGENT_NAME=.*|AGENT_NAME=$AGENT_NAME|" "$HERMES_HOME/.env" || \
        echo "AGENT_NAME=$AGENT_NAME" >> "$HERMES_HOME/.env"
fi

# config.yaml
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
fi

# SOUL.md
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Sync bundled skills (manifest-based so user edits are preserved)
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

# Detectar modo: si WHATSAPP_SESSION_NAME está definida, forzar modo bridge
# Esto sobrescribe la detección por TTY que falla en algunos entornos (Coolify)
if [ -n "$WHATSAPP_SESSION_NAME" ]; then
    # Headless mode for Docker - run WhatsApp Bridge directly
    echo "Starting WhatsApp Bridge in headless mode (session: $WHATSAPP_SESSION_NAME)"
    cd "$INSTALL_DIR/scripts/whatsapp-bridge" && exec npm start
else
    # Interactive CLI mode
    exec hermes "$@"
fi
