#!/bin/sh
set -e

# remove-instance.sh - Stop and remove a PocketBase instance
# Usage: remove-instance.sh <name>

MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
MANIFEST_FILE="/var/multipb/instances.json"

if [ $# -lt 1 ]; then
    echo "Usage: remove-instance.sh <name>"
    exit 1
fi

INSTANCE_NAME="$1"

echo "Removing instance: $INSTANCE_NAME"

# Check if instance exists in manifest
if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' not found"
    exit 1
fi

# Stop supervisord process
if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl stop "pb-${INSTANCE_NAME}" || true
    supervisorctl remove "pb-${INSTANCE_NAME}" || true
    echo "Instance stopped via supervisord"
fi

# Remove supervisord config
SUPERVISOR_CONF="/etc/supervisor/conf.d/${INSTANCE_NAME}.conf"
if [ -f "$SUPERVISOR_CONF" ]; then
    rm "$SUPERVISOR_CONF"
    echo "Removed supervisord config"
fi

# Remove from manifest using jq if available
if command -v jq >/dev/null 2>&1; then
    TMP_FILE=$(mktemp)
    jq --arg name "$INSTANCE_NAME" 'del(.[$name])' "$MANIFEST_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$MANIFEST_FILE"
else
    # Fallback: remove line with instance name (basic approach)
    sed -i "/\"$INSTANCE_NAME\"/d" "$MANIFEST_FILE"
fi

echo "Removed from manifest"

# Optionally remove data directory (ask for confirmation)
read -p "Delete data directory? (y/N): " confirm
case "$confirm" in
    [Yy]*)
        INSTANCE_DIR="$MULTIPB_DATA_DIR/$INSTANCE_NAME"
        if [ -d "$INSTANCE_DIR" ]; then
            rm -rf "$INSTANCE_DIR"
            echo "Data directory deleted: $INSTANCE_DIR"
        fi
        ;;
    *)
        echo "Data directory preserved: $MULTIPB_DATA_DIR/$INSTANCE_NAME"
        ;;
esac

# Regenerate Caddy config
/usr/local/bin/reload-proxy.sh

echo ""
echo "✓ Instance '$INSTANCE_NAME' removed"
