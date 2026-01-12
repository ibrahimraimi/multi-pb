#!/bin/bash
set -e

DOMAIN_NAME="${DOMAIN_NAME:-localhost.direct}"
ACME_EMAIL="${ACME_EMAIL:-admin@example.com}"
BASE_PORT=8081
DATA_DIR="/mnt/data"

CADDYFILE="/etc/Caddyfile"
SUPERVISORD_CONF="/etc/supervisord.conf"

# Initialize Caddyfile from template
cat /etc/Caddyfile.template > "$CADDYFILE"
sed -i "s/{{ACME_EMAIL}}/${ACME_EMAIL}/g" "$CADDYFILE"

# Initialize supervisord.conf from template
cat /etc/supervisord.conf.template > "$SUPERVISORD_CONF"

current_port=$BASE_PORT
instance_count=0

echo "Scanning for PocketBase instances in ${DATA_DIR}..."

# Iterate through directories in /mnt/data
for dir in "${DATA_DIR}"/*/; do
    # Skip if no directories found (glob didn't expand)
    [ -d "$dir" ] || continue
    
    # Extract tenant name from directory path
    tenant=$(basename "$dir")
    
    # Skip hidden directories
    [[ "$tenant" == .* ]] && continue
    
    hostname="${tenant}.${DOMAIN_NAME}"
    
    echo "Configuring: ${hostname} -> localhost:${current_port}"
    
    # Append Caddy reverse proxy block
    cat >> "$CADDYFILE" << EOF

${hostname} {
    reverse_proxy localhost:${current_port}
}
EOF

    # Append supervisord program block for this PocketBase instance
    cat >> "$SUPERVISORD_CONF" << EOF

[program:pb-${tenant}]
command=/usr/local/bin/pocketbase serve --dir=${DATA_DIR}/${tenant} --http=127.0.0.1:${current_port}
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/pb-${tenant}.err.log
stdout_logfile=/var/log/supervisor/pb-${tenant}.out.log
stdout_logfile_maxbytes=1MB
stderr_logfile_maxbytes=1MB
EOF

    ((current_port++))
    ((instance_count++))
done

# Append Caddy program to supervisord.conf
cat >> "$SUPERVISORD_CONF" << EOF

[program:caddy]
command=caddy run --config ${CADDYFILE} --adapter caddyfile
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/caddy.err.log
stdout_logfile=/var/log/supervisor/caddy.out.log
stdout_logfile_maxbytes=1MB
stderr_logfile_maxbytes=1MB
EOF

echo "============================================"
echo "Configured ${instance_count} PocketBase instance(s)"
echo "Domain: ${DOMAIN_NAME}"
echo "============================================"

if [ "$instance_count" -eq 0 ]; then
    echo "WARNING: No tenant directories found in ${DATA_DIR}"
    echo "Create subdirectories like ${DATA_DIR}/myapp to add tenants"
fi

# Start supervisord
exec /usr/bin/supervisord -n -c "$SUPERVISORD_CONF"
