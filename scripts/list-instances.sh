#!/bin/sh

# list-instances.sh - List all PocketBase instances
# Usage: list-instances.sh

MANIFEST_FILE="/var/multipb/data/instances.json"

if [ ! -f "$MANIFEST_FILE" ]; then
    echo "No instances configured yet"
    exit 0
fi

echo "PocketBase Instances:"
echo "===================="

if command -v jq >/dev/null 2>&1; then
    # Pretty print with jq
    if command -v column >/dev/null 2>&1; then
        jq -r 'to_entries[] | "\(.key)\t Port: \(.value.port)\t Status: \(.value.status // "unknown")\t Created: \(.value.created // "N/A")"' "$MANIFEST_FILE" | column -t -s $'\t'
    else
        # Fallback: format without column command
        jq -r 'to_entries[] | "\(.key)\tPort: \(.value.port)\tStatus: \(.value.status // "unknown")\tCreated: \(.value.created // "N/A")"' "$MANIFEST_FILE" | awk -F'\t' '{printf "%-20s %-15s %-15s %s\n", $1, $2, $3, $4}'
    fi
else
    # Fallback: basic parsing
    cat "$MANIFEST_FILE" | grep -o '"[^"]*"' | sed 'N;s/\n/ /'
fi

echo ""
echo "Total: $(grep -o '"' "$MANIFEST_FILE" | wc -l | awk '{print int($1/2)}')"
