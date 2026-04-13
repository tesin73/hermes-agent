     1|FROM node:20-slim
     2|
     3|# Avoid interactive prompts
     4|ENV DEBIAN_FRONTEND=noninteractive
     5|
     6|# Install only essential system dependencies (sin nodejs/npm que ya vienen en la imagen base)
     7|RUN apt-get update && \
     8|    apt-get install -y --no-install-recommends \
     9|        python3 python3-pip python3-venv ripgrep ffmpeg git \
    10|        gcc libc6-dev && \
    11|    rm -rf /var/lib/apt/lists/*
    12|
    13|COPY . /opt/hermes
    14|WORKDIR /opt/hermes
    15|
    16|# Compilar WhatsMeow para WhatsApp personal
    17|RUN cd /opt/hermes/scripts/whatsapp-meow && \
    18|    go mod tidy && \
    19|    go build -o /opt/hermes/whatsapp-meow main.go && \
    20|    chmod +x /opt/hermes/whatsapp-meow && \
    21|    echo "WhatsMeow compilado: $(/opt/hermes/whatsapp-meow --help 2>&1 | head -1 || echo OK)"
    22|
    23|
    24|# Install Python dependencies and setup
    25|RUN pip install --no-cache-dir -e ".[all]" --break-system-packages && \
    26|    npm install --prefer-offline --no-audit && \
    27|    npx playwright install --with-deps chromium --only-shell && \
    28|    cd /opt/hermes/scripts/whatsapp-bridge && sed -i "s/7.0.0-rc.9/6.7.16/g" package.json && \
    29|    npm install --prefer-offline --no-audit && \
    30|    npm cache clean --force
    31|
    32|WORKDIR /opt/hermes
    33|
    34|# Ensure all docker scripts are executable
    35|RUN chmod +x /opt/hermes/docker/*.sh
    36|
    37|ENV HERMES_HOME=/opt/data
    38|VOLUME [ "/opt/data" ]
    39|ENTRYPOINT [ "/opt/hermes/docker/entrypoint.sh" ]
    40|