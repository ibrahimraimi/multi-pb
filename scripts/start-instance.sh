#!/bin/sh
set -e

# start-instance.sh - Start a stopped PocketBase instance
# Usage: start-instance.sh <name>

MANIFEST_FILE="/var/multipb/instances.json"

if [ $# -lt 1 ]; then
    echo "Usage: start-instance.sh <name>"
    exit 1
fi

INSTANCE_NAME="$1"

echo "Starting instance: $INSTANCE_NAME"

# Check if instance exists
if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' not found"
    exit 1
fi

# Start via supervisord
if command -v supervisorctl >/dev/null 2>&1; then
    supervisorctl start "pb-${INSTANCE_NAME}"
    echo "✓ Instance '$INSTANCE_NAME' started"
else
    echo "Error: supervisorctl not available"
    exit 1
fi

# Update status in manifest
if command -v jq >/dev/null 2>&1; then
    TMP_FILE=$(mktemp)
    jq --arg name "$INSTANCE_NAME" '.[$name].status = "running"' "$MANIFEST_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$MANIFEST_FILE"
fi
