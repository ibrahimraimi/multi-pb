# Stage 1: Build the frontend
FROM node:22-alpine AS frontend-builder

WORKDIR /app

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy frontend source
COPY multi-frontend/package.json multi-frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY multi-frontend/ ./
RUN pnpm build

# Stage 2: Runtime
FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    bash \
    supervisor \
    caddy \
    unzip \
    nodejs

# Download PocketBase
ARG PB_VERSION=0.23.4
RUN curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip" \
    -o /tmp/pocketbase.zip \
    && unzip /tmp/pocketbase.zip -d /tmp \
    && mv /tmp/pocketbase /usr/local/bin/pocketbase \
    && chmod +x /usr/local/bin/pocketbase \
    && rm -rf /tmp/*

# Create directories
RUN mkdir -p /mnt/data /etc/supervisor.d /var/log/supervisor /app/dashboard

# Copy built frontend
COPY --from=frontend-builder /app/build /app/dashboard

# Copy config templates and entrypoint
COPY Caddyfile.template /etc/Caddyfile.template
COPY supervisord.conf.template /etc/supervisord.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]
