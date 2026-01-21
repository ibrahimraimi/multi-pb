#!/bin/sh
set -e

# import-instance.sh - Import a PocketBase instance from a ZIP backup
# Usage: import-instance.sh <zip_path> <new_name> [port]

ZIP_PATH="$1"
INSTANCE_NAME="$2"
CUSTOM_PORT="$3"

MULTIPB_DATA_DIR="${MULTIPB_DATA_DIR:-/var/multipb/data}"

if [ -z "$ZIP_PATH" ] || [ -z "$INSTANCE_NAME" ]; then
    echo "Usage: import-instance.sh <zip_path> <new_name> [port]"
    exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
    echo "Error: Backup file not found: $ZIP_PATH"
    exit 1
fi

# Sanitize name
INSTANCE_NAME=$(echo "$INSTANCE_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
INSTANCE_DIR="$MULTIPB_DATA_DIR/$INSTANCE_NAME"

if [ -d "$INSTANCE_DIR" ]; then
    echo "Error: Instance '$INSTANCE_NAME' already exists"
    exit 1
fi

echo "Importing '$INSTANCE_NAME' from $ZIP_PATH..."

# 1. Create instance
# We use add-instance.sh to handle port allocation and config generation
# But we need to prevent it from creating the admin user or initializing DB if we are overwriting it
if [ -n "$CUSTOM_PORT" ]; then
    /usr/local/bin/add-instance.sh "$INSTANCE_NAME" --port "$CUSTOM_PORT"
else
    /usr/local/bin/add-instance.sh "$INSTANCE_NAME"
fi

# 2. Stop the new instance (it was started by add-instance.sh)
/usr/local/bin/stop-instance.sh "$INSTANCE_NAME"

# 3. Clean the fresh directory (remove empty db)
rm -rf "${INSTANCE_DIR:?}/"*

# 4. Extract backup
echo "Extracting data..."
unzip -q "$ZIP_PATH" -d "$INSTANCE_DIR"

# 5. Fix permissions (if needed, mostly for root)
# chown -R root:root "$INSTANCE_DIR"

# 6. Restart instance
/usr/local/bin/start-instance.sh "$INSTANCE_NAME"

echo "✓ Import complete!"
