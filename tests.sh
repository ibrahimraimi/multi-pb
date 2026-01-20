#!/bin/bash

# tests.sh - Comprehensive test suite for multi-pb
# Tests installation, CLI commands, API endpoints, Proxy routing, and Dashboard
# This script is designed for complete coverage including CI/CD scenarios
# Usage: tests.sh [--skip-install] [--cli-only] [--port PORT] [--name NAME]

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
SKIP_INSTALL=false
CLI_ONLY=false
TEST_PORT="25998"
CONTAINER_NAME="multipb-test-all"
TEST_DIR=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-install) SKIP_INSTALL=true ;;
        --cli-only) CLI_ONLY=true ;;
        --port) TEST_PORT="$2"; shift ;;
        --name) CONTAINER_NAME="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
SECTION_TESTS=0

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    SECTION_TESTS=$((SECTION_TESTS + 1))
}

fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    SECTION_TESTS=$((SECTION_TESTS + 1))
}

info() {
    echo -e "${BLUE}→${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
    SECTION_TESTS=0
}

test_command() {
    local description="$1"
    local command="$2"
    local expected_exit="${3:-0}"
    
    info "Testing: $description"
    local output
    output=$(docker exec "$CONTAINER_NAME" $command 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq "$expected_exit" ]; then
        pass "$description"
        return 0
    else
        fail "$description (exit code: $exit_code, expected: $expected_exit)"
        if [ -n "$output" ]; then
            echo "  Command output: $output"
        fi
        return 1
    fi
}

test_output() {
    local description="$1"
    local command="$2"
    local expected_pattern="$3"
    
    info "Testing: $description"
    local output
    output=$(docker exec "$CONTAINER_NAME" $command 2>&1)
    local exit_code=$?
    
    if [ -z "$expected_pattern" ]; then
        if [ $exit_code -eq 0 ]; then
            pass "$description"
            return 0
        else
            fail "$description (command failed with exit code: $exit_code)"
            return 1
        fi
    fi
    
    if echo "$output" | grep -qi "$expected_pattern"; then
        pass "$description"
        return 0
    else
        fail "$description (pattern not found: $expected_pattern)"
        if [ -n "$output" ]; then
            echo "  Actual output: $output"
        fi
        return 1
    fi
}

test_http() {
    local description="$1"
    local url="$2"
    local expected_code="${3:-200}"
    local timeout="${4:-15}"
    
    info "Testing: $description ($url)"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time "$timeout" "$url" 2>/dev/null || echo "000")
    local curl_exit=$?
    
    if [ $curl_exit -eq 28 ]; then
        fail "$description (timeout after ${timeout}s)"
        return 1
    elif [ $curl_exit -ne 0 ] && [ "$http_code" = "000" ]; then
        fail "$description (curl failed with exit code: $curl_exit)"
        return 1
    fi
    
    if [ "$http_code" = "$expected_code" ]; then
        pass "$description"
        return 0
    else
        fail "$description (HTTP $http_code, expected $expected_code)"
        return 1
    fi
}

test_json() {
    local description="$1"
    local url="$2"
    local jq_filter="$3"
    local expected_value="$4"
    
    info "Testing JSON: $description"
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not found, skipping JSON content test"
        return 0
    fi
    
    local response=$(curl -s --connect-timeout 5 --max-time 15 "$url" 2>/dev/null)
    local actual_value=$(echo "$response" | jq -r "$jq_filter" 2>/dev/null)
    
    if [ "$actual_value" = "$expected_value" ]; then
        pass "$description"
        return 0
    else
        fail "$description (Expected '$expected_value', got '$actual_value')"
        [ -n "$response" ] && echo "  Response snippet: $(echo "$response" | head -c 100)..."
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        info "Cleaning up test directory..."
        (cd "$TEST_DIR" && docker compose down >/dev/null 2>&1) || true
        rm -rf "$TEST_DIR" 2>/dev/null || true
    fi
}

# Only cleanup on exit if we created the test directory
CLEANUP_ON_EXIT=false
trap 'if [ "$CLEANUP_ON_EXIT" = "true" ] && [ -n "$TEST_DIR" ]; then cleanup; fi' EXIT

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    Multi-PB Comprehensive Test Suite     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ============================================
# SECTION 1: Installation Testing
# ============================================
if [ "$SKIP_INSTALL" != "true" ]; then
    section "Installation Testing"
    
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        warn "Container '$CONTAINER_NAME' already exists. Removing..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    
    # Create test directory
    TEST_DIR="/tmp/multipb-test-all-$(date +%s)"
    ORIG_DIR="$(pwd)"
    info "Creating test directory: $TEST_DIR"
    if ! mkdir -p "$TEST_DIR"; then
        echo -e "${RED}Error: Failed to create test directory${NC}"
        exit 1
    fi
    
    # Copy project files
    info "Copying project files..."
    if ! rsync -av --exclude '.git' --exclude 'node_modules' --exclude 'multipb-data' \
        --exclude 'dashboard/node_modules' --exclude '.DS_Store' \
        --exclude 'test-*' \
        ./ "$TEST_DIR/" >/dev/null 2>&1; then
        echo -e "${RED}Error: Failed to copy project files${NC}"
        exit 1
    fi
    
    cd "$TEST_DIR"
    
    # Test installation
    info "Running install.sh..."
    INSTALL_ARGS="--non-interactive --port $TEST_PORT --data-dir ./test-data --name $CONTAINER_NAME"
    if [ "$CLI_ONLY" = "true" ]; then
        INSTALL_ARGS="$INSTALL_ARGS --cli-only"
    fi
    
    ./install.sh $INSTALL_ARGS
    INSTALL_EXIT=$?
    
    if [ $INSTALL_EXIT -eq 0 ]; then
        pass "install.sh (installation completed)"
    else
        fail "install.sh (installation failed with exit code: $INSTALL_EXIT)"
        CLEANUP_ON_EXIT=true
        exit 1
    fi
    
    # Wait for container to be healthy
    info "Waiting for container to be healthy..."
    MAX_RETRIES=30
    HEALTHY=false
    
    info "Waiting 5 seconds for container to initialize..."
    sleep 5
    
    for i in $(seq 1 $MAX_RETRIES); do
        if curl -s -f "http://localhost:$TEST_PORT/_health" >/dev/null 2>&1; then
            HEALTHY=true
            info "Container is healthy! (attempt $i)"
            break
        fi
        
        if [ $i -lt $MAX_RETRIES ]; then
            [ $((i % 5)) -eq 0 ] && info "Still waiting for health check... ($i/$MAX_RETRIES)"
            sleep 2
        fi
    done
    
    if [ "$HEALTHY" = true ]; then
        pass "Container health check"
    else
        fail "Container health check failed after $MAX_RETRIES attempts"
        docker logs "$CONTAINER_NAME" 2>&1 | tail -50
        CLEANUP_ON_EXIT=true
        exit 1
    fi
    
    echo -e "${GREEN}Installation tests: $SECTION_TESTS passed${NC}"
    CLEANUP_ON_EXIT=true
    
    if [ -n "$ORIG_DIR" ]; then
        cd "$ORIG_DIR" >/dev/null 2>&1 || true
    fi
else
    section "Installation Testing (Skipped)"
    info "Skipping installation (--skip-install flag set)"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${RED}Error: Container '$CONTAINER_NAME' is not running${NC}"
        exit 1
    fi
    CLEANUP_ON_EXIT=false
fi

# ============================================
# SECTION 2: Web API and Proxy Testing
# ============================================
section "Web API and Proxy Functionality"

# Test core endpoints
test_http "Health endpoint" "http://localhost:$TEST_PORT/_health" 200
test_http "Instances list API" "http://localhost:$TEST_PORT/api/instances" 200
test_http "System stats API" "http://localhost:$TEST_PORT/api/stats" 200

if [ "$CLI_ONLY" != "true" ]; then
    test_http "Dashboard UI accessibility" "http://localhost:$TEST_PORT/dashboard/" 200
else
    info "Skipping dashboard UI test (CLI-only mode)"
fi

# Test instance creation via API
API_INSTANCE="api-test-$(date +%s)"
info "Testing instance creation via API: $API_INSTANCE"
API_CREATE_RESP=$(curl -s -X POST "http://localhost:$TEST_PORT/api/instances" \
     -H "Content-Type: application/json" \
     -d "{\"name\": \"$API_INSTANCE\"}")

if echo "$API_CREATE_RESP" | grep -qi "true" 2>/dev/null; then
    pass "API: Create instance"
    info "Waiting for API instance to initialize and Caddy to reload..."
    sleep 8
    
    test_http "Proxy routing to instance ($API_INSTANCE)" "http://localhost:$TEST_PORT/$API_INSTANCE/api/health" 200
    test_json "API: Instance details status" "http://localhost:$TEST_PORT/api/instances/$API_INSTANCE" ".status" "running"
    
    info "Testing instance stop via API..."
    curl -s -X POST "http://localhost:$TEST_PORT/api/instances/$API_INSTANCE/stop" > /dev/null
    sleep 3
    test_json "API: Instance status after stop" "http://localhost:$TEST_PORT/api/instances/$API_INSTANCE" ".status" "stopped"
    
    info "Testing instance start via API..."
    curl -s -X POST "http://localhost:$TEST_PORT/api/instances/$API_INSTANCE/start" > /dev/null
    sleep 5
    test_json "API: Instance status after restart" "http://localhost:$TEST_PORT/api/instances/$API_INSTANCE" ".status" "running"
    
    info "Testing instance deletion via API..."
    curl -s -X DELETE "http://localhost:$TEST_PORT/api/instances/$API_INSTANCE" > /dev/null
    sleep 2
    test_http "API: Instance gone after delete" "http://localhost:$TEST_PORT/api/instances/$API_INSTANCE" 404
else
    fail "API: Create instance failed"
    echo "  Response: $API_CREATE_RESP"
fi

echo -e "${GREEN}API & Proxy tests: $SECTION_TESTS passed${NC}"

# ============================================
# SECTION 3: Basic CLI Commands
# ============================================
section "Basic CLI Commands"

info "Starting CLI command tests..."
TEST_INSTANCE="test-cli-$(date +%s)"

test_output "list-instances.sh syntax check" "list-instances.sh" "instances"

info "Testing: add-instance.sh"
ADD_OUTPUT=$(docker exec "$CONTAINER_NAME" add-instance.sh "$TEST_INSTANCE" 2>&1)
ADD_EXIT=$?

if [ $ADD_EXIT -eq 0 ]; then
    pass "add-instance.sh (create instance)"
    if docker exec "$CONTAINER_NAME" list-instances.sh | grep -qi "$TEST_INSTANCE"; then
        pass "add-instance.sh (instance appears in list)"
    else
        fail "add-instance.sh (instance not in list)"
    fi
else
    fail "add-instance.sh (create instance) - exit code: $ADD_EXIT"
    echo "  Command output: $ADD_OUTPUT"
fi

test_output "list-instances.sh (find created instance)" "list-instances.sh" "$TEST_INSTANCE"

TEST_INSTANCE_OPTS="test-opts-$(date +%s)"
test_command "add-instance.sh (with email/password)" \
    "add-instance.sh $TEST_INSTANCE_OPTS --email test@example.com --password testpass123"

docker exec "$CONTAINER_NAME" remove-instance.sh "$TEST_INSTANCE_OPTS" >/dev/null 2>&1 || true

echo -e "${GREEN}Basic CLI tests: $SECTION_TESTS passed${NC}"

# ============================================
# SECTION 4: Instance Lifecycle (CLI)
# ============================================
section "Instance Lifecycle Management (CLI)"

test_command "start-instance.sh (idempotency)" "start-instance.sh $TEST_INSTANCE"
test_command "stop-instance.sh" "stop-instance.sh $TEST_INSTANCE"
test_command "start-instance.sh (restart from stopped)" "start-instance.sh $TEST_INSTANCE"

info "Waiting for Caddy/PB to stabilize..."
sleep 5
test_http "Proxy routing after CLI restart" "http://localhost:$TEST_PORT/$TEST_INSTANCE/api/health" 200

test_command "start-instance.sh (nonexistent instance)" "start-instance.sh nonexistent-$(date +%s)" 1

echo -e "${GREEN}Lifecycle tests: $SECTION_TESTS passed${NC}"

# ============================================
# SECTION 5: Backup Operations
# ============================================
section "Backup Operations"

info "Testing: backup-instance.sh"
BACKUP_OUTPUT=$(docker exec "$CONTAINER_NAME" backup-instance.sh "$TEST_INSTANCE" 2>&1)
if [ $? -eq 0 ]; then
    pass "backup-instance.sh (create backup)"
    sleep 2
    BACKUP_LIST=$(docker exec "$CONTAINER_NAME" list-backups.sh "$TEST_INSTANCE" 2>&1)
    if echo "$BACKUP_LIST" | grep -qi "backup-"; then
        pass "backup-instance.sh (backup appears in list)"
    else
        fail "backup-instance.sh (backup not found in list)"
    fi
else
    fail "backup-instance.sh (create backup)"
fi

BACKUP_NAME=$(docker exec "$CONTAINER_NAME" list-backups.sh "$TEST_INSTANCE" 2>/dev/null | grep "backup-" | head -1 | awk '{print $1}')
if [ -n "$BACKUP_NAME" ]; then
    info "Found backup for testing: $BACKUP_NAME"
    test_command "restore-instance.sh (restore from backup)" "restore-instance.sh $TEST_INSTANCE $BACKUP_NAME"
fi

test_command "backup-instance.sh (nonexistent instance)" "backup-instance.sh nonexistent-$(date +%s)" 1

echo -e "${GREEN}Backup tests: $SECTION_TESTS passed${NC}"

# ============================================
# SECTION 6: Log Viewing
# ============================================
section "Log Viewing"

test_output "view-logs.sh (stdout access)" "view-logs.sh $TEST_INSTANCE --tail 5" ""
test_output "view-logs.sh (stderr access)" "view-logs.sh $TEST_INSTANCE --stderr --tail 5" ""
test_command "view-logs.sh (nonexistent instance)" "view-logs.sh nonexistent-$(date +%s)" 1

echo -e "${GREEN}Log viewing tests: $SECTION_TESTS passed${NC}"

# ============================================
# SECTION 7: Proxy and Maintenance
# ============================================
section "Proxy and Maintenance"

test_command "reload-proxy.sh (manual trigger)" "reload-proxy.sh"

TEST_INSTANCE_DELETE="test-delete-$(date +%s)"
docker exec "$CONTAINER_NAME" add-instance.sh "$TEST_INSTANCE_DELETE" >/dev/null 2>&1
test_command "remove-instance.sh (with --delete-data)" "remove-instance.sh $TEST_INSTANCE_DELETE --delete-data"

docker exec "$CONTAINER_NAME" add-instance.sh "$TEST_INSTANCE" >/dev/null 2>&1
duplicate_exit=$?

if [ $duplicate_exit -ne 0 ]; then
    pass "add-instance.sh (duplicate name rejection)"
else
    fail "add-instance.sh (duplicate name SHOULD be rejected, but exit code was $duplicate_exit)"
fi

echo -e "${GREEN}Maintenance tests: $SECTION_TESTS passed${NC}"

# ============================================
# SECTION 8: Cleanup and Final check
# ============================================
section "Final Cleanup"

test_command "remove-instance.sh (final cleanup)" "remove-instance.sh $TEST_INSTANCE"

INSTANCE_LIST=$(docker exec "$CONTAINER_NAME" list-instances.sh 2>&1)
if ! echo "$INSTANCE_LIST" | grep -qi "$TEST_INSTANCE"; then
    pass "Final check: instance removed successfully"
else
    fail "Final check: instance still exists in list"
fi

echo -e "${GREEN}Cleanup tests: $SECTION_TESTS passed${NC}"

# ============================================
# Final Summary
# ============================================
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Test Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}Total Passed: $TESTS_PASSED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Total Failed: $TESTS_FAILED${NC}"
    echo ""
    echo -e "${RED}Some tests failed! Check the output above.${NC}"
    CLEANUP_ON_EXIT=true
    exit 1
else
    echo -e "${GREEN}Total Failed: $TESTS_FAILED${NC}"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     All tests passed successfully!        ║${NC}"
    echo -e "${GREEN}║    Comprehensive functionality verified   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    CLEANUP_ON_EXIT=true
    exit 0
fi
