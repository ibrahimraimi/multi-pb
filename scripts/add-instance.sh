#!/bin/sh
set -e

# add-instance.sh - Create and start a new PocketBase instance
# Usage: add-instance.sh <name> [--email <admin_email>] [--password <admin_password>]

MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
MANIFEST_FILE="/var/multipb/data/instances.json"
MIN_PORT=30000
MAX_PORT=39999

# Parse arguments
INSTANCE_NAME=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""
CUSTOM_PORT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --port)
            CUSTOM_PORT="$2"
            shift 2
            ;;
        *)
            if [ -z "$INSTANCE_NAME" ]; then
                INSTANCE_NAME="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$INSTANCE_NAME" ]; then
    echo "Usage: add-instance.sh <name> [--email <admin_email>] [--password <admin_password>]"
    exit 1
fi

# Sanitize instance name (alphanumeric and hyphens only)
INSTANCE_NAME=$(echo "$INSTANCE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

echo "Adding instance: $INSTANCE_NAME"

# Check if manifest exists, create if not
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "{}" > "$MANIFEST_FILE"
fi

# Check if instance already exists
if grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' already exists"
    exit 1
fi

# Get list of used ports
get_used_ports() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.[] | .port' "$MANIFEST_FILE" 2>/dev/null | sort -n || echo ""
    else
        grep -oE '"port":[0-9]+' "$MANIFEST_FILE" 2>/dev/null | grep -oE '[0-9]+' | sort -n || echo ""
    fi
}

# Check if port is available
is_port_available() {
    local port=$1
    local used_ports=$(get_used_ports)
    for used in $used_ports; do
        if [ "$port" -eq "$used" ]; then
            return 1
        fi
    done
    return 0
}

# Determine port to use
if [ -n "$CUSTOM_PORT" ]; then
    # Validate custom port is a number
    if ! echo "$CUSTOM_PORT" | grep -qE '^[0-9]+$'; then
        echo "Error: Port must be a number"
        exit 1
    fi
    
    # Validate port range
    if [ "$CUSTOM_PORT" -lt "$MIN_PORT" ] || [ "$CUSTOM_PORT" -gt "$MAX_PORT" ]; then
        echo "Error: Port must be between $MIN_PORT and $MAX_PORT"
        exit 1
    fi
    
    # Check if port is already in use
    if ! is_port_available "$CUSTOM_PORT"; then
        echo "Error: Port $CUSTOM_PORT is already in use by another instance"
        exit 1
    fi
    
    NEXT_PORT=$CUSTOM_PORT
else
    # Find next available port - optimized version
    NEXT_PORT=$MIN_PORT
    USED_PORTS=$(get_used_ports)
    
    # Find first available port
    for port in $USED_PORTS; do
        if [ $NEXT_PORT -eq $port ]; then
            NEXT_PORT=$((NEXT_PORT + 1))
        elif [ $NEXT_PORT -lt $port ]; then
            break
        fi
    done
    
    if [ $NEXT_PORT -gt $MAX_PORT ]; then
        echo "Error: No available ports in range $MIN_PORT-$MAX_PORT"
        exit 1
    fi
fi

# 1. Create instance data directory
INSTANCE_DIR="$MULTIPB_DATA_DIR/$INSTANCE_NAME"
mkdir -p "$INSTANCE_DIR"

# 2. Check if database exists - if not, we need to initialize it
DB_FILE="$INSTANCE_DIR/data.db"
if [ ! -f "$DB_FILE" ]; then
    echo "Initializing database and running migrations..."
    if ! /usr/local/bin/pocketbase migrate up --dir="$INSTANCE_DIR"; then
        echo "Warning: Initial migration had issues, but continuing..."
    fi
fi

# 3. Create admin user (while service is NOT yet registered/running)
if [ -z "$ADMIN_EMAIL" ]; then
    ADMIN_EMAIL="admin@${INSTANCE_NAME}.local"
fi
if [ -z "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="changeme123"
fi

echo "Creating admin user..."
if /usr/local/bin/pocketbase superuser create "$ADMIN_EMAIL" "$ADMIN_PASSWORD" --dir="$INSTANCE_DIR"; then
    ADMIN_CREATED=true
else
    ADMIN_CREATED=false
    echo "Note: Admin user creation skipped (may already exist)"
fi

# 4. Add to manifest using jq if available
if command -v jq >/dev/null 2>&1; then
    TMP_FILE=$(mktemp)
    jq --arg name "$INSTANCE_NAME" --argjson port "$NEXT_PORT" \
        '.[$name] = {"port": $port, "status": "running", "created": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
        "$MANIFEST_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$MANIFEST_FILE"
else
    # Fallback: simple JSON manipulation
    sed -i "s/{}$/{\n  \"$INSTANCE_NAME\": {\"port\": $NEXT_PORT, \"status\": \"running\", \"created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}\n}/" "$MANIFEST_FILE"
fi

echo "Instance '$INSTANCE_NAME' added to manifest with port $NEXT_PORT"

# 5. Create supervisord program config
SUPERVISOR_CONF="/etc/supervisor/conf.d/${INSTANCE_NAME}.conf"
cat > "$SUPERVISOR_CONF" << EOF
[program:pb-${INSTANCE_NAME}]
command=/usr/local/bin/pocketbase serve --dir=${INSTANCE_DIR} --http=127.0.0.1:${NEXT_PORT}
directory=${INSTANCE_DIR}
autostart=true
autorestart=true
startretries=3
stderr_logfile=/var/log/multipb/${INSTANCE_NAME}.err.log
stdout_logfile=/var/log/multipb/${INSTANCE_NAME}.log
stderr_logfile_maxbytes=10MB
stdout_logfile_maxbytes=10MB
stderr_logfile_backups=3
stdout_logfile_backups=3
user=root
environment=HOME="/root"
EOF

# 6. Reload supervisord to start the service
SUPERVISORCTL="supervisorctl -c /etc/supervisor/supervisord.conf -s unix:///var/run/supervisor.sock"
if command -v supervisorctl >/dev/null 2>&1 && [ -S /var/run/supervisor.sock ]; then
    echo "Registering with supervisord..."
    $SUPERVISORCTL reread >/dev/null 2>&1
    $SUPERVISORCTL update >/dev/null 2>&1
    echo "Instance service started"
fi

# 7. Regenerate Caddy config
/usr/local/bin/reload-proxy.sh

# Get the actual external port
ACTUAL_PORT="${MULTIPB_PORT:-25983}"

echo ""
echo "✓ Instance '$INSTANCE_NAME' is ready!"
echo "  URL: http://localhost:${ACTUAL_PORT}/${INSTANCE_NAME}/_/"
if [ "$ADMIN_CREATED" = true ]; then
    echo "  Admin: $ADMIN_EMAIL / $ADMIN_PASSWORD"
fi
