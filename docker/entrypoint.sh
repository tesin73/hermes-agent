#!/bin/bash
# Docker entrypoint: bootstrap config files into the mounted volume, then run hermes.
set -e

HERMES_HOME="/opt/data"
INSTALL_DIR="/opt/hermes"

# Create essential directory structure.
mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills}

# =============================================================================
# GENERAR .env DESDE VARIABLES DE ENTORNO (Para deployments Docker/Coolify)
# =============================================================================
# Este bloque crea/actualiza el archivo .env con los valores de las variables
# de entorno del contenedor. Así cada instancia puede configurarse via Coolify
# sin necesidad de editar archivos manualmente.
#
# Variables soportadas: OPENROUTER_API_KEY, MODEL, AGENT_NAME, MAX_TURNS,
# TOOL_PROGRESS, SHOW_REASONING, y cualquier otra definida en el contenedor.

ENV_FILE="$HERMES_HOME/.env"

# Función para escribir o actualizar una variable en el .env
write_env_var() {
    local var_name=$1
    local var_value=${!var_name}
    
    if [ -n "$var_value" ]; then
        # Si la variable existe en el archivo, reemplazarla. Si no, agregarla.
        if grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null; then
            sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$ENV_FILE"
        else
            echo "${var_name}=${var_value}" >> "$ENV_FILE"
        fi
        echo "[Config] ${var_name} configurado desde entorno"
    fi
}

# Si existe .env.example, copiarlo primero (para tener estructura base)
if [ ! -f "$ENV_FILE" ] && [ -f "$INSTALL_DIR/.env.example" ]; then
    cp "$INSTALL_DIR/.env.example" "$ENV_FILE"
fi

# Escribir las variables críticas desde el entorno
write_env_var "OPENROUTER_API_KEY"
write_env_var "MODEL"
write_env_var "AGENT_NAME"
write_env_var "MAX_TURNS"
write_env_var "TOOL_PROGRESS"
write_env_var "SHOW_REASONING"
write_env_var "WHATSAPP_SESSION_NAME"
write_env_var "HERMES_HOME"

# También pasar cualquier variable que empiece con HERMES_, OPENROUTER_, etc.
for var in $(env | grep -E '^(HERMES_|OPENROUTER_|MODEL|AGENT|TOOL_|MAX_TURNS|SHOW_|WHATSAPP_)' | cut -d= -f1); do
    write_env_var "$var"
done

# =============================================================================

# config.yaml
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

# Detect mode: if WHATSAPP_SESSION_NAME is set, run WhatsApp Bridge (headless)
if [ -n "$WHATSAPP_SESSION_NAME" ]; then
    echo "[Hermes] Iniciando WhatsApp Bridge en modo headless (sesion: $WHATSAPP_SESSION_NAME)"
    echo "[Hermes] Modelo configurado: ${MODEL:-default}"
    cd "$INSTALL_DIR/scripts/whatsapp-bridge" && exec npm start
else
    # Interactive CLI mode
    exec hermes "$@"
fi
