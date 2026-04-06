#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run hermes.
set -e

HERMES_HOME="/opt/data"
INSTALL_DIR="/opt/hermes"

# Create essential directory structure.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills}

# =============================================================================
# GENERAR .env DESDE VARIABLES DE ENTORNO
# =============================================================================
ENV_FILE="$HERMES_HOME/.env"

# Función para escribir o actualizar una variable en el .env
write_env_var() {
    local var_name=$1
    local var_value=${!var_name}
    
    if [ -n "$var_value" ]; then
        if grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null; then
            sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$ENV_FILE"
        else
            echo "${var_name}=${var_value}" >> "$ENV_FILE"
        fi
    fi
}

# Si existe .env.example, copiarlo primero
if [ ! -f "$ENV_FILE" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
    cp "$INSTALL_DIR/.env.example" "$ENV_FILE"
fi

# Escribir variables desde entorno
write_env_var "OPENROUTER_API_KEY"
write_env_var "HERMES_MODEL"
write_env_var "AGENT_NAME"
write_env_var "MAX_TURNS"
write_env_var "TOOL_PROGRESS"
write_env_var "SHOW_REASONING"
write_env_var "WHATSAPP_SESSION_NAME"
write_env_var "HERMES_HOME"

# =============================================================================
# CONFIGURAR MODELO EN config.yaml (CRÍTICO para que use el modelo correcto)
# =============================================================================
CONFIG_FILE="$HERMES_HOME/config.yaml"

if [ ! -f "$CONFIG_FILE" ] && [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
    cp "$INSTALL_DIR/cli-config.yaml.example" "$CONFIG_FILE"
fi

# Si HERMES_MODEL está definida, actualizar el config.yaml
if [ -n "$HERMES_MODEL" ]; then
    echo "[Config] Configurando modelo: $HERMES_MODEL"
    
    # Actualizar la línea 'default:' en la sección 'model:'
    # De: default: "anthropic/claude-opus-4.6"
    # A:   default: "openrouter:moonshotai/kimi-k2.5"
    sed -i "s|default: \"anthropic/claude-opus-4.6\"|default: \"$HERMES_MODEL\"|" "$CONFIG_FILE"
    
    # También actualizar si ya fue modificado antes (cualquier valor)
    sed -i "s|default: \"[^\"]*\"|default: \"$HERMES_MODEL\"|" "$CONFIG_FILE"
    
    # Actualizar provider a openrouter si el modelo empieza con openrouter:
    if [[ "$HERMES_MODEL" == openrouter:* ]]; then
        sed -i 's/provider: "auto"/provider: "openrouter"/' "$CONFIG_FILE"
    fi
fi

# =============================================================================

# SOUL.md
if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
    cp "$INSTALL_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md"
fi

# Sync bundled skills
if [ -d "$INSTALL_DIR/skills" ]; then
    python3 "$INSTALL_DIR/tools/skills_sync.py"
fi

# Detect mode: if WHATSAPP_SESSION_NAME is set, run WhatsApp Bridge (headless)
if [ -n "$WHATSAPP_SESSION_NAME" ]; then
    echo "[Hermes] Iniciando WhatsApp Bridge en modo headless (sesion: $WHATSAPP_SESSION_NAME)"
    echo "[Hermes] Modelo configurado: ${HERMES_MODEL:-default}"
    cd "$INSTALL_DIR/scripts/whatsapp-bridge" && exec npm start
else
    # Interactive CLI mode
    exec hermes "$@"
fi
