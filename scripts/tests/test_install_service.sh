#!/bin/bash

# ==============================================================================
# File: test_install_service.sh
# Description: install_service.sh 유틸리티 함수 테스트
# ==============================================================================

# Source the script under test
# Note: install_service.sh should have a source guard to prevent execution
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../install_service.sh"

# Test results
PASSED=0
FAILED=0

# Mock log functions to avoid terminal clutter during tests
log_info() { :; }
log_success() { :; }
log_error() { echo "   [ERROR] $1"; }

echo "--- Running tests for cleanup_docker_artifacts ---"

# Helper to assert file existence
assert_exists() {
    if [ -f "$1" ] || [ -d "$1" ]; then
        return 0
    else
        echo "   [FAIL] Expected '$1' to exist"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Helper to assert file non-existence
assert_not_exists() {
    if [ ! -f "$1" ] && [ ! -d "$1" ]; then
        return 0
    else
        echo "   [FAIL] Expected '$1' to be deleted"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# 1. Happy Path: All Docker artifacts exist
echo "Test 1: Happy Path - All Docker artifacts present"
DEST_DIR=$(mktemp -d)
touch "$DEST_DIR/docker-compose.yml"
touch "$DEST_DIR/bootstrap.sh"
touch "$DEST_DIR/utils.sh"
touch "$DEST_DIR/uninstall_service.sh"
touch "$DEST_DIR/.app-env.properties"
mkdir "$DEST_DIR/cron"
touch "$DEST_DIR/cron/crond"

cleanup_docker_artifacts

assert_not_exists "$DEST_DIR/docker-compose.yml" && \
assert_not_exists "$DEST_DIR/bootstrap.sh" && \
assert_not_exists "$DEST_DIR/utils.sh" && \
assert_not_exists "$DEST_DIR/uninstall_service.sh" && \
assert_not_exists "$DEST_DIR/.app-env.properties" && \
assert_not_exists "$DEST_DIR/cron" && \
echo "   [PASS] All Docker artifacts were cleaned up" && PASSED=$((PASSED + 1))

rm -rf "$DEST_DIR"

# 2. Partial Cleanup: Some artifacts exist
echo "Test 2: Partial Cleanup - Only some artifacts present"
DEST_DIR=$(mktemp -d)
touch "$DEST_DIR/docker-compose.yml"
touch "$DEST_DIR/utils.sh"

cleanup_docker_artifacts

assert_not_exists "$DEST_DIR/docker-compose.yml" && \
assert_not_exists "$DEST_DIR/utils.sh" && \
echo "   [PASS] Present artifacts were cleaned up" && PASSED=$((PASSED + 1))

rm -rf "$DEST_DIR"

# 3. Preservation: Non-Docker files should remain
echo "Test 3: Preservation - Non-Docker files remain"
DEST_DIR=$(mktemp -d)
mkdir "$DEST_DIR/libs"
touch "$DEST_DIR/libs/application.jar"
mkdir "$DEST_DIR/config"
touch "$DEST_DIR/config/application.yml"
touch "$DEST_DIR/docker-compose.yml"

cleanup_docker_artifacts

assert_not_exists "$DEST_DIR/docker-compose.yml" && \
assert_exists "$DEST_DIR/libs/application.jar" && \
assert_exists "$DEST_DIR/config/application.yml" && \
echo "   [PASS] Only Docker artifacts were cleaned up" && PASSED=$((PASSED + 1))

rm -rf "$DEST_DIR"

# 4. Empty Directory
echo "Test 4: Empty Directory - No errors"
DEST_DIR=$(mktemp -d)

cleanup_docker_artifacts
RESULT=$?

if [ $RESULT -eq 0 ]; then
    echo "   [PASS] No errors on empty directory"
    PASSED=$((PASSED + 1))
else
    echo "   [FAIL] cleanup_docker_artifacts failed with exit code $RESULT"
    FAILED=$((FAILED + 1))
fi

rm -rf "$DEST_DIR"

echo -e "\n--- Tests completed: $PASSED passed, $FAILED failed ---"

if [ $FAILED -ne 0 ]; then
    exit 1
fi
