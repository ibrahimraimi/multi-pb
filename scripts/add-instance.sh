#!/bin/sh
set -e

# add-instance.sh - Create and start a new PocketBase instance
# Usage: add-instance.sh <name> [--email <admin_email>] [--password <admin_password>]

MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
MANIFEST_FILE="/var/multipb/instances.json"
MIN_PORT=30000
MAX_PORT=39999

# Parse arguments
INSTANCE_NAME=""
ADMIN_EMAIL=""
ADMIN_PASSWORD=""

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

# Find next available port - optimized version
NEXT_PORT=$MIN_PORT

if command -v jq >/dev/null 2>&1; then
    # Extract all used ports and sort them
    USED_PORTS=$(jq -r '.[] | .port' "$MANIFEST_FILE" 2>/dev/null | sort -n || echo "")
    
    # Find first available port
    for port in $USED_PORTS; do
        if [ $NEXT_PORT -eq $port ]; then
            NEXT_PORT=$((NEXT_PORT + 1))
        elif [ $NEXT_PORT -lt $port ]; then
            break
        fi
    done
else
    # Fallback: simple linear search
    while [ $NEXT_PORT -le $MAX_PORT ]; do
        if ! grep -q ":$NEXT_PORT" "$MANIFEST_FILE"; then
            break
        fi
        NEXT_PORT=$((NEXT_PORT + 1))
    done
fi

if [ $NEXT_PORT -gt $MAX_PORT ]; then
    echo "Error: No available ports in range $MIN_PORT-$MAX_PORT"
    exit 1
fi

# Create instance data directory
INSTANCE_DIR="$MULTIPB_DATA_DIR/$INSTANCE_NAME"
mkdir -p "$INSTANCE_DIR"

# Add to manifest using jq if available, otherwise use basic sed
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

echo "Instance '$INSTANCE_NAME' added with port $NEXT_PORT"
echo "Data directory: $INSTANCE_DIR"

# Create supervisord program config
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

echo "Supervisord config created: $SUPERVISOR_CONF"

# Reload supervisord
if command -v supervisorctl >/dev/null 2>&1; then
    # Check if supervisord is actually running (with retry for startup timing)
    SUPERVISOR_READY=false
    for i in 1 2 3; do
        if supervisorctl status >/dev/null 2>&1; then
            SUPERVISOR_READY=true
            break
        fi
        if [ $i -lt 3 ]; then
            sleep 1
        fi
    done
    
    if [ "$SUPERVISOR_READY" = true ]; then
        echo "Reloading supervisord configuration..."
        supervisorctl reread >/dev/null 2>&1
        supervisorctl update >/dev/null 2>&1
        
        # Try to start the instance
        if supervisorctl start "pb-${INSTANCE_NAME}" >/dev/null 2>&1; then
            echo "Instance started via supervisord"
        else
            echo "Warning: Could not start instance (will start on next container restart)"
        fi
    else
        echo "Note: supervisord not ready yet (instance will start automatically)"
        echo "      Container may still be initializing. Check with: docker logs multipb"
    fi
else
    echo "Warning: supervisorctl not available (instance will start on next container restart)"
fi

# Regenerate Caddy config
/usr/local/bin/reload-proxy.sh

echo ""
echo "✓ Instance '$INSTANCE_NAME' is ready!"
echo "  Access at: http://<host>:\${MULTIPB_PORT}/${INSTANCE_NAME}/"
if [ -n "$ADMIN_EMAIL" ] && [ -n "$ADMIN_PASSWORD" ]; then
    echo "  Admin setup will use provided credentials"
    echo "  (Note: Auto-setup not yet implemented, please configure manually)"
fi
