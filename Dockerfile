# Multi-PB: Simplified Single-Container PocketBase Manager
# Alpine-based with minimal dependencies
FROM alpine:3.19

# Install basic dependencies first
RUN apk add --no-cache \
    ca-certificates \
    curl \
    unzip \
    zip \
    python3 \
    supervisor \
    jq \
    bash \
    util-linux \
    libstdc++ \
    libgcc

# Install Bun
COPY --from=oven/bun:alpine /usr/local/bin/bun /usr/local/bin/bun

# Detect architecture and download appropriate binaries
ARG PB_VERSION=0.23.4
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
    PB_ARCH="amd64"; \
    CADDY_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
    PB_ARCH="arm64"; \
    CADDY_ARCH="arm64"; \
    else \
    echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    echo "Downloading binaries for architecture: $PB_ARCH" && \
    # Download Caddy
    curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=${CADDY_ARCH}" -o /usr/local/bin/caddy && \
    chmod +x /usr/local/bin/caddy && \
    # Download PocketBase
    curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_${PB_ARCH}.zip" \
    -o /tmp/pocketbase.zip && \
    unzip /tmp/pocketbase.zip -d /tmp && \
    mv /tmp/pocketbase /usr/local/bin/pocketbase && \
    chmod +x /usr/local/bin/pocketbase && \
    rm -rf /tmp/*

# Create directories
RUN mkdir -p /var/multipb/data \
    /var/multipb/backups \
    /var/log/multipb \
    /etc/caddy \
    /etc/supervisor/conf.d

# Copy management scripts
COPY core/cli/*.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Create versions directory
RUN mkdir -p /var/multipb/versions

# Copy entrypoint
COPY core/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Build dashboard (skip if SKIP_DASHBOARD build arg is set)
ARG SKIP_DASHBOARD=false
RUN mkdir -p /var/www/dashboard
COPY apps/dashboard /tmp/dashboard
WORKDIR /tmp/dashboard
RUN if [ "$SKIP_DASHBOARD" != "true" ]; then \
    bun install && \
    bun x svelte-kit sync && \
    bun run build && \
    cp -r build/* /var/www/dashboard/; \
    else \
    echo "Skipping dashboard build (CLI-only mode)" && \
    rm -rf /tmp/dashboard; \
    fi

# Copy API server
COPY core/api/server.js /usr/local/bin/api-server.js
RUN chmod +x /usr/local/bin/api-server.js

WORKDIR /

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
