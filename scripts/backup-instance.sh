#!/bin/sh
set -e

# backup-instance.sh - Create a backup of a PocketBase instance
# Usage: backup-instance.sh <name>

MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"
BACKUP_DIR="/var/multipb/backups"
MANIFEST_FILE="/var/multipb/data/instances.json"

if [ $# -lt 1 ]; then
    echo "Usage: backup-instance.sh <name>"
    exit 1
fi

INSTANCE_NAME="$1"

echo "Creating backup for instance: $INSTANCE_NAME"

# Check if instance exists
if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' not found"
    exit 1
fi

# Check if instance directory exists
INSTANCE_DIR="$MULTIPB_DATA_DIR/$INSTANCE_NAME"
if [ ! -d "$INSTANCE_DIR" ]; then
    echo "Error: Instance directory '$INSTANCE_DIR' not found"
    exit 1
fi

# Create backup directory for this instance
INSTANCE_BACKUP_DIR="$BACKUP_DIR/$INSTANCE_NAME"
mkdir -p "$INSTANCE_BACKUP_DIR"

# Generate timestamp-based backup name
TIMESTAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
BACKUP_NAME="backup-${TIMESTAMP}.zip"
BACKUP_PATH="$INSTANCE_BACKUP_DIR/$BACKUP_NAME"

# Create backup (zip the instance directory)
echo "Backing up instance data..."
if cd "$INSTANCE_DIR" && zip -r "$BACKUP_PATH" . >/dev/null 2>&1; then
    # Get backup size
    if command -v stat >/dev/null 2>&1; then
        if stat -f%z "$BACKUP_PATH" >/dev/null 2>&1; then
            # macOS/BSD stat
            SIZE=$(stat -f%z "$BACKUP_PATH")
        else
            # Linux stat
            SIZE=$(stat -c%s "$BACKUP_PATH")
        fi
    else
        SIZE=$(ls -l "$BACKUP_PATH" | awk '{print $5}')
    fi
    
    # Format size
    if [ "$SIZE" -lt 1024 ]; then
        SIZE_STR="${SIZE}B"
    elif [ "$SIZE" -lt 1048576 ]; then
        SIZE_STR="$((SIZE / 1024))KB"
    else
        SIZE_STR="$((SIZE / 1048576))MB"
    fi
    
    echo "✓ Backup created: $BACKUP_NAME ($SIZE_STR)"
    echo "  Location: $BACKUP_PATH"
else
    echo "Error: Failed to create backup"
    exit 1
fi
