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

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --port) MULTIPB_PORT="$2"; shift ;;
        --data-dir) DATA_DIR="$2"; shift ;;
        --name) CONTAINER_NAME="$2"; shift ;;
        --non-interactive) NON_INTERACTIVE=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Default values
DEFAULT_PORT="25983"
DEFAULT_DATA_DIR="./multipb-data"
DEFAULT_CONTAINER_NAME="multipb"

# Use provided values or defaults
MULTIPB_PORT="${MULTIPB_PORT:-$DEFAULT_PORT}"
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
CONTAINER_NAME="${CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"

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

echo ""
echo -e "${YELLOW}Creating configuration...${NC}"

# Generate docker-compose.yml
if [ "$BUILD_FROM_SOURCE" = "true" ]; then
cat > "$INSTALL_DIR/docker-compose.yml" << EOF
services:
  ${CONTAINER_NAME}:
    build: ${SCRIPT_DIR}
EOF
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
    volumes:
      - ${DATA_DIR}:/var/multipb/data
    environment:
      - MULTIPB_PORT=25983
      - MULTIPB_DATA_DIR=/var/multipb/data
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
    echo ""
    echo -e "${YELLOW}Create your first instance:${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} add-instance.sh myapp${NC}"
    echo ""
    echo -e "${YELLOW}Then access it at:${NC}"
    echo -e "  ${BLUE}http://localhost:${MULTIPB_PORT}/myapp/${NC}"
    echo ""
    echo -e "${YELLOW}Manage instances:${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} list-instances.sh${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} stop-instance.sh myapp${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} start-instance.sh myapp${NC}"
    echo -e "  ${BLUE}docker exec ${CONTAINER_NAME} remove-instance.sh myapp${NC}"
    echo ""
    
    # Try to open browser
    if command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:${MULTIPB_PORT}/_health" 2>/dev/null &
    elif command -v open &> /dev/null; then
        open "http://localhost:${MULTIPB_PORT}/_health" 2>/dev/null &
    fi
else
    echo ""
    echo -e "To start later, run:"
    echo -e "  ${BLUE}${DOCKER_COMPOSE} up -d${NC}"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
