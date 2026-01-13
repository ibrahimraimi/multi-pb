#!/bin/bash
set -e

echo "╔══════════════════════════════════════════╗"
echo "║      Multi-PB Management Platform        ║"
echo "╚══════════════════════════════════════════╝"

DATA_DIR="${DATA_DIR:-/mnt/data}"
HTTP_PORT="${HTTP_PORT:-8080}"
DOMAIN_NAME="${DOMAIN_NAME:-localhost.direct}"

# Create required directories
mkdir -p "$DATA_DIR/.multi-pb/logs"
mkdir -p /etc/caddy

echo "Configuration:"
echo "  Domain:    ${DOMAIN_NAME}"
echo "  HTTP Port: ${HTTP_PORT}"
echo "  Data Dir:  ${DATA_DIR}"
echo ""

# Export environment for the Go binary
export DATA_DIR
export HTTP_PORT
export HTTPS_PORT
export DOMAIN_NAME
export ENABLE_HTTPS
export ACME_EMAIL

# Start the management server
echo "Starting Multi-PB server..."
exec /usr/local/bin/multipb
