#!/bin/sh

# list-instances.sh - List all PocketBase instances
# Usage: list-instances.sh

MANIFEST_FILE="/var/multipb/instances.json"

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "No instances configured yet"
    exit 0
fi

echo "PocketBase Instances:"
echo "===================="

if command -v jq >/dev/null 2>&1; then
    # Pretty print with jq
    jq -r 'to_entries[] | "\(.key)\t Port: \(.value.port)\t Status: \(.value.status // "unknown")\t Created: \(.value.created // "N/A")"' "$MANIFEST_FILE" | column -t -s $'\t'
else
    # Fallback: basic parsing
    cat "$MANIFEST_FILE" | grep -o '"[^"]*"' | sed 'N;s/\n/ /'
fi

echo ""
echo "Total: $(grep -o '"' "$MANIFEST_FILE" | wc -l | awk '{print int($1/2)}')"
