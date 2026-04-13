FROM node:20-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update &&     apt-get install -y --no-install-recommends         python3 python3-pip python3-venv ripgrep ffmpeg git         gcc libc6-dev &&     rm -rf /var/lib/apt/lists/*

COPY . /opt/hermes
WORKDIR /opt/hermes

# Install Python and Node dependencies
RUN pip install --no-cache-dir -e ".[all]" --break-system-packages &&     npm install --prefer-offline --no-audit &&     npx playwright install --with-deps chromium --only-shell &&     cd /opt/hermes/scripts/whatsapp-bridge && sed -i "s/7.0.0-rc.9/6.7.16/g" package.json &&     npm install --prefer-offline --no-audit &&     npm cache clean --force

WORKDIR /opt/hermes

# Make scripts executable
RUN chmod +x /opt/hermes/docker/*.sh

ENV HERMES_HOME=/opt/data
VOLUME [ "/opt/data" ]
ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
