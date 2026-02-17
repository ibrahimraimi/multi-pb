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
PROXY_AUTO_CONFIG="none"  # none, nginx, or traefik
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
        PROXY_MODE="external"

        # Detect what's on port 80
        DETECTED_PROXY=""
        PORT80_PID=$(ss -tlnp 2>/dev/null | grep ':80 ' | grep -oP 'pid=\K[0-9]+' | head -1)
        if [ -n "$PORT80_PID" ]; then
            PORT80_PROC=$(ps -p "$PORT80_PID" -o comm= 2>/dev/null || echo "")
            case "$PORT80_PROC" in
                nginx*)
                    DETECTED_PROXY="nginx"
                    ;;
                docker-proxy*|docker*)
                    PORT80_CONTAINER=$(docker ps --format '{{.Names}}' --filter "publish=80" 2>/dev/null | head -1)
                    if [ -n "$PORT80_CONTAINER" ]; then
                        PORT80_IMAGE=$(docker inspect "$PORT80_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null || echo "")
                        case "$PORT80_IMAGE" in
                            *traefik*) DETECTED_PROXY="traefik"; TRAEFIK_CONTAINER="$PORT80_CONTAINER" ;;
                            *caddy*)   DETECTED_PROXY="caddy-external" ;;
                            *nginx*)   DETECTED_PROXY="nginx-docker" ;;
                            *)         DETECTED_PROXY="docker-unknown" ;;
                        esac
                    fi
                    ;;
                apache2*|httpd*)
                    DETECTED_PROXY="apache"
                    ;;
                caddy*)
                    DETECTED_PROXY="caddy-external"
                    ;;
            esac
        fi

        if [ -n "$DETECTED_PROXY" ]; then
            echo -e "Detected: ${GREEN}${DETECTED_PROXY}${NC}"
        else
            echo -e "Could not detect which service is using port 80."
        fi
        echo ""

        # Offer auto-config based on detected proxy
        PROXY_AUTO_CONFIG="none"
        if [ "$NON_INTERACTIVE" = "true" ]; then
            # Non-interactive: auto-configure if we can, otherwise manual
            case "$DETECTED_PROXY" in
                nginx)
                    if command -v nginx &>/dev/null; then
                        PROXY_AUTO_CONFIG="nginx"
                    fi
                    ;;
                traefik)
                    PROXY_AUTO_CONFIG="traefik"
                    ;;
            esac
        else
            case "$DETECTED_PROXY" in
                nginx)
                    echo -e "Choose how to set up ${GREEN}${DOMAIN_NAME}${NC}:"
                    echo ""
                    echo -e "  ${GREEN}1)${NC} Auto-configure nginx"
                    echo -e "     Writes a site config, reloads nginx, optionally sets up HTTPS with certbot."
                    echo ""
                    echo -e "  ${GREEN}2)${NC} Manual setup (print instructions only)"
                    echo ""
                    echo -e "  ${GREEN}3)${NC} Free ports 80/443 and let Multi-PB handle TLS instead"
                    echo ""
                    read -p "Choice [1]: " PROXY_CHOICE
                    PROXY_CHOICE="${PROXY_CHOICE:-1}"
                    case "$PROXY_CHOICE" in
                        1) PROXY_AUTO_CONFIG="nginx" ;;
                        3)
                            echo ""
                            echo -e "${YELLOW}Please free ports 80 and 443, then re-run the installer.${NC}"
                            exit 0
                            ;;
                        *) PROXY_AUTO_CONFIG="none" ;;
                    esac
                    ;;
                traefik)
                    echo -e "Choose how to set up ${GREEN}${DOMAIN_NAME}${NC}:"
                    echo ""
                    echo -e "  ${GREEN}1)${NC} Auto-configure Traefik"
                    echo -e "     Adds labels and connects to Traefik's docker network."
                    echo ""
                    echo -e "  ${GREEN}2)${NC} Manual setup (print instructions only)"
                    echo ""
                    echo -e "  ${GREEN}3)${NC} Free ports 80/443 and let Multi-PB handle TLS instead"
                    echo ""
                    read -p "Choice [1]: " PROXY_CHOICE
                    PROXY_CHOICE="${PROXY_CHOICE:-1}"
                    case "$PROXY_CHOICE" in
                        1) PROXY_AUTO_CONFIG="traefik" ;;
                        3)
                            echo ""
                            echo -e "${YELLOW}Please free ports 80 and 443, then re-run the installer.${NC}"
                            exit 0
                            ;;
                        *) PROXY_AUTO_CONFIG="none" ;;
                    esac
                    ;;
                *)
                    echo -e "Choose how to handle HTTPS for ${GREEN}${DOMAIN_NAME}${NC}:"
                    echo ""
                    echo -e "  ${GREEN}1)${NC} External proxy mode (print setup instructions)"
                    echo -e "     Multi-PB stays on port ${MULTIPB_PORT} (HTTP only)."
                    echo -e "     You configure your existing proxy to forward ${DOMAIN_NAME} → localhost:${MULTIPB_PORT}"
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
                    ;;
            esac
        fi

        echo -e "${GREEN}Using external proxy mode.${NC}"
        echo -e "Multi-PB will run on port ${MULTIPB_PORT} (HTTP). Your existing proxy handles TLS."
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

# Traefik auto-config: add labels and discover network
if [ "$PROXY_AUTO_CONFIG" = "traefik" ]; then
    TRAEFIK_NETWORK=""
    if [ -n "$TRAEFIK_CONTAINER" ]; then
        TRAEFIK_NETWORK=$(docker inspect "$TRAEFIK_CONTAINER" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null | awk '{print $1}')
    fi
    # Fallback: check common network names
    if [ -z "$TRAEFIK_NETWORK" ] || [ "$TRAEFIK_NETWORK" = "bridge" ]; then
        for net in traefik web proxy traefik-public; do
            if docker network inspect "$net" &>/dev/null; then
                TRAEFIK_NETWORK="$net"
                break
            fi
        done
    fi
    if [ -n "$TRAEFIK_NETWORK" ] && [ "$TRAEFIK_NETWORK" != "bridge" ]; then
        echo -e "${GREEN}Detected Traefik network: ${TRAEFIK_NETWORK}${NC}"
    else
        TRAEFIK_NETWORK="web"
        echo -e "${YELLOW}Could not detect Traefik network, using '${TRAEFIK_NETWORK}'. Edit docker-compose.yml if different.${NC}"
    fi
cat >> "$INSTALL_DIR/docker-compose.yml" << EOF
    labels:
      - traefik.enable=true
      - traefik.http.routers.multipb.rule=Host(\`${DOMAIN_NAME}\`)
      - traefik.http.routers.multipb.entrypoints=websecure
      - traefik.http.routers.multipb.tls.certresolver=letsencrypt
      - traefik.http.services.multipb.loadbalancer.server.port=25983
    networks:
      - ${TRAEFIK_NETWORK}
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

# Close Traefik external network definition
if [ "$PROXY_AUTO_CONFIG" = "traefik" ] && [ -n "$TRAEFIK_NETWORK" ]; then
cat >> "$INSTALL_DIR/docker-compose.yml" << EOF

networks:
  ${TRAEFIK_NETWORK}:
    external: true
EOF
fi

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
        if [ "$PROXY_AUTO_CONFIG" = "nginx" ]; then
            echo -e "  TLS:        ${GREEN}Nginx (auto-configured + certbot)${NC}"
        elif [ "$PROXY_AUTO_CONFIG" = "traefik" ]; then
            echo -e "  TLS:        ${GREEN}Traefik (auto-configured via labels)${NC}"
        else
            echo -e "  TLS:        ${YELLOW}External proxy (configure your proxy → localhost:${MULTIPB_PORT})${NC}"
        fi
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
    
    # External proxy: auto-configure or print instructions
    if [ -n "$DOMAIN_NAME" ] && [ "$PROXY_MODE" = "external" ]; then
        echo ""

        if [ "$PROXY_AUTO_CONFIG" = "nginx" ]; then
            # ── Nginx auto-config ──
            echo -e "${YELLOW}━━━ Configuring Nginx ━━━${NC}"

            # Find nginx config directory
            NGINX_CONF_DIR=""
            if [ -d "/etc/nginx/sites-available" ]; then
                NGINX_CONF_DIR="/etc/nginx/sites-available"
                NGINX_LINK_DIR="/etc/nginx/sites-enabled"
            elif [ -d "/etc/nginx/conf.d" ]; then
                NGINX_CONF_DIR="/etc/nginx/conf.d"
                NGINX_LINK_DIR=""
            fi

            if [ -z "$NGINX_CONF_DIR" ]; then
                echo -e "${RED}Could not find nginx config directory. Printing manual instructions instead.${NC}"
                PROXY_AUTO_CONFIG="none"
            else
                NGINX_CONF_FILE="${NGINX_CONF_DIR}/multipb-${DOMAIN_NAME}.conf"
                echo -e "Writing config to ${GREEN}${NGINX_CONF_FILE}${NC}"

                cat > "$NGINX_CONF_FILE" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME};

    location / {
        proxy_pass http://127.0.0.1:${MULTIPB_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
NGINXEOF

                # Symlink if using sites-available/sites-enabled pattern
                if [ -n "$NGINX_LINK_DIR" ] && [ -d "$NGINX_LINK_DIR" ]; then
                    ln -sf "$NGINX_CONF_FILE" "${NGINX_LINK_DIR}/multipb-${DOMAIN_NAME}.conf"
                    echo -e "Symlinked to ${GREEN}${NGINX_LINK_DIR}/multipb-${DOMAIN_NAME}.conf${NC}"
                fi

                # Test and reload
                if nginx -t 2>/dev/null; then
                    nginx -s reload 2>/dev/null || systemctl reload nginx 2>/dev/null || true
                    echo -e "${GREEN}✓ Nginx configured and reloaded${NC}"
                    echo -e "  ${GREEN}${DOMAIN_NAME}${NC} → localhost:${MULTIPB_PORT} (HTTP)"

                    # Offer certbot for HTTPS
                    CERTBOT_DONE=false
                    if command -v certbot &>/dev/null; then
                        echo ""
                        if [ "$NON_INTERACTIVE" = "true" ]; then
                            echo -e "${YELLOW}Certbot detected. Run this to enable HTTPS:${NC}"
                            echo -e "  ${BLUE}certbot --nginx -d ${DOMAIN_NAME}${NC}"
                        else
                            read -p "Certbot detected. Set up HTTPS now? (Y/n): " CERTBOT_CHOICE
                            CERTBOT_CHOICE="${CERTBOT_CHOICE:-y}"
                            if [[ ! "$CERTBOT_CHOICE" =~ ^[Nn]$ ]]; then
                                echo -e "${YELLOW}Running certbot...${NC}"
                                if certbot --nginx -d "${DOMAIN_NAME}" --non-interactive --agree-tos --redirect --register-unsafely-without-email 2>&1; then
                                    echo -e "${GREEN}✓ HTTPS enabled for ${DOMAIN_NAME}${NC}"
                                    CERTBOT_DONE=true
                                else
                                    echo -e "${YELLOW}Certbot failed. You can retry manually:${NC}"
                                    echo -e "  ${BLUE}certbot --nginx -d ${DOMAIN_NAME}${NC}"
                                fi
                            fi
                        fi
                    else
                        echo ""
                        echo -e "${YELLOW}To enable HTTPS, install certbot and run:${NC}"
                        echo -e "  ${BLUE}apt install -y certbot python3-certbot-nginx${NC}"
                        echo -e "  ${BLUE}certbot --nginx -d ${DOMAIN_NAME}${NC}"
                    fi
                else
                    echo -e "${RED}Nginx config test failed. Check ${NGINX_CONF_FILE} manually.${NC}"
                    nginx -t 2>&1 || true
                fi
            fi

        elif [ "$PROXY_AUTO_CONFIG" = "traefik" ]; then
            # ── Traefik auto-config ──
            echo -e "${GREEN}✓ Traefik labels added to docker-compose.yml${NC}"
            echo -e "  ${GREEN}${DOMAIN_NAME}${NC} → multipb container (port 25983)"
            echo -e "  Traefik will handle TLS automatically."
            echo ""
        fi

        # Fallback: manual instructions for anything we couldn't auto-configure
        if [ "$PROXY_AUTO_CONFIG" = "none" ]; then
            echo -e "${YELLOW}━━━ External Proxy Setup ━━━${NC}"
            echo -e "Configure your reverse proxy to forward ${GREEN}${DOMAIN_NAME}${NC} to ${GREEN}localhost:${MULTIPB_PORT}${NC}"
            echo ""
            echo -e "${BLUE}Nginx:${NC}"
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
            echo -e "${BLUE}Caddy:${NC}"
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
            echo -e "Your proxy handles TLS — add HTTPS there (e.g. certbot for nginx, automatic for Caddy/Traefik)."
        fi
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
