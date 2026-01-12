FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    bash \
    supervisor \
    caddy \
    unzip

# Download latest PocketBase
ARG PB_VERSION=0.23.4
RUN curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip" \
    -o /tmp/pocketbase.zip \
    && unzip /tmp/pocketbase.zip -d /tmp \
    && mv /tmp/pocketbase /usr/local/bin/pocketbase \
    && chmod +x /usr/local/bin/pocketbase \
    && rm -rf /tmp/*

# Create data directory
RUN mkdir -p /mnt/data /etc/supervisor.d /var/log/supervisor

# Copy config templates and entrypoint
COPY Caddyfile.template /etc/Caddyfile.template
COPY supervisord.conf.template /etc/supervisord.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
