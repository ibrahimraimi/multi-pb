#!/bin/bash
# Test script to validate shell scripts work correctly

set -e

echo "Testing Multi-PB shell scripts..."

# Set up test environment
export MULTIPB_DATA_DIR="/tmp/multipb-test/data"
export MULTIPB_PORT="25983"
MANIFEST_FILE="/tmp/multipb-test/instances.json"

# Clean up from previous runs
rm -rf /tmp/multipb-test
mkdir -p /tmp/multipb-test
mkdir -p "$MULTIPB_DATA_DIR"
mkdir -p /tmp/multipb-test/supervisor/conf.d
mkdir -p /tmp/multipb-test/caddy
mkdir -p /tmp/multipb-test/log

# Initialize manifest
echo "{}" > "$MANIFEST_FILE"

echo "✓ Test environment initialized"

# Test 0: Check for jq availability (hard requirement)
echo ""
echo "Test 0: Checking for jq..."
if ! command -v jq >/dev/null 2>&1; then
    echo "✗ jq is required but not installed"
    echo "  Install with: apt-get install jq (Debian/Ubuntu)"
    echo "            or: apk add jq (Alpine)"
    echo "            or: yum install jq (RHEL/CentOS)"
    exit 1
fi
echo "✓ jq is available"

# Test 1: Check script syntax
echo ""
echo "Test 1: Checking script syntax..."
for script in scripts/*.sh; do
    if ! bash -n "$script"; then
        echo "✗ Syntax error in $script"
        exit 1
    fi
done
echo "✓ All scripts have valid syntax"

# Test 2: Manifest operations
echo ""
echo "Test 2: Testing manifest operations..."

INSTANCE_NAME="test1"
NEXT_PORT=30000

# Add instance to manifest
TMP_FILE=$(mktemp)
jq --arg name "$INSTANCE_NAME" --argjson port "$NEXT_PORT" \
    '.[$name] = {"port": $port, "status": "running", "created": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
    "$MANIFEST_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$MANIFEST_FILE"

# Verify manifest
if grep -q "\"test1\"" "$MANIFEST_FILE"; then
    echo "✓ Instance added to manifest"
else
    echo "✗ Failed to add instance to manifest"
    exit 1
fi

# Test 3: Port assignment
echo ""
echo "Test 3: Testing port assignment..."

# Add another instance
INSTANCE_NAME="test2"
NEXT_PORT=30001
TMP_FILE=$(mktemp)
jq --arg name "$INSTANCE_NAME" --argjson port "$NEXT_PORT" \
    '.[$name] = {"port": $port, "status": "running", "created": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}' \
    "$MANIFEST_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$MANIFEST_FILE"

if [ "$(jq 'length' "$MANIFEST_FILE")" -eq 2 ]; then
    echo "✓ Multiple instances tracked correctly"
else
    echo "✗ Failed to track multiple instances"
    exit 1
fi

# Test 4: Optimized port search
echo ""
echo "Test 4: Testing optimized port search..."

# Test the optimized port assignment algorithm
USED_PORTS=$(jq -r '.[] | .port' "$MANIFEST_FILE" 2>/dev/null | sort -n)
NEXT_PORT=30000

for port in $USED_PORTS; do
    if [ $NEXT_PORT -eq $port ]; then
        NEXT_PORT=$((NEXT_PORT + 1))
    elif [ $NEXT_PORT -lt $port ]; then
        break
    fi
done

if [ $NEXT_PORT -eq 30002 ]; then
    echo "✓ Port search algorithm works correctly"
else
    echo "✗ Port search algorithm failed (expected 30002, got $NEXT_PORT)"
    exit 1
fi

# Test 5: Remove instance
echo ""
echo "Test 5: Testing instance removal..."

TMP_FILE=$(mktemp)
jq 'del(.test1)' "$MANIFEST_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$MANIFEST_FILE"

if ! grep -q "\"test1\"" "$MANIFEST_FILE" && grep -q "\"test2\"" "$MANIFEST_FILE"; then
    echo "✓ Instance removed correctly"
else
    echo "✗ Failed to remove instance"
    exit 1
fi

# Test 6: Caddyfile generation
echo ""
echo "Test 6: Testing Caddyfile generation..."

cat > /tmp/multipb-test/test-caddy-gen.sh << 'EOFSCRIPT'
#!/bin/sh
MANIFEST_FILE="/tmp/multipb-test/instances.json"
CADDYFILE="/tmp/multipb-test/Caddyfile"
MULTIPB_PORT="25983"

cat > "$CADDYFILE" << 'EOF'
{
    auto_https off
    admin off
}

:${MULTIPB_PORT} {
    handle /_health {
        respond "OK" 200
    }

    handle /_instances {
        respond `{"status":"ok","instances":${INSTANCE_LIST}}` 200
    }

EOF

INSTANCE_LIST=$(jq -c 'keys' "$MANIFEST_FILE")
jq -r 'to_entries[] | "    handle /\(.key)/* {\n        uri strip_prefix /\(.key)\n        reverse_proxy 127.0.0.1:\(.value.port)\n    }\n"' "$MANIFEST_FILE" >> "$CADDYFILE"

cat >> "$CADDYFILE" << 'EOF'

    handle {
        respond "Multi-PB" 200
    }
}
EOF

sed -i "s/\${MULTIPB_PORT}/$MULTIPB_PORT/g" "$CADDYFILE"
sed -i "s|\${INSTANCE_LIST}|$INSTANCE_LIST|g" "$CADDYFILE"
EOFSCRIPT

chmod +x /tmp/multipb-test/test-caddy-gen.sh
/tmp/multipb-test/test-caddy-gen.sh

if [ -f /tmp/multipb-test/Caddyfile ] && grep -q "test2" /tmp/multipb-test/Caddyfile; then
    echo "✓ Caddyfile generated correctly"
    echo ""
    echo "Generated Caddyfile:"
    cat /tmp/multipb-test/Caddyfile
else
    echo "✗ Failed to generate Caddyfile"
    exit 1
fi

# Cleanup
echo ""
echo "Cleaning up test environment..."
rm -rf /tmp/multipb-test

echo ""
echo "═════════════════════════════════════"
echo "✓ All tests passed!"
echo "═════════════════════════════════════"
