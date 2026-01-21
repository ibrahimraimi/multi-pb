#!/bin/sh

# list-backups.sh - List backups for a PocketBase instance
# Usage: list-backups.sh [name]

BACKUP_DIR="/var/multipb/backups"
MANIFEST_FILE="/var/multipb/data/instances.json"

if [ $# -ge 1 ]; then
    # List backups for specific instance
    INSTANCE_NAME="$1"
    
    # Check if instance exists
    if [ ! -f "$MANIFEST_FILE" ] || ! grep -q "\"$INSTANCE_NAME\"" "$MANIFEST_FILE"; then
        echo "Error: Instance '$INSTANCE_NAME' not found"
        exit 1
    fi
    
    INSTANCE_BACKUP_DIR="$BACKUP_DIR/$INSTANCE_NAME"
    
    if [ ! -d "$INSTANCE_BACKUP_DIR" ]; then
        echo "No backups found for instance '$INSTANCE_NAME'"
        exit 0
    fi
    
    echo "Backups for instance '$INSTANCE_NAME':"
    echo "======================================"
    
    # List backups with details
    if command -v ls >/dev/null 2>&1 && [ -n "$(ls -A "$INSTANCE_BACKUP_DIR" 2>/dev/null)" ]; then
        for backup in "$INSTANCE_BACKUP_DIR"/*.zip; do
            if [ -f "$backup" ]; then
                BACKUP_NAME=$(basename "$backup")
                
                # Get file size
                if command -v stat >/dev/null 2>&1; then
                    if stat -f%z "$backup" >/dev/null 2>&1; then
                        SIZE=$(stat -f%z "$backup")
                    else
                        SIZE=$(stat -c%s "$backup")
                    fi
                else
                    SIZE=$(ls -l "$backup" | awk '{print $5}')
                fi
                
                # Format size
                if [ "$SIZE" -lt 1024 ]; then
                    SIZE_STR="${SIZE}B"
                elif [ "$SIZE" -lt 1048576 ]; then
                    SIZE_STR="$((SIZE / 1024))KB"
                else
                    SIZE_STR="$((SIZE / 1048576))MB"
                fi
                
                # Get modification time
                if command -v stat >/dev/null 2>&1; then
                    if stat -f%Sm "$backup" >/dev/null 2>&1; then
                        MTIME=$(stat -f%Sm "$backup")
                    else
                        MTIME=$(stat -c%y "$backup" | cut -d' ' -f1-2)
                    fi
                else
                    MTIME=$(ls -l "$backup" | awk '{print $6, $7, $8}')
                fi
                
                echo "$BACKUP_NAME  $SIZE_STR  $MTIME"
            fi
        done | sort -r
    else
        echo "No backups found"
    fi
else
    # List all backups for all instances
    echo "All backups:"
    echo "============"
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo "No backups found"
        exit 0
    fi
    
    for instance_dir in "$BACKUP_DIR"/*; do
        if [ -d "$instance_dir" ]; then
            INSTANCE_NAME=$(basename "$instance_dir")
            BACKUP_COUNT=$(find "$instance_dir" -name "*.zip" -type f 2>/dev/null | wc -l | tr -d ' ')
            
            if [ "$BACKUP_COUNT" -gt 0 ]; then
                echo ""
                echo "Instance: $INSTANCE_NAME ($BACKUP_COUNT backup$( [ "$BACKUP_COUNT" -ne 1 ] && echo 's' ))"
                echo "----------------------------------------"
                
                for backup in "$instance_dir"/*.zip; do
                    if [ -f "$backup" ]; then
                        BACKUP_NAME=$(basename "$backup")
                        
                        # Get file size
                        if command -v stat >/dev/null 2>&1; then
                            if stat -f%z "$backup" >/dev/null 2>&1; then
                                SIZE=$(stat -f%z "$backup")
                            else
                                SIZE=$(stat -c%s "$backup")
                            fi
                        else
                            SIZE=$(ls -l "$backup" | awk '{print $5}')
                        fi
                        
                        # Format size
                        if [ "$SIZE" -lt 1024 ]; then
                            SIZE_STR="${SIZE}B"
                        elif [ "$SIZE" -lt 1048576 ]; then
                            SIZE_STR="$((SIZE / 1024))KB"
                        else
                            SIZE_STR="$((SIZE / 1048576))MB"
                        fi
                        
                        echo "  $BACKUP_NAME  $SIZE_STR"
                    fi
                done | sort -r
            fi
        fi
    done
fi
