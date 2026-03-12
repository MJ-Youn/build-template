#!/bin/bash

# Test script for bootstrap.sh
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BOOTSTRAP_PATH="$SCRIPT_DIR/../bootstrap.sh"
UTILS_PATH="$SCRIPT_DIR/../utils.sh"

# Test results
PASSED=0
FAILED=0

assert_defined() {
    if declare -f "$1" > /dev/null; then
        echo -e "   [PASS] Function '$1' is defined"
        PASSED=$((PASSED + 1))
    else
        echo -e "   [FAIL] Function '$1' is NOT defined"
        FAILED=$((FAILED + 1))
    fi
}

echo "--- Running tests for bootstrap.sh (with utils.sh) ---"

# 1. Test when utils.sh is present
if [ -f "$UTILS_PATH" ]; then
    echo "   utils.sh found at $UTILS_PATH"
    # Start a fresh subshell to avoid contamination
    (
        source "$BOOTSTRAP_PATH"
        assert_defined "log_header"
        assert_defined "log_step"
        assert_defined "log_info"
        assert_defined "log_success"
        assert_defined "log_warning"
        assert_defined "log_error"
        assert_defined "is_safe_path"
        assert_defined "add_path_to_profile"
        exit $((FAILED > 0))
    )
    if [ $? -eq 0 ]; then
        PASSED=$((PASSED + 8))
    else
        FAILED=$((FAILED + 1))
    fi
else
    echo "   [SKIP] utils.sh not found, skipping 'with utils.sh' test."
fi

echo "--- Running tests for bootstrap.sh (fallback mode) ---"

# 2. Test when utils.sh is missing
(
    # Move utils.sh temporarily if it exists
    if [ -f "$UTILS_PATH" ]; then
        mv "$UTILS_PATH" "${UTILS_PATH}.bak"
    fi

    source "$BOOTSTRAP_PATH"

    # Check if functions are defined
    SUCCESS=0
    declare -f log_header > /dev/null || SUCCESS=1
    declare -f log_step > /dev/null || SUCCESS=1
    declare -f log_info > /dev/null || SUCCESS=1
    declare -f log_success > /dev/null || SUCCESS=1
    declare -f log_warning > /dev/null || SUCCESS=1
    declare -f log_error > /dev/null || SUCCESS=1
    declare -f is_safe_path > /dev/null || SUCCESS=1
    declare -f add_path_to_profile > /dev/null || SUCCESS=1

    # Restore utils.sh
    if [ -f "${UTILS_PATH}.bak" ]; then
        mv "${UTILS_PATH}.bak" "$UTILS_PATH"
    fi

    exit $SUCCESS
)
if [ $? -eq 0 ]; then
    echo -e "   [PASS] All fallback functions defined"
    PASSED=$((PASSED + 8))
else
    echo -e "   [FAIL] Some fallback functions NOT defined"
    FAILED=$((FAILED + 1))
fi

echo "--- Tests completed: $PASSED passed, $FAILED failed ---"

if [ $FAILED -ne 0 ]; then
    exit 1
fi
