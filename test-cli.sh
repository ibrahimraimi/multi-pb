#!/bin/bash
set -e

# test-cli.sh - Test all CLI functionality for multi-pb
# Usage: test-cli.sh [container-name]

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CONTAINER_NAME="${1:-multipb}"
TEST_INSTANCE="test-cli-$(date +%s)"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

info() {
    echo -e "${BLUE}→${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

test_command() {
    local description="$1"
    local command="$2"
    local expected_exit="${3:-0}"
    
    info "Testing: $description"
    docker exec "$CONTAINER_NAME" $command >/dev/null 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq "$expected_exit" ]; then
        pass "$description"
        return 0
    else
        fail "$description (exit code: $exit_code, expected: $expected_exit)"
        return 1
    fi
}

test_output() {
    local description="$1"
    local command="$2"
    local expected_pattern="$3"
    
    info "Testing: $description"
    local output=$(docker exec "$CONTAINER_NAME" $command 2>&1)
    local exit_code=$?
    
    # If pattern is empty, just check that command succeeded
    if [ -z "$expected_pattern" ]; then
        if [ $exit_code -eq 0 ]; then
            pass "$description"
            return 0
        else
            fail "$description (command failed with exit code: $exit_code)"
            return 1
        fi
    fi
    
    if echo "$output" | grep -q "$expected_pattern"; then
        pass "$description"
        return 0
    else
        fail "$description (pattern not found: $expected_pattern)"
        echo "  Output: $output"
        return 1
    fi
}

# Check if container is running
info "Checking if container '$CONTAINER_NAME' is running..."
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}Error: Container '$CONTAINER_NAME' is not running${NC}"
    echo "Start it with: docker compose up -d"
    exit 1
fi

echo ""
echo "=========================================="
echo "  Multi-PB CLI Test Suite"
echo "  Container: $CONTAINER_NAME"
echo "  Test Instance: $TEST_INSTANCE"
echo "=========================================="
echo ""

# Test 1: list-instances.sh (should work even with no instances)
test_output "list-instances.sh (no instances)" \
    "list-instances.sh" \
    "instances"

# Test 2: add-instance.sh
info "Testing: add-instance.sh"
if docker exec "$CONTAINER_NAME" add-instance.sh "$TEST_INSTANCE" >/dev/null 2>&1; then
    pass "add-instance.sh (create instance)"
    
    # Verify instance appears in list
    if docker exec "$CONTAINER_NAME" list-instances.sh | grep -q "$TEST_INSTANCE"; then
        pass "add-instance.sh (instance appears in list)"
    else
        fail "add-instance.sh (instance not in list)"
    fi
else
    fail "add-instance.sh (create instance)"
fi

# Test 3: list-instances.sh (with instance)
test_output "list-instances.sh (with instance)" \
    "list-instances.sh" \
    "$TEST_INSTANCE"

# Test 4: start-instance.sh (should work even if already running)
test_command "start-instance.sh" \
    "start-instance.sh $TEST_INSTANCE"

# Test 5: stop-instance.sh
test_command "stop-instance.sh" \
    "stop-instance.sh $TEST_INSTANCE"

# Test 6: start-instance.sh again
test_command "start-instance.sh (restart)" \
    "start-instance.sh $TEST_INSTANCE"

# Test 7: view-logs.sh (stdout)
test_output "view-logs.sh (stdout)" \
    "view-logs.sh $TEST_INSTANCE --tail 10" \
    ""

# Test 8: view-logs.sh (stderr)
test_output "view-logs.sh (stderr)" \
    "view-logs.sh $TEST_INSTANCE --stderr --tail 10" \
    ""

# Test 9: backup-instance.sh
info "Testing: backup-instance.sh"
if docker exec "$CONTAINER_NAME" backup-instance.sh "$TEST_INSTANCE" >/dev/null 2>&1; then
    pass "backup-instance.sh (create backup)"
    
    # Verify backup exists
    sleep 1  # Give it a moment
    if docker exec "$CONTAINER_NAME" list-backups.sh "$TEST_INSTANCE" | grep -q "backup-"; then
        pass "backup-instance.sh (backup appears in list)"
    else
        fail "backup-instance.sh (backup not found)"
    fi
else
    fail "backup-instance.sh (create backup)"
fi

# Test 9b: backup-instance.sh error handling
test_command "backup-instance.sh (nonexistent instance)" \
    "backup-instance.sh nonexistent-instance-$(date +%s)" \
    1

# Test 10: list-backups.sh (specific instance)
test_output "list-backups.sh (specific instance)" \
    "list-backups.sh $TEST_INSTANCE" \
    "backup-"

# Test 11: list-backups.sh (all instances)
test_output "list-backups.sh (all instances)" \
    "list-backups.sh" \
    "$TEST_INSTANCE"

# Test 11b: list-backups.sh (nonexistent instance)
test_command "list-backups.sh (nonexistent instance)" \
    "list-backups.sh nonexistent-instance-$(date +%s)" \
    1

# Test 12: Get backup name for restore test
BACKUP_NAME=$(docker exec "$CONTAINER_NAME" list-backups.sh "$TEST_INSTANCE" | grep "backup-" | head -1 | awk '{print $1}')
if [ -z "$BACKUP_NAME" ]; then
    warn "Could not find backup name for restore test, skipping..."
else
    info "Found backup: $BACKUP_NAME"
    
    # Test 13: restore-instance.sh
    info "Testing: restore-instance.sh"
    if docker exec "$CONTAINER_NAME" restore-instance.sh "$TEST_INSTANCE" "$BACKUP_NAME" >/dev/null 2>&1; then
        pass "restore-instance.sh (restore from backup)"
    else
        fail "restore-instance.sh (restore from backup)"
    fi
fi

# Test 14: Error handling - invalid instance name
test_command "start-instance.sh (invalid instance)" \
    "start-instance.sh nonexistent-instance-$(date +%s)" \
    1

# Test 15: Error handling - invalid backup
# Need to create instance first for this test
TEST_INSTANCE_TEMP="test-temp-$(date +%s)"
if docker exec "$CONTAINER_NAME" add-instance.sh "$TEST_INSTANCE_TEMP" >/dev/null 2>&1; then
    test_command "restore-instance.sh (invalid backup)" \
        "restore-instance.sh $TEST_INSTANCE_TEMP nonexistent-backup.zip" \
        1
    docker exec "$CONTAINER_NAME" remove-instance.sh "$TEST_INSTANCE_TEMP" >/dev/null 2>&1 || true
fi

# Test 16: Error handling - view logs for nonexistent instance
test_command "view-logs.sh (nonexistent instance)" \
    "view-logs.sh nonexistent-instance-$(date +%s)" \
    1

# Test 17: reload-proxy.sh
test_command "reload-proxy.sh" \
    "reload-proxy.sh"

# Test 18: remove-instance.sh (cleanup)
info "Testing: remove-instance.sh (cleanup)"
if docker exec "$CONTAINER_NAME" remove-instance.sh "$TEST_INSTANCE" >/dev/null 2>&1; then
    pass "remove-instance.sh (remove instance)"
    
    # Verify instance is gone
    if ! docker exec "$CONTAINER_NAME" list-instances.sh | grep -q "$TEST_INSTANCE"; then
        pass "remove-instance.sh (instance removed from list)"
    else
        fail "remove-instance.sh (instance still in list)"
    fi
else
    fail "remove-instance.sh (remove instance)"
fi

# Test 19: add-instance.sh with options
info "Testing: add-instance.sh with email/password"
TEST_INSTANCE2="test-cli-2-$(date +%s)"
if docker exec "$CONTAINER_NAME" add-instance.sh "$TEST_INSTANCE2" --email "test@example.com" --password "testpass123" >/dev/null 2>&1; then
    pass "add-instance.sh (with email/password)"
    
    # Cleanup
    docker exec "$CONTAINER_NAME" remove-instance.sh "$TEST_INSTANCE2" >/dev/null 2>&1 || true
else
    fail "add-instance.sh (with email/password)"
fi

# Test 20: view-logs.sh options
info "Testing: view-logs.sh with various options"
# Create a temporary instance for log testing
TEST_INSTANCE3="test-logs-$(date +%s)"
if docker exec "$CONTAINER_NAME" add-instance.sh "$TEST_INSTANCE3" >/dev/null 2>&1; then
    sleep 2  # Give it time to generate logs
    
    # Test --tail option
    test_output "view-logs.sh (--tail option)" \
        "view-logs.sh $TEST_INSTANCE3 --tail 5" \
        ""
    
    # Test --stderr option
    test_output "view-logs.sh (--stderr option)" \
        "view-logs.sh $TEST_INSTANCE3 --stderr" \
        ""
    
    # Cleanup
    docker exec "$CONTAINER_NAME" remove-instance.sh "$TEST_INSTANCE3" >/dev/null 2>&1 || true
fi

# Summary
echo ""
echo "=========================================="
echo "  Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}Failed: $TESTS_FAILED${NC}"
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
