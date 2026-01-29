#!/bin/sh
set -e

echo "╔══════════════════════════════════════════╗"
echo "║    Multi-PB - Simple & Scalable          ║"
echo "║    PocketBase Multi-Instance Manager     ║"
echo "╚══════════════════════════════════════════╝"

# Configuration from environment
export MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
export MULTIPB_PORT="${MULTIPB_PORT:-25983}"
MANIFEST_FILE="/var/multipb/data/instances.json"

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
mkdir -p /var/multipb/data/versions

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
logfile=/dev/stdout
logfile_maxbytes=0
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
stderr_logfile=/dev/stderr
stdout_logfile=/dev/stdout
stderr_logfile_maxbytes=0
stdout_logfile_maxbytes=0
user=root
priority=1

[program:api-server]
command=/usr/bin/node /usr/local/bin/api-server.js
autostart=true
autorestart=true
startretries=5
stderr_logfile=/dev/stderr
stdout_logfile=/dev/stdout
stderr_logfile_maxbytes=0
stdout_logfile_maxbytes=0
user=root
priority=2

[program:log-streamer]
command=/usr/bin/tail -F /var/log/multipb/caddy.log /var/log/multipb/api-server.log /var/log/multipb/*.log
autostart=true
autorestart=true
user=root
priority=100
EOF
fi

# Restore instances in background using supervisord
cat >> /etc/supervisor/supervisord.conf << 'EOF'

[program:restore-instances]
command=/usr/local/bin/restore-instances.sh
autostart=true
autorestart=false
startretries=0
stderr_logfile=/var/log/multipb/restore.err.log
stdout_logfile=/var/log/multipb/restore.log
user=root
priority=10
EOF

# Restore logic moved to restore-instances.sh
echo "Configured background instance restoration"

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
