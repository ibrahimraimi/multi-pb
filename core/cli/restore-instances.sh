#!/bin/bash
set -e

MANIFEST_FILE="/var/multipb/data/instances.json"
MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
STATUS_FILE="/var/multipb/restore.status"

# Initialize status
# Format: JSON-like content for simple parsing
echo '{"restoring":true,"current":"","completed":0,"total":0}' > "$STATUS_FILE"

if [ -f "$MANIFEST_FILE" ] && command -v jq >/dev/null 2>&1; then
    INSTANCE_COUNT=$(jq 'length' "$MANIFEST_FILE")
    
    # Update total
    echo "{\"restoring\":true,\"current\":\"Starting...\",\"completed\":0,\"total\":$INSTANCE_COUNT}" > "$STATUS_FILE"
    
    if [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo "Found $INSTANCE_COUNT instance(s) to restore"
        
        COUNT=0
        # Use a portable while loop
        jq -r 'to_entries[] | "\(.key) \(.value.port) \(.value.version // "0.23.4")"' "$MANIFEST_FILE" | while read -r instance_name port version; do
            COUNT=$((COUNT + 1))
            
            # Update status
            echo "{\"restoring\":true,\"current\":\"$instance_name\",\"completed\":$((COUNT-1)),\"total\":$INSTANCE_COUNT}" > "$STATUS_FILE"
            
            INSTANCE_DIR="${MULTIPB_DATA_DIR}/${instance_name}"
            mkdir -p "$INSTANCE_DIR"
            
            # Determine PocketBase binary path
            PB_BINARY="/usr/local/bin/pocketbase"
            if [ -n "$version" ] && command -v manage-versions.sh >/dev/null 2>&1; then
                # Try to get version-specific binary
                if VERSION_BINARY=$(/usr/local/bin/manage-versions.sh path "$version" 2>/dev/null); then
                    PB_BINARY="$VERSION_BINARY"
                else
                    # Download version if not available
                    echo "  Downloading PocketBase v$version for $instance_name..."
                    /usr/local/bin/manage-versions.sh download "$version" >/dev/null 2>&1 && \
                        PB_BINARY=$(/usr/local/bin/manage-versions.sh path "$version" 2>/dev/null) || \
                        echo "  Warning: Failed to download v$version, using default binary"
                fi
            fi
            
            # Create supervisord config for this instance
            SUPERVISOR_CONF="/etc/supervisor/conf.d/${instance_name}.conf"
            # Always recreate config to ensure latest settings or paths
            MEMORY_LIMIT=$(jq -r --arg name "$instance_name" '.[$name].memory // ""' "$MANIFEST_FILE" 2>/dev/null || echo "")
            cat > "$SUPERVISOR_CONF" << EOF
[program:pb-${instance_name}]
command=${PB_BINARY} serve --dir=${INSTANCE_DIR} --http=127.0.0.1:${port}
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
environment=HOME="/root"$(test -n "$MEMORY_LIMIT" && echo ",GOMEMLIMIT=\"$MEMORY_LIMIT\"")
EOF
            echo "  - $instance_name (port $port, version ${version:-default})"
            
            # Update status after processing
             echo "{\"restoring\":true,\"current\":\"$instance_name (Done)\",\"completed\":$COUNT,\"total\":$INSTANCE_COUNT}" > "$STATUS_FILE"
        done
        
        # Reload supervisor to pick up new configs and start instances
        echo "{\"restoring\":true,\"current\":\"Finalizing configuration...\",\"completed\":$INSTANCE_COUNT,\"total\":$INSTANCE_COUNT}" > "$STATUS_FILE"
        echo "Reloading supervisor..."
        
        # Must specify config file for supervisorctl to find the socket
        supervisorctl -c /etc/supervisor/supervisord.conf reread || echo "Warning: supervisorctl reread failed"
        
        echo "{\"restoring\":true,\"current\":\"Starting instances...\",\"completed\":$INSTANCE_COUNT,\"total\":$INSTANCE_COUNT}" > "$STATUS_FILE"
        supervisorctl -c /etc/supervisor/supervisord.conf update || echo "Warning: supervisorctl update failed"
    else
        echo "No instances to restore"
    fi
fi

# Final status
echo '{"restoring":false,"current":"Done","completed":0,"total":0}' > "$STATUS_FILE"
echo "Restore complete"
