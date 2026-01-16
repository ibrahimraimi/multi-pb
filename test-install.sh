#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TEST_DIR="/tmp/multipb-test-$(date +%s)"
TEST_PORT="25999"
CONTAINER_NAME="multipb-test"

echo "Creating test directory: $TEST_DIR"
mkdir -p "$TEST_DIR"

# Copy project files to test dir (simulating a clone)
# Excluding git, node_modules, and existing data
rsync -av --exclude '.git' --exclude 'node_modules' --exclude 'multipb-data' \
    --exclude 'dashboard/node_modules' --exclude '.DS_Store' \
    ./ "$TEST_DIR/"

cd "$TEST_DIR"

echo "Running install.sh in non-interactive mode..."
./install.sh --non-interactive \
    --port "$TEST_PORT" \
    --data-dir "./test-data" \
    --name "$CONTAINER_NAME"

echo "Waiting for health check..."
MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
    if curl -s -f "http://localhost:$TEST_PORT/_health" >/dev/null; then
        echo -e "${GREEN}✓ Health check passed!${NC}"
        
        # Verify dashboard loads
        if curl -s -f "http://localhost:$TEST_PORT/dashboard/" >/dev/null; then
             echo -e "${GREEN}✓ Dashboard reachable!${NC}"
        else
             echo -e "${RED}✗ Dashboard unreachable${NC}"
             exit 1
        fi
        
        # Cleanup
        echo "Cleaning up..."
        docker compose down
        rm -rf "$TEST_DIR"
        echo -e "${GREEN}Test completed successfully!${NC}"
        exit 0
    fi
    echo "Waiting... ($i/$MAX_RETRIES)"
    sleep 2
done

echo -e "${RED}Test failed: Service did not become healthy${NC}"
docker logs "$CONTAINER_NAME"
docker compose down
exit 1
