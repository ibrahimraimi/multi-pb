#!/bin/sh
set -e

echo "╔══════════════════════════════════════════╗"
echo "║    Multi-PB - Simple & Scalable          ║"
echo "║    PocketBase Multi-Instance Manager     ║"
echo "╚══════════════════════════════════════════╝"

# Configuration from environment
export MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
export MULTIPB_PORT="${MULTIPB_PORT:-25983}"
MANIFEST_FILE="/var/multipb/instances.json"

echo ""
echo "Configuration:"
echo "  Port:      ${MULTIPB_PORT}"
echo "  Data Dir:  ${MULTIPB_DATA_DIR}"
echo ""

# Create required directories
mkdir -p "${MULTIPB_DATA_DIR}"
mkdir -p /var/log/multipb
mkdir -p /etc/caddy
mkdir -p /etc/supervisor/conf.d
mkdir -p /var/multipb

# Initialize manifest if it doesn't exist
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "{}" > "$MANIFEST_FILE"
    echo "Initialized empty manifest"
fi

# Generate initial Caddyfile
echo "Generating initial Caddy configuration..."
/usr/local/bin/reload-proxy.sh

# Create supervisord main config if it doesn't exist
if [ ! -f /etc/supervisor/supervisord.conf ]; then
    cat > /etc/supervisor/supervisord.conf << 'EOF'
[supervisord]
nodaemon=true
user=root
logfile=/var/log/multipb/supervisord.log
pidfile=/var/run/supervisord.pid
loglevel=info
childlogdir=/var/log/multipb

[unix_http_server]
file=/var/run/supervisor.sock

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[include]
files = /etc/supervisor/conf.d/*.conf

[program:caddy]
command=/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
autostart=true
autorestart=true
startretries=5
stderr_logfile=/var/log/multipb/caddy.err.log
stdout_logfile=/var/log/multipb/caddy.log
stderr_logfile_maxbytes=10MB
stdout_logfile_maxbytes=10MB
user=root
priority=1

[program:api-server]
command=/usr/bin/node /usr/local/bin/api-server.js
autostart=true
autorestart=true
startretries=5
stderr_logfile=/var/log/multipb/api-server.err.log
stdout_logfile=/var/log/multipb/api-server.log
stderr_logfile_maxbytes=10MB
stdout_logfile_maxbytes=10MB
user=root
priority=2
EOF
fi

# Restore existing instances from manifest
echo "Restoring instances from manifest..."
if [ -f "$MANIFEST_FILE" ] && command -v jq >/dev/null 2>&1; then
    INSTANCE_COUNT=$(jq 'length' "$MANIFEST_FILE")
    if [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo "Found $INSTANCE_COUNT instance(s) to restore"
        
        # Use process substitution to avoid subshell issue
        while read -r instance_name port; do
            INSTANCE_DIR="${MULTIPB_DATA_DIR}/${instance_name}"
            mkdir -p "$INSTANCE_DIR"
            
            # Create supervisord config for this instance
            SUPERVISOR_CONF="/etc/supervisor/conf.d/${instance_name}.conf"
            if [ ! -f "$SUPERVISOR_CONF" ]; then
                cat > "$SUPERVISOR_CONF" << EOF
[program:pb-${instance_name}]
command=/usr/local/bin/pocketbase serve --dir=${INSTANCE_DIR} --http=127.0.0.1:${port}
directory=${INSTANCE_DIR}
autostart=true
autorestart=true
startretries=3
stderr_logfile=/var/log/multipb/${instance_name}.err.log
stdout_logfile=/var/log/multipb/${instance_name}.log
stderr_logfile_maxbytes=10MB
stdout_logfile_maxbytes=10MB
stderr_logfile_backups=3
stdout_logfile_backups=3
user=root
environment=HOME="/root"
EOF
                echo "  - $instance_name (port $port)"
            fi
        done < <(jq -r 'to_entries[] | "\(.key) \(.value.port)"' "$MANIFEST_FILE")
    else
        echo "No instances to restore"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Multi-PB is starting..."
echo ""
echo "Access at: http://<host>:${MULTIPB_PORT}"
echo "Dashboard: http://<host>:${MULTIPB_PORT}/dashboard"
echo "Health check: http://<host>:${MULTIPB_PORT}/_health"
echo "List instances: http://<host>:${MULTIPB_PORT}/_instances"
echo ""
echo "Manage instances:"
echo "  docker exec <container> add-instance.sh <name>"
echo "  docker exec <container> list-instances.sh"
echo "  docker exec <container> remove-instance.sh <name>"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start supervisord (manages Caddy and all PocketBase instances)
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
