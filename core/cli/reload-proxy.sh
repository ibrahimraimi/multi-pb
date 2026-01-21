#!/bin/sh
set -e

# reload-proxy.sh - Regenerate Caddyfile from manifest and reload Caddy
# Usage: reload-proxy.sh

MANIFEST_FILE="/var/multipb/data/instances.json"
CADDYFILE="/etc/caddy/Caddyfile"
MULTIPB_PORT="${MULTIPB_PORT:-25983}"

echo "Regenerating Caddy configuration..."

# Start building Caddyfile
echo "Building Caddyfile with DOMAIN=${MULTIPB_DOMAIN} PORT=${MULTIPB_PORT}"

if [ -n "$MULTIPB_DOMAIN" ]; then
    # HTTPS Mode (Domain provided)
    cat > "$CADDYFILE" << EOF
{
    admin localhost:2019
    log {
        output stdout
        format json
    }
}

${MULTIPB_DOMAIN} {
EOF
else
    # HTTP Mode (Port only)
    cat > "$CADDYFILE" << EOF
{
    auto_https off
    admin localhost:2019
    log {
        output stdout
        format json
    }
}

:${MULTIPB_PORT} {
EOF
fi

cat >> "$CADDYFILE" << 'EOF'
    # Health check endpoint
    handle /_health {
        respond "OK" 200
    }

    # List instances endpoint
    handle /_instances {
        respond `{"status":"ok","instances":${INSTANCE_LIST}}` 200
    }

    # API endpoints
    handle /api/* {
        reverse_proxy 127.0.0.1:3001
    }

EOF

# Add dashboard routes only if dashboard exists
if [ -d "/var/www/dashboard" ] && [ -f "/var/www/dashboard/index.html" ]; then
    cat >> "$CADDYFILE" << 'EOF'
    # Dashboard - serve static files with SPA fallback
    handle /dashboard* {
        root * /var/www
        try_files {path} {path}/ /dashboard/index.html
        file_server
    }

    # Redirect root to dashboard
    handle / {
        redir /dashboard/ 301
    }
EOF
else
    cat >> "$CADDYFILE" << 'EOF'
    # Root endpoint (dashboard not installed)
    handle / {
        respond "Multi-PB - PocketBase Multi-Instance Manager (CLI-only mode)" 200
    }
EOF
fi

cat >> "$CADDYFILE" << 'EOF'

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

# Replace variables
sed -i "s|\${INSTANCE_LIST}|$INSTANCE_LIST|g" "$CADDYFILE"

echo "Caddyfile generated at: $CADDYFILE"

# Reload Caddy if running
# We use pidof as it's more reliable than pgrep in some alpine/container environments
if pidof caddy > /dev/null || pgrep caddy > /dev/null; then
    if command -v caddy >/dev/null 2>&1; then
        echo "Reloading Caddy..."
        if ! caddy reload --config "$CADDYFILE" --adapter caddyfile 2>&1; then
            echo "Warning: Caddy reload encountered an issue. Check logs."
            # Fallback: try to restart if reload fails and we are inside supervisor? 
            # No, keep it simple.
        else
            echo "✓ Caddy configuration reloaded"
        fi
    fi
else
    echo "Note: Caddy not running (pidof failed), will use config on next start"
fi
