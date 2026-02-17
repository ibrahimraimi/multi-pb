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
echo "║   Simple PocketBase Multi-Instance       ║"
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

# Parse command line arguments
CLI_ONLY=false
NON_INTERACTIVE=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --port) MULTIPB_PORT="$2"; shift ;;
        --data-dir) DATA_DIR="$2"; shift ;;
        --name) CONTAINER_NAME="$2"; shift ;;
        --domain) DOMAIN_NAME="$2"; shift ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        --cli-only) CLI_ONLY=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# When piped (e.g. curl ... | bash), stdin is not a TTY: force non-interactive and use defaults
if [ ! -t 0 ]; then
    NON_INTERACTIVE=true
fi

echo -e "${YELLOW}Checking requirements...${NC}"
check_command docker

# Check if docker compose is available (v2 or v1)
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo -e "${RED}Error: Docker Compose is not installed.${NC}"
    exit 1
fi

# Only check curl if not CLI-only (needed for health checks)
if [ "$CLI_ONLY" != "true" ]; then
    check_command curl
fi

echo -e "${GREEN}✓ All requirements met${NC}"
echo ""

# Default values
DEFAULT_PORT="25983"
DEFAULT_DATA_DIR="./multipb-data"
DEFAULT_CONTAINER_NAME="multipb"

# Use provided values or defaults
MULTIPB_PORT="${MULTIPB_PORT:-$DEFAULT_PORT}"
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"

# CLI-only mode: skip dashboard but still install container
# This will be used when building the Docker image

# Prompt for configuration if not non-interactive
if [ "$NON_INTERACTIVE" != "true" ]; then
    echo -e "${BLUE}Configuration${NC}"
    echo "Press Enter to accept defaults shown in [brackets]"
    echo ""

    read -p "External port [$MULTIPB_PORT]: " INPUT_PORT
    MULTIPB_PORT="${INPUT_PORT:-$MULTIPB_PORT}"

    read -p "Data directory [$DATA_DIR]: " INPUT_DATA_DIR
    DATA_DIR="${INPUT_DATA_DIR:-$DATA_DIR}"

    read -p "Container name [$CONTAINER_NAME]: " INPUT_NAME
    CONTAINER_NAME="${INPUT_NAME:-$CONTAINER_NAME}"
    
    read -p "Domain name (optional, enables HTTPS) []: " INPUT_DOMAIN
    DOMAIN_NAME="${INPUT_DOMAIN:-$DOMAIN_NAME}"
fi

# Create installation directory
INSTALL_DIR="$(pwd)"
mkdir -p "$DATA_DIR"

# Determine script location to find source files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_FROM_SOURCE="false"

# Check if running from source (Dockerfile exists next to this script)
if [ -f "${SCRIPT_DIR}/Dockerfile" ]; then
    BUILD_FROM_SOURCE="true"
fi

# When a domain is set, check if ports 80/443 are available
PROXY_MODE="direct"  # direct = Caddy handles TLS on 80/443, external = user's proxy handles TLS
if [ -n "$DOMAIN_NAME" ]; then
    PORT_80_FREE=true
    PORT_443_FREE=true
    if ss -tlnp 2>/dev/null | grep -q ':80 ' || netstat -tlnp 2>/dev/null | grep -q ':80 '; then
        PORT_80_FREE=false
    fi
    if ss -tlnp 2>/dev/null | grep -q ':443 ' || netstat -tlnp 2>/dev/null | grep -q ':443 '; then
        PORT_443_FREE=false
    fi

    if [ "$PORT_80_FREE" = "false" ] || [ "$PORT_443_FREE" = "false" ]; then
        echo ""
        echo -e "${YELLOW}Port 80 and/or 443 are already in use.${NC}"
        echo -e "Another service (nginx, Traefik, Apache, etc.) is using these ports."
        echo ""

        if [ "$NON_INTERACTIVE" = "true" ]; then
            PROXY_MODE="external"
        else
            echo -e "Choose how to handle HTTPS for ${GREEN}${DOMAIN_NAME}${NC}:"
            echo ""
            echo -e "  ${GREEN}1)${NC} External proxy mode (recommended)"
            echo -e "     Multi-PB stays on port ${MULTIPB_PORT} (HTTP only)."
            echo -e "     Configure your existing proxy to forward ${DOMAIN_NAME} → localhost:${MULTIPB_PORT}"
            echo ""
            echo -e "  ${GREEN}2)${NC} Free ports 80/443 and let Multi-PB handle TLS"
            echo -e "     You'll need to stop the service using these ports first."
            echo ""
            read -p "Choice [1]: " PROXY_CHOICE
            PROXY_CHOICE="${PROXY_CHOICE:-1}"
            if [ "$PROXY_CHOICE" = "2" ]; then
                echo ""
                echo -e "${YELLOW}Please free ports 80 and 443, then re-run the installer.${NC}"
                exit 0
            fi
            PROXY_MODE="external"
        fi

        if [ "$PROXY_MODE" = "external" ]; then
            echo -e "${GREEN}Using external proxy mode.${NC}"
            echo -e "Multi-PB will run on port ${MULTIPB_PORT} (HTTP). Your existing proxy handles TLS."
        fi
    fi
fi

echo ""
echo -e "${YELLOW}Creating configuration...${NC}"

# Generate docker-compose.yml
if [ "$BUILD_FROM_SOURCE" = "true" ]; then
    if [ "$CLI_ONLY" = "true" ]; then
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  ${CONTAINER_NAME}:
    build:
      context: ${SCRIPT_DIR}
      args:
        SKIP_DASHBOARD: "true"
EOF
    else
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  ${CONTAINER_NAME}:
    build: ${SCRIPT_DIR}
EOF
    fi
else
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  ${CONTAINER_NAME}:
    image: ghcr.io/n3-rd/multi-pb:latest
EOF
fi

cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "${MULTIPB_PORT}:25983"
EOF

# Only expose 80/443 if domain is set AND we're in direct mode (Caddy handles TLS)
if [ -n "$DOMAIN_NAME" ] && [ "$PROXY_MODE" = "direct" ]; then
cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
      - "80:80"
      - "443:443"
EOF
fi

cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    volumes:
      - ${DATA_DIR}:/var/multipb/data
    environment:
      - MULTIPB_PORT=25983
      - MULTIPB_DATA_DIR=/var/multipb/data
EOF

# Set MULTIPB_DOMAIN only in direct mode (Caddy handles TLS)
# In external proxy mode, Caddy stays HTTP-only on :25983
if [ -n "$DOMAIN_NAME" ] && [ "$PROXY_MODE" = "direct" ]; then
cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
      - MULTIPB_DOMAIN=${DOMAIN_NAME}
EOF
fi

cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:25983/_health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
EOF

echo -e "${GREEN}✓ Configuration created${NC}"
echo ""

# Summary
echo -e "${BLUE}Installation Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Container:  ${GREEN}${CONTAINER_NAME}${NC}"
echo -e "  Port:       ${GREEN}http://localhost:${MULTIPB_PORT}${NC}"
echo -e "  Data Dir:   ${GREEN}${DATA_DIR}${NC}"
if [ -n "$DOMAIN_NAME" ]; then
    echo -e "  Domain:     ${GREEN}${DOMAIN_NAME}${NC}"
    if [ "$PROXY_MODE" = "external" ]; then
        echo -e "  TLS:        ${YELLOW}External proxy (configure your proxy → localhost:${MULTIPB_PORT})${NC}"
    else
        echo -e "  TLS:        ${GREEN}Caddy (automatic HTTPS on ports 80/443)${NC}"
    fi
fi
if [ "$CLI_ONLY" = "true" ]; then
    echo -e "  Mode:       ${YELLOW}CLI-only (no dashboard)${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Ask to start
if [ "$NON_INTERACTIVE" = "true" ]; then
    START_NOW="y"
else
    read -p "Start Multi-PB now? (Y/n): " START_NOW
fi

if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
    echo ""
    echo -e "${YELLOW}Starting Multi-PB...${NC}"
    
    # For development, build locally instead of pulling
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        echo -e "${YELLOW}Building from local source...${NC}"
        $DOCKER_COMPOSE up -d --build
    else
        $DOCKER_COMPOSE up -d
    fi
    
    # Wait for container to be healthy
    echo -e "${YELLOW}Waiting for Multi-PB to be ready...${NC}"
    for i in {1..30}; do
        if docker exec ${CONTAINER_NAME} curl -f http://localhost:25983/_health &>/dev/null; then
            break
        fi
        sleep 1
    done
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Multi-PB is running!             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Health check: ${BLUE}http://localhost:${MULTIPB_PORT}/_health${NC}"
    echo -e "List instances: ${BLUE}http://localhost:${MULTIPB_PORT}/_instances${NC}"
    if [ "$CLI_ONLY" != "true" ]; then
        echo -e "Dashboard: ${BLUE}http://localhost:${MULTIPB_PORT}/dashboard${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Create your first instance:${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} add-instance.sh myapp${NC}"
    echo ""
    echo -e "${YELLOW}Then access it at:${NC}"
    echo -e "  ${BLUE}http://localhost:${MULTIPB_PORT}/myapp/_/${NC}"
    echo ""
    echo -e "${YELLOW}Manage instances:${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} list-instances.sh${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} stop-instance.sh myapp${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} start-instance.sh myapp${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} remove-instance.sh myapp${NC}"
    echo ""
    
    # Show external proxy instructions if applicable
    if [ -n "$DOMAIN_NAME" ] && [ "$PROXY_MODE" = "external" ]; then
        echo ""
        echo -e "${YELLOW}━━━ External Proxy Setup ━━━${NC}"
        echo -e "Configure your reverse proxy to forward ${GREEN}${DOMAIN_NAME}${NC} to ${GREEN}localhost:${MULTIPB_PORT}${NC}"
        echo ""
        echo -e "${BLUE}Nginx example:${NC}"
        echo "  server {"
        echo "      listen 80;"
        echo "      server_name ${DOMAIN_NAME};"
        echo "      location / {"
        echo "          proxy_pass http://127.0.0.1:${MULTIPB_PORT};"
        echo "          proxy_set_header Host \$host;"
        echo "          proxy_set_header X-Real-IP \$remote_addr;"
        echo "          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
        echo "          proxy_set_header X-Forwarded-Proto \$scheme;"
        echo "      }"
        echo "  }"
        echo ""
        echo -e "${BLUE}Caddy example:${NC}"
        echo "  ${DOMAIN_NAME} {"
        echo "      reverse_proxy localhost:${MULTIPB_PORT}"
        echo "  }"
        echo ""
        echo -e "${BLUE}Traefik (docker labels):${NC}"
        echo "  Add to your docker-compose.yml under ${CONTAINER_NAME}:"
        echo "    labels:"
        echo "      - traefik.enable=true"
        echo "      - traefik.http.routers.multipb.rule=Host(\`${DOMAIN_NAME}\`)"
        echo "      - traefik.http.services.multipb.loadbalancer.server.port=25983"
        echo ""
        echo -e "After configuring your proxy, ${GREEN}${DOMAIN_NAME}${NC} will serve Multi-PB."
        echo -e "Your proxy handles TLS — add HTTPS there (e.g. certbot for nginx, automatic for Caddy/Traefik)."
        echo ""
    fi

    # Try to open browser (skip dashboard in CLI-only mode)
    if [ "$CLI_ONLY" != "true" ]; then
        if command -v xdg-open &> /dev/null; then
            xdg-open "http://localhost:${MULTIPB_PORT}/dashboard" 2>/dev/null &
        elif command -v open &> /dev/null; then
            open "http://localhost:${MULTIPB_PORT}/dashboard" 2>/dev/null &
        fi
    fi
else
    echo ""
    echo -e "To start later, run:"
    echo -e "  ${BLUE}${DOCKER_COMPOSE} up -d${NC}"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
