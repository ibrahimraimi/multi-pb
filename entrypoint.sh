#!/bin/bash
set -e

DOMAIN_NAME="${DOMAIN_NAME:-localhost.direct}"
ACME_EMAIL="${ACME_EMAIL:-admin@example.com}"
LOCAL_DEV="${LOCAL_DEV:-false}"
BASE_PORT=8081
DATA_DIR="/mnt/data"

CADDYFILE="/etc/Caddyfile"
SUPERVISORD_CONF="/etc/supervisord.conf"

# Initialize Caddyfile
if [ "$LOCAL_DEV" = "true" ]; then
    # Use Caddy's internal CA for local development (self-signed certs)
    echo -e "{\n    local_certs\n}" > "$CADDYFILE"
else
    cat /etc/Caddyfile.template > "$CADDYFILE"
    sed -i "s/{{ACME_EMAIL}}/${ACME_EMAIL}/g" "$CADDYFILE"
fi

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
    
    # Sanitize tenant name for supervisord (alphanumeric + dash/underscore only)
    tenant_safe=$(echo "$tenant" | sed 's/[^a-zA-Z0-9_-]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    
    # Skip if tenant name becomes empty after sanitization
    [[ -z "$tenant_safe" ]] && continue
    
    # Check port exhaustion (max 65535, but be conservative)
    if [ "$current_port" -gt 65530 ]; then
        echo "ERROR: Port exhaustion! Too many instances (max ~65530)"
        exit 1
    fi
    
    hostname="${tenant}.${DOMAIN_NAME}"
    
    echo "Configuring: ${hostname} -> localhost:${current_port}"
    
    # Append Caddy reverse proxy block with security headers
    cat >> "$CADDYFILE" << EOF

${hostname} {
    header {
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
        -Server
    }
    reverse_proxy localhost:${current_port}
}
EOF

    # Append supervisord program block for this PocketBase instance
    cat >> "$SUPERVISORD_CONF" << EOF

[program:pb-${tenant_safe}]
command=/usr/local/bin/pocketbase serve --dir=${DATA_DIR}/${tenant} --http=127.0.0.1:${current_port}
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/pb-${tenant_safe}.err.log
stdout_logfile=/var/log/supervisor/pb-${tenant_safe}.out.log
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile_backups=3
EOF

    current_port=$((current_port + 1))
    instance_count=$((instance_count + 1))
done

# Append Caddy program to supervisord.conf
cat >> "$SUPERVISORD_CONF" << EOF

[program:caddy]
command=caddy run --config ${CADDYFILE} --adapter caddyfile
environment=CADDY_DATA_DIR="/data",CADDY_CONFIG_DIR="/config"
autostart=true
autorestart=true
stderr_logfile=/var/log/supervisor/caddy.err.log
stdout_logfile=/var/log/supervisor/caddy.out.log
stdout_logfile_maxbytes=10MB
stderr_logfile_maxbytes=10MB
stdout_logfile_backups=3
stderr_logfile_backups=3
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
