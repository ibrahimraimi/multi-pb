#!/bin/sh
set -e

# stop-instance.sh - Stop a running PocketBase instance
# Usage: stop-instance.sh <name>

MANIFEST_FILE="/var/multipb/instances.json"

if [ $# -lt 1 ]; then
    echo "Usage: stop-instance.sh <name>"
    exit 1
fi

INSTANCE_NAME="$1"

echo "Stopping instance: $INSTANCE_NAME"

# Check if instance exists
if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' not found"
    exit 1
fi

# Stop via supervisord
if command -v supervisorctl >/dev/null 2>&1 && [ -S /var/run/supervisor.sock ]; then
    if supervisorctl -c /etc/supervisor/supervisord.conf -s unix:///var/run/supervisor.sock stop "pb-${INSTANCE_NAME}" >/dev/null 2>&1; then
        echo "✓ Instance '$INSTANCE_NAME' stopped"
    else
        echo "Warning: Could not stop instance via supervisord (may already be stopped)"
    fi
else
    echo "Warning: supervisord not available (instance may already be stopped)"
fi

# Update status in manifest
if command -v jq >/dev/null 2>&1; then
    TMP_FILE=$(mktemp)
    jq --arg name "$INSTANCE_NAME" '.[$name].status = "stopped"' "$MANIFEST_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$MANIFEST_FILE"
fi
