#!/bin/bash
set -e

CONFIG_FILE="/var/multipb/data/config.json"
TOKEN="$1"

if [ $# -lt 1 ]; then
    echo "Usage: set-admin-token.sh <token>"
    echo "  Sets the admin token (authorization key) for Multi-PB API."
    echo "  Set to \"\" (empty string) to disable authorization."
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "{}" > "$CONFIG_FILE"
fi

# Use jq to update or remove the adminToken field safely
tmp=$(mktemp)
if [ -z "$TOKEN" ]; then
    # Empty token: remove the field to disable auth
    jq 'del(.adminToken)' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "Admin token removed. API is now public."
else
    # Set the token
    jq --arg token "$TOKEN" '.adminToken = $token' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
    echo "Admin token updated."
fi

# Make sure permissions are correct
chown root:root "$CONFIG_FILE" 2>/dev/null || true
chmod 644 "$CONFIG_FILE"
