# Stage 1: Build the Go management server
FROM golang:1.24-alpine AS go-builder

WORKDIR /build

# Install git for go mod
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY cmd/ cmd/
COPY internal/ internal/

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o multipb ./cmd/multipb

# Stage 2: Build the frontend
FROM node:22-alpine AS frontend-builder

WORKDIR /app

# Install pnpm
RUN corepack enable && corepack prepare pnpm@latest --activate

# Copy package files first for better caching
COPY multi-frontend/package.json multi-frontend/pnpm-lock.yaml multi-frontend/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

# Copy source files explicitly to avoid conflicts with node_modules symlinks
COPY multi-frontend/src ./src
COPY multi-frontend/static ./static
COPY multi-frontend/svelte.config.js multi-frontend/vite.config.ts multi-frontend/tsconfig.json ./
COPY multi-frontend/.prettierrc multi-frontend/.npmrc multi-frontend/eslint.config.js ./
RUN pnpm build

# Stage 3: Runtime
FROM alpine:latest

# Install dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    bash \
    caddy

# Download PocketBase
ARG PB_VERSION=0.23.4
RUN curl -fsSL "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip" \
    -o /tmp/pocketbase.zip \
    && unzip /tmp/pocketbase.zip -d /tmp \
    && mv /tmp/pocketbase /usr/local/bin/pocketbase \
    && chmod +x /usr/local/bin/pocketbase \
    && rm -rf /tmp/*

# Create directories
RUN mkdir -p /mnt/data /var/log/multipb /app/dashboard

# Copy Go binary
COPY --from=go-builder /build/multipb /usr/local/bin/multipb

# Copy built frontend to be served by the Go server
COPY --from=frontend-builder /app/build /app/dashboard

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Environment defaults
ENV DATA_DIR=/mnt/data \
    HTTP_PORT=8080 \
    HTTPS_PORT=8443 \
    DOMAIN_NAME=localhost.direct \
    ENABLE_HTTPS=false \
    ACME_EMAIL=admin@example.com

EXPOSE 8080 8443

ENTRYPOINT ["/entrypoint.sh"]
