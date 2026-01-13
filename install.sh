#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════╗"
echo "║          Multi-PB Installer              ║"
echo "║   Multi-tenant PocketBase Platform       ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# Check for required commands
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed.${NC}"
        echo "Please install $1 and try again."
        exit 1
    fi
}

echo -e "${YELLOW}Checking requirements...${NC}"
check_command docker
check_command curl

# Check if docker compose is available (v2 or v1)
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo -e "${RED}Error: Docker Compose is not installed.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All requirements met${NC}"
echo ""

# Default values
DEFAULT_DOMAIN="localhost.direct"
DEFAULT_PORT="8080"
DEFAULT_DATA_DIR="./data"
DEFAULT_EMAIL="admin@example.com"

# Prompt for configuration
echo -e "${BLUE}Configuration${NC}"
echo "Press Enter to accept defaults shown in [brackets]"
echo ""

read -p "Domain name [$DEFAULT_DOMAIN]: " DOMAIN_NAME
DOMAIN_NAME="${DOMAIN_NAME:-$DEFAULT_DOMAIN}"

read -p "HTTP port (internal, for reverse proxy) [$DEFAULT_PORT]: " HTTP_PORT
HTTP_PORT="${HTTP_PORT:-$DEFAULT_PORT}"

read -p "Data directory [$DEFAULT_DATA_DIR]: " DATA_DIR
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"

read -p "Admin email (for SSL certs) [$DEFAULT_EMAIL]: " ACME_EMAIL
ACME_EMAIL="${ACME_EMAIL:-$DEFAULT_EMAIL}"

# Check if running behind a reverse proxy
echo ""
read -p "Are you running behind an existing reverse proxy? (y/N): " BEHIND_PROXY
if [[ "$BEHIND_PROXY" =~ ^[Yy]$ ]]; then
    EXPOSE_HTTPS="false"
    echo -e "${YELLOW}Note: Your reverse proxy should handle SSL and proxy to port $HTTP_PORT${NC}"
else
    # For localhost.direct or other local domains, disable HTTPS by default
    if [[ "$DOMAIN_NAME" == "localhost.direct" || "$DOMAIN_NAME" == "localhost" || "$DOMAIN_NAME" =~ \.local$ ]]; then
        EXPOSE_HTTPS="false"
        echo -e "${YELLOW}Note: Using HTTP-only mode for local development${NC}"
        echo -e "${YELLOW}Access tenants via http://tenant.${DOMAIN_NAME}${NC}"
    else
        EXPOSE_HTTPS="true"
        read -p "HTTPS port [$((HTTP_PORT + 363))]: " HTTPS_PORT
        HTTPS_PORT="${HTTPS_PORT:-$((HTTP_PORT + 363))}"
    fi
fi

# Create installation directory
INSTALL_DIR="${DATA_DIR}"
mkdir -p "$INSTALL_DIR"

# Determine script location to find source files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_FROM_SOURCE="false"

# Check if running from source (Dockerfile exists next to this script)
if [ -f "${SCRIPT_DIR}/Dockerfile" ]; then
    BUILD_FROM_SOURCE="true"
fi

echo ""
echo -e "${YELLOW}Creating configuration...${NC}"

# Generate docker-compose.yml
if [ "$BUILD_FROM_SOURCE" = "true" ]; then
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  multi-pb:
    build: .
EOF
else
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  multi-pb:
    image: ghcr.io/multi-pb/multi-pb:latest
EOF
fi

cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    container_name: multi-pb
    restart: unless-stopped
    ports:
      - "${HTTP_PORT}:8080"
      - "80:80"
EOF

if [ "$EXPOSE_HTTPS" = "true" ]; then
cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
      - "${HTTPS_PORT}:8443"
      - "443:443"
EOF
fi

cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    volumes:
      - ./pb_data:/mnt/data
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - DOMAIN_NAME=${DOMAIN_NAME}
      - ACME_EMAIL=${ACME_EMAIL}
      - HTTP_PORT=8080
EOF

if [ "$EXPOSE_HTTPS" = "true" ]; then
cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
      - HTTPS_PORT=8443
      - ENABLE_HTTPS=true
EOF
else
cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
      - ENABLE_HTTPS=false
EOF
fi

cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

volumes:
  caddy_data:
  caddy_config:
EOF

# Create data directory
mkdir -p "$INSTALL_DIR/pb_data"

echo -e "${GREEN}✓ Configuration created${NC}"
echo ""

# Summary
echo -e "${BLUE}Installation Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Domain:     ${GREEN}${DOMAIN_NAME}${NC}"
echo -e "  Dashboard:  ${GREEN}http://localhost:${HTTP_PORT}${NC}"
if [ "$EXPOSE_HTTPS" = "true" ]; then
echo -e "  HTTPS:      ${GREEN}https://localhost:${HTTPS_PORT}${NC}"
fi
echo -e "  Data Dir:   ${GREEN}${INSTALL_DIR}/pb_data${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Ask to start
read -p "Start Multi-PB now? (Y/n): " START_NOW
if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
    echo ""
    echo -e "${YELLOW}Starting Multi-PB...${NC}"
    cd "$INSTALL_DIR"
    
    # For development, build locally instead of pulling
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        echo -e "${YELLOW}Building from local source...${NC}"
        
        # Copy source files to install dir
        cp "${SCRIPT_DIR}/Dockerfile" .
        cp "${SCRIPT_DIR}/entrypoint.sh" .
        cp -r "${SCRIPT_DIR}/cmd" .
        cp -r "${SCRIPT_DIR}/internal" .
        cp -r "${SCRIPT_DIR}/multi-frontend" .
        cp "${SCRIPT_DIR}/go.mod" .
        cp "${SCRIPT_DIR}/go.sum" .
        
        $DOCKER_COMPOSE up -d --build
    else
        $DOCKER_COMPOSE up -d
    fi
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Multi-PB is running!             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Open ${BLUE}http://localhost:${HTTP_PORT}${NC} to complete setup"
    echo ""
    
    # Try to open browser
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:${HTTP_PORT}" 2>/dev/null &
    elif command -v open &> /dev/null; then
        open "http://localhost:${HTTP_PORT}" 2>/dev/null &
    fi
else
    echo ""
    echo -e "To start later, run:"
    echo -e "  ${BLUE}cd ${INSTALL_DIR} && ${DOCKER_COMPOSE} up -d${NC}"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
