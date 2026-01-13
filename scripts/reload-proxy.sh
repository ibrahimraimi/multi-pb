#!/bin/sh
set -e

# reload-proxy.sh - Regenerate Caddyfile from manifest and reload Caddy
# Usage: reload-proxy.sh

MANIFEST_FILE="/var/multipb/instances.json"
CADDYFILE="/etc/caddy/Caddyfile"
MULTIPB_PORT="${MULTIPB_PORT:-25983}"

echo "Regenerating Caddy configuration..."

# Start building Caddyfile
cat > "$CADDYFILE" << 'EOF'
{
    auto_https off
    admin localhost:2019
}

:${MULTIPB_PORT} {
    # Health check endpoint
    handle /_health {
        respond "OK" 200
    }

    # List instances endpoint
    handle /_instances {
        respond `{"status":"ok","instances":${INSTANCE_LIST}}` 200
    }

EOF

# Add routes for each instance from manifest
if [ -f "$MANIFEST_FILE" ] && command -v jq >/dev/null 2>&1; then
    # Extract instance list for /_instances endpoint
    INSTANCE_LIST=$(jq -c 'keys' "$MANIFEST_FILE" || echo "[]")
    
    # Add route for each instance (handles both /name and /name/*)
    jq -r 'to_entries[] | "    # Instance: \(.key)\n    handle /\(.key)* {\n        uri strip_prefix /\(.key)\n        reverse_proxy 127.0.0.1:\(.value.port)\n    }\n"' "$MANIFEST_FILE" >> "$CADDYFILE"
else
    INSTANCE_LIST="[]"
    echo "    # No instances configured yet" >> "$CADDYFILE"
fi

# Close the server block
cat >> "$CADDYFILE" << 'EOF'

    # Default fallback
    handle {
        respond "Multi-PB - PocketBase Multi-Instance Manager" 200
    }
}
EOF

# Replace ${MULTIPB_PORT} and ${INSTANCE_LIST} in the generated file
sed -i "s/\${MULTIPB_PORT}/$MULTIPB_PORT/g" "$CADDYFILE"
sed -i "s|\${INSTANCE_LIST}|$INSTANCE_LIST|g" "$CADDYFILE"

echo "Caddyfile generated at: $CADDYFILE"

# Reload Caddy if running
if pgrep -x caddy > /dev/null; then
    if command -v caddy >/dev/null 2>&1; then
        # Attempt reload and capture any errors for logging
        if ! caddy reload --config "$CADDYFILE" --adapter caddyfile 2>&1; then
            echo "Warning: Caddy reload encountered an issue. Check logs at /var/log/multipb/caddy.err.log"
        else
            echo "✓ Caddy configuration reloaded"
        fi
    fi
else
    echo "Note: Caddy not running, will use config on next start"
fi
