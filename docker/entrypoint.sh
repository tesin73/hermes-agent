#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run hermes.
set -e

HERMES_HOME="/opt/data"
INSTALL_DIR="/opt/hermes"

# Create essential directory structure.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills}

# Detectar modo: si WHATSAPP_SESSION_NAME está definida, es modo headless (Docker/Coolify)
if [ -n "$WHATSAPP_SESSION_NAME" ]; then
    MODO_HEADLESS=true
else
    MODO_HEADLESS=false
fi

# .env - Solo crear archivo si estamos en modo interactivo (CLI)
# En modo headless, las variables vienen del entorno de Coolify, no de un archivo
if [ "$MODO_HEADLESS" = false ] && [ ! -f "$HERMES_HOME/.env" ]; then
    cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
fi

# En modo headless, opcionalmente podemos crear un .env mínimo con las variables del entorno
# para compatibilidad con código que busca archivo
if [ "$MODO_HEADLESS" = true ]; then
    # Crear/actualizar .env con las variables críticas del entorno
    ENV_FILE="$HERMES_HOME/.env"
    
    # Función para escribir variable si existe en el entorno
    write_env_var() {
        local var_name=$1
        local var_value=${!var_name}
        if [ -n "$var_value" ]; then
            # Si existe, reemplazar. Si no, agregar.
            grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null && \
                sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$ENV_FILE" || \
                echo "${var_name}=${var_value}" >> "$ENV_FILE"
        fi
    }
    
    # Variables críticas para el WhatsApp Bridge
    write_env_var "OPENROUTER_API_KEY"
    write_env_var "MODEL"
    write_env_var "AGENT_NAME"
    write_env_var "MAX_TURNS"
    write_env_var "TOOL_PROGRESS"
    write_env_var "SHOW_REASONING"
    write_env_var "WHATSAPP_SESSION_NAME"
fi

# config.yaml - crear si no existe
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

# Ejecutar modo según configuración
if [ "$MODO_HEADLESS" = true ]; then
    echo "Starting WhatsApp Bridge in headless mode (session: $WHATSAPP_SESSION_NAME)"
    cd "$INSTALL_DIR/scripts/whatsapp-bridge" && exec npm start
else
    # Interactive CLI mode
    exec hermes "$@"
fi
