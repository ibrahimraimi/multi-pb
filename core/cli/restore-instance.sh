#!/bin/sh
set -e

# restore-instance.sh - Restore a PocketBase instance from a backup
# Usage: restore-instance.sh <name> <backup-name>

MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
BACKUP_DIR="/var/multipb/backups"
MANIFEST_FILE="/var/multipb/data/instances.json"

if [ $# -lt 2 ]; then
    echo "Usage: restore-instance.sh <name> <backup-name>"
    echo ""
    echo "Example:"
    echo "  restore-instance.sh myapp backup-2024-01-15T10-30-00Z.zip"
    exit 1
fi

INSTANCE_NAME="$1"
BACKUP_NAME="$2"

echo "Restoring instance '$INSTANCE_NAME' from backup '$BACKUP_NAME'"

# Check if instance exists
if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' not found"
    exit 1
fi

# Check if backup exists
BACKUP_PATH="$BACKUP_DIR/$INSTANCE_NAME/$BACKUP_NAME"
if [ ! -f "$BACKUP_PATH" ]; then
    echo "Error: Backup file '$BACKUP_PATH' not found"
    echo ""
    echo "Available backups for '$INSTANCE_NAME':"
    if [ -d "$BACKUP_DIR/$INSTANCE_NAME" ]; then
        ls -1 "$BACKUP_DIR/$INSTANCE_NAME"/*.zip 2>/dev/null | xargs -n1 basename || echo "  (none)"
    else
        echo "  (none)"
    fi
    exit 1
fi

# Stop instance first
echo "Stopping instance..."
if command -v supervisorctl >/dev/null 2>&1 && [ -S /var/run/supervisor.sock ]; then
    supervisorctl -c /etc/supervisor/supervisord.conf -s unix:///var/run/supervisor.sock stop "pb-${INSTANCE_NAME}" >/dev/null 2>&1 || true
fi

# Create temporary backup of current data
INSTANCE_DIR="$MULTIPB_DATA_DIR/$INSTANCE_NAME"
TEMP_BACKUP_DIR="${INSTANCE_DIR}_restore_backup_$(date +%s)"

if [ -d "$INSTANCE_DIR" ]; then
    echo "Backing up current data..."
    mv "$INSTANCE_DIR" "$TEMP_BACKUP_DIR"
fi

# Create fresh instance directory
mkdir -p "$INSTANCE_DIR"

# Extract backup
echo "Extracting backup..."
if cd "$INSTANCE_DIR" && unzip -o "$BACKUP_PATH" >/dev/null 2>&1; then
    echo "✓ Backup extracted successfully"
else
    echo "Error: Failed to extract backup"
    
    # Try to restore old data
    if [ -d "$TEMP_BACKUP_DIR" ]; then
        echo "Restoring previous data..."
        rm -rf "$INSTANCE_DIR"
        mv "$TEMP_BACKUP_DIR" "$INSTANCE_DIR"
    fi
    
    # Start instance
    if command -v supervisorctl >/dev/null 2>&1 && [ -S /var/run/supervisor.sock ]; then
        supervisorctl -c /etc/supervisor/supervisord.conf -s unix:///var/run/supervisor.sock start "pb-${INSTANCE_NAME}" >/dev/null 2>&1 || true
    fi
    
    exit 1
fi

# Start instance
echo "Starting instance..."
if command -v supervisorctl >/dev/null 2>&1 && [ -S /var/run/supervisor.sock ]; then
    supervisorctl -c /etc/supervisor/supervisord.conf -s unix:///var/run/supervisor.sock start "pb-${INSTANCE_NAME}" >/dev/null 2>&1 || true
fi

# Update status in manifest
if command -v jq >/dev/null 2>&1; then
    TMP_FILE=$(mktemp)
    jq --arg name "$INSTANCE_NAME" '.[$name].status = "running"' "$MANIFEST_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$MANIFEST_FILE"
fi

# Clean up temporary backup after successful restore
if [ -d "$TEMP_BACKUP_DIR" ]; then
    echo "Cleaning up temporary backup..."
    rm -rf "$TEMP_BACKUP_DIR"
fi

echo ""
echo "✓ Instance '$INSTANCE_NAME' restored from backup '$BACKUP_NAME'"
