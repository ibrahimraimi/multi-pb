# Multi-PB: Simplified Single-Container PocketBase Manager
# Alpine-based with minimal dependencies
FROM alpine:3.19

# Install dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    unzip \
    supervisor \
    caddy \
    jq \
    bash

# Detect architecture and download appropriate PocketBase binary
ARG PB_VERSION=0.23.4
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        PB_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        PB_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading PocketBase for architecture: $PB_ARCH" && \
    curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${PB_ARCH}.zip" \
    -o /tmp/pocketbase.zip && \
    unzip /tmp/pocketbase.zip -d /tmp && \
    mv /tmp/pocketbase /usr/local/bin/pocketbase && \
    chmod +x /usr/local/bin/pocketbase && \
    rm -rf /tmp/*

# Create directories
RUN mkdir -p /var/multipb/data \
    /var/log/multipb \
    /etc/caddy \
    /etc/supervisor/conf.d

# Copy management scripts
COPY scripts/*.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment defaults
ENV MULTIPB_PORT=25983 \
    MULTIPB_DATA_DIR=/var/multipb/data

# Volume for persistent data
VOLUME ["/var/multipb/data"]

# Expose only the single configured port
EXPOSE ${MULTIPB_PORT}

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${MULTIPB_PORT}/_health || exit 1

ENTRYPOINT ["/entrypoint.sh"]
