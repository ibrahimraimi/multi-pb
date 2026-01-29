#!/bin/sh
set -e

# manage-versions.sh - Manage PocketBase versions
# Usage: manage-versions.sh <command> [args]

VERSIONS_DIR="/var/multipb/data/versions"
MANIFEST_FILE="/var/multipb/data/instances.json"

# Detect architecture
detect_arch() {
    ARCH=$(uname -m)
    if [ "$ARCH" = "x86_64" ]; then
        echo "amd64"
    elif [ "$ARCH" = "aarch64" ]; then
        echo "arm64"
    else
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
    fi
}

# Get latest version from GitHub
get_latest_version() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "" >&2
        return 1
    fi
    if command -v jq >/dev/null 2>&1; then
        curl -s --max-time 10 https://api.github.com/repos/pocketbase/pocketbase/releases/latest 2>/dev/null | \
            jq -r '.tag_name // ""' | \
            sed 's/^v//' || echo ""
    else
        curl -s --max-time 10 https://api.github.com/repos/pocketbase/pocketbase/releases/latest 2>/dev/null | \
            grep -o '"tag_name": "[^"]*"' | \
            sed 's/"tag_name": "v\?//' | \
            sed 's/"$//' || echo ""
    fi
}

# List all available versions (from GitHub releases)
list_available_versions() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "" >&2
        return 1
    fi
    if command -v jq >/dev/null 2>&1; then
        curl -s --max-time 10 https://api.github.com/repos/pocketbase/pocketbase/releases 2>/dev/null | \
            jq -r '.[].tag_name' | \
            sed 's/^v//' | \
            head -20 || echo ""
    else
        curl -s --max-time 10 https://api.github.com/repos/pocketbase/pocketbase/releases 2>/dev/null | \
            grep -o '"tag_name": "[^"]*"' | \
            sed 's/"tag_name": "v\?//' | \
            sed 's/"$//' | \
            head -20 || echo ""
    fi
}

# Download a specific version
download_version() {
    local version=$1
    if [ -z "$version" ]; then
        echo "Error: Version required" >&2
        exit 1
    fi
    
    PB_ARCH=$(detect_arch)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to detect architecture" >&2
        exit 1
    fi
    
    VERSION_DIR="$VERSIONS_DIR/$version"
    BINARY_PATH="$VERSION_DIR/pocketbase"
    
    # Check if already downloaded
    if [ -f "$BINARY_PATH" ] && [ -x "$BINARY_PATH" ]; then
        echo "Version $version already downloaded" >&2
        echo "$BINARY_PATH"  # Output path to stdout for caller
        return 0
    fi
    
    echo "Downloading PocketBase v$version..." >&2
    mkdir -p "$VERSION_DIR" || {
        echo "Error: Failed to create version directory" >&2
        exit 1
    }
    
    # Download and extract
    DOWNLOAD_URL="https://github.com/pocketbase/pocketbase/releases/download/v${version}/pocketbase_${version}_linux_${PB_ARCH}.zip"
    
    if ! curl -fsSL --max-time 300 "$DOWNLOAD_URL" -o "/tmp/pocketbase_${version}.zip" 2>&1; then
        echo "Error: Failed to download version $version from $DOWNLOAD_URL" >&2
        echo "Please verify the version exists and is available for your architecture ($PB_ARCH)" >&2
        rm -rf "$VERSION_DIR"
        rm -f "/tmp/pocketbase_${version}.zip"
        exit 1
    fi
    
    cd "$VERSION_DIR" || {
        echo "Error: Failed to change to version directory" >&2
        rm -f "/tmp/pocketbase_${version}.zip"
        exit 1
    }
    
    if ! unzip -q "/tmp/pocketbase_${version}.zip" 2>&1; then
        echo "Error: Failed to extract PocketBase archive" >&2
        rm -rf "$VERSION_DIR"
        rm -f "/tmp/pocketbase_${version}.zip"
        exit 1
    fi
    
    if [ ! -f "$BINARY_PATH" ]; then
        echo "Error: PocketBase binary not found after extraction" >&2
        rm -rf "$VERSION_DIR"
        rm -f "/tmp/pocketbase_${version}.zip"
        exit 1
    fi
    
    chmod +x "$BINARY_PATH" || {
        echo "Error: Failed to make binary executable" >&2
        exit 1
    }
    
    rm -f "/tmp/pocketbase_${version}.zip"
    
    echo "Version $version downloaded successfully" >&2
    echo "$BINARY_PATH"  # Output path to stdout for caller
}

# List installed versions
list_installed_versions() {
    if [ ! -d "$VERSIONS_DIR" ]; then
        return
    fi
    
    for dir in "$VERSIONS_DIR"/*; do
        if [ -d "$dir" ] && [ -f "$dir/pocketbase" ]; then
            basename "$dir"
        fi
    done | sort -V
}

# Get binary path for a version
get_binary_path() {
    local version=$1
    if [ -z "$version" ]; then
        echo "Error: Version required" >&2
        exit 1
    fi
    
    BINARY_PATH="$VERSIONS_DIR/$version/pocketbase"
    if [ -f "$BINARY_PATH" ] && [ -x "$BINARY_PATH" ]; then
        echo "$BINARY_PATH"
    else
        echo "Error: Version $version not installed" >&2
        exit 1
    fi
}

# Delete a version
delete_version() {
    local version=$1
    if [ -z "$version" ]; then
        echo "Error: Version required" >&2
        exit 1
    fi
    
    # Check if any instance is using this version
    if command -v jq >/dev/null 2>&1 && [ -f "$MANIFEST_FILE" ]; then
        INSTANCES_USING=$(jq -r --arg v "$version" '.[] | select(.version == $v) | .name' "$MANIFEST_FILE" 2>/dev/null || echo "")
        if [ -n "$INSTANCES_USING" ]; then
            echo "Error: Cannot delete version $version - still in use by instances: $INSTANCES_USING" >&2
            exit 1
        fi
    fi
    
    VERSION_DIR="$VERSIONS_DIR/$version"
    if [ -d "$VERSION_DIR" ]; then
        rm -rf "$VERSION_DIR"
        echo "Version $version deleted"
    else
        echo "Version $version not found"
    fi
}

# Main command handler
case "$1" in
    latest)
        get_latest_version
        ;;
    available)
        list_available_versions
        ;;
    installed)
        list_installed_versions
        ;;
    download)
        if [ -z "$2" ]; then
            echo "Usage: manage-versions.sh download <version>" >&2
            exit 1
        fi
        download_version "$2"
        ;;
    path)
        if [ -z "$2" ]; then
            echo "Usage: manage-versions.sh path <version>" >&2
            exit 1
        fi
        get_binary_path "$2"
        ;;
    delete)
        if [ -z "$2" ]; then
            echo "Usage: manage-versions.sh delete <version>" >&2
            exit 1
        fi
        delete_version "$2"
        ;;
    *)
        echo "Usage: manage-versions.sh <command> [args]" >&2
        echo "Commands:" >&2
        echo "  latest              - Get latest version from GitHub" >&2
        echo "  available           - List available versions from GitHub" >&2
        echo "  installed           - List installed versions" >&2
        echo "  download <version>  - Download a specific version" >&2
        echo "  path <version>      - Get binary path for a version" >&2
        echo "  delete <version>    - Delete a version (if not in use)" >&2
        exit 1
        ;;
esac
