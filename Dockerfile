FROM node:22-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install only essential dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv ripgrep git curl \
        g++ make && \
    rm -rf /var/lib/apt/lists/*

COPY . /opt/hermes
WORKDIR /opt/hermes

# Install Python dependencies — only the extras needed for gateway + WhatsApp
# Core deps are always included. Skip heavy/unused extras like voice, modal, daytona, etc.
RUN pip install --no-cache-dir -e ".[cron,pty,mcp]" --break-system-packages 2>/dev/null || \
    pip install --no-cache-dir -e ".[cron,pty,mcp]"

# Install Node dependencies:
# - Root package (agent-browser): skip browser binary downloads to avoid OOM on
#   constrained build servers. Browsers can be installed at runtime if needed.
# - WhatsApp Bridge (Baileys): lightweight, install normally.
RUN PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    npm install --prefer-offline --no-audit && \
    cd /opt/hermes/scripts/whatsapp-bridge && \
    npm install --prefer-offline --no-audit && \
    npm cache clean --force

WORKDIR /opt/hermes

# Make scripts executable
RUN chmod +x /opt/hermes/docker/*.sh

ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
