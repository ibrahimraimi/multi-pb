#!/bin/sh
set -e

# remove-instance.sh - Stop and remove a PocketBase instance
# Usage: remove-instance.sh <name> [--delete-data]

MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
MANIFEST_FILE="/var/multipb/instances.json"
DELETE_DATA=false

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: remove-instance.sh <name> [--delete-data]"
    exit 1
fi

INSTANCE_NAME="$1"

# Check for --delete-data flag
if [ "$2" = "--delete-data" ]; then
    DELETE_DATA=true
fi

echo "Removing instance: $INSTANCE_NAME"

# Check if instance exists in manifest
if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' not found"
    exit 1
fi

# Stop supervisord process
if command -v supervisorctl >/dev/null 2>&1 && [ -S /var/run/supervisor.sock ]; then
    supervisorctl -c /etc/supervisor/supervisord.conf -s unix:///var/run/supervisor.sock stop "pb-${INSTANCE_NAME}" >/dev/null 2>&1 || true
    supervisorctl -c /etc/supervisor/supervisord.conf -s unix:///var/run/supervisor.sock remove "pb-${INSTANCE_NAME}" >/dev/null 2>&1 || true
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

# Handle data directory deletion
INSTANCE_DIR="$MULTIPB_DATA_DIR/$INSTANCE_NAME"
if [ "$DELETE_DATA" = true ]; then
    if [ -d "$INSTANCE_DIR" ]; then
        rm -rf "$INSTANCE_DIR"
        echo "Data directory deleted: $INSTANCE_DIR"
    fi
else
    if [ -d "$INSTANCE_DIR" ]; then
        echo "Data directory preserved: $INSTANCE_DIR"
        echo "To delete it later: rm -rf $INSTANCE_DIR"
    fi
fi

# Regenerate Caddy config
/usr/local/bin/reload-proxy.sh

echo ""
echo "✓ Instance '$INSTANCE_NAME' removed"
