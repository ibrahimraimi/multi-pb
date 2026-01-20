#!/bin/sh

# view-logs.sh - View logs for a PocketBase instance
# Usage: view-logs.sh <name> [--stderr] [--tail <lines>] [--follow]

MANIFEST_FILE="/var/multipb/data/instances.json"
LOG_DIR="/var/log/multipb"

if [ $# -lt 1 ]; then
    echo "Usage: view-logs.sh <name> [--stderr] [--tail <lines>] [--follow]"
    echo ""
    echo "Options:"
    echo "  --stderr    View error log instead of stdout log"
    echo "  --tail N    Show last N lines (default: 50)"
    echo "  --follow    Follow log output (like tail -f)"
    exit 1
fi

INSTANCE_NAME="$1"
SHOW_STDERR=false
TAIL_LINES=50
FOLLOW=false

# Parse arguments
shift
while [ $# -gt 0 ]; do
    case "$1" in
        --stderr)
            SHOW_STDERR=true
            shift
            ;;
        --tail)
            TAIL_LINES="$2"
            shift 2
            ;;
        --follow)
            FOLLOW=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if instance exists
if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
    echo "Error: Instance '$INSTANCE_NAME' not found"
    exit 1
fi

# Determine log file
if [ "$SHOW_STDERR" = true ]; then
    LOG_FILE="$LOG_DIR/${INSTANCE_NAME}.err.log"
    LOG_TYPE="error"
else
    LOG_FILE="$LOG_DIR/${INSTANCE_NAME}.log"
    LOG_TYPE="stdout"
fi

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found: $LOG_FILE"
    echo "Instance may not have generated any logs yet."
    exit 1
fi

# Display logs
if [ "$FOLLOW" = true ]; then
    echo "Following $LOG_TYPE log for instance '$INSTANCE_NAME' (Ctrl+C to stop)..."
    echo "=========================================="
    tail -f "$LOG_FILE"
else
    echo "Last $TAIL_LINES lines of $LOG_TYPE log for instance '$INSTANCE_NAME':"
    echo "=========================================="
    tail -n "$TAIL_LINES" "$LOG_FILE"
fi
