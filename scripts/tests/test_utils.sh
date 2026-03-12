#!/bin/bash

# Source the utility script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../utils.sh"

# Test results
PASSED=0
FAILED=0

# Mock chown to avoid permission issues during tests
chown() {
    # echo "   [MOCK] chown $@"
    return 0
}

# Helper function to assert success (safe path)
assert_safe() {
    local path="$1"
    if is_safe_path "$path"; then
        echo -e "   [PASS] '$path' is safe"
        PASSED=$((PASSED + 1))
    else
        echo -e "   [FAIL] '$path' should be safe"
        FAILED=$((FAILED + 1))
    fi
}

# Helper function to assert failure (unsafe path)
assert_unsafe() {
    local path="$1"
    if ! is_safe_path "$path"; then
        echo -e "   [PASS] '$path' is unsafe"
        PASSED=$((PASSED + 1))
    else
        echo -e "   [FAIL] '$path' should be unsafe"
        FAILED=$((FAILED + 1))
    fi
}

echo "--- Running tests for is_safe_path ---"

# 1. Empty path
assert_unsafe ""

# 2. Sensitive system paths (Exact matches)
assert_unsafe "/"
assert_unsafe "/bin"
assert_unsafe "/etc"
assert_unsafe "/usr/bin"
assert_unsafe "/var/log"
assert_unsafe "/root"
assert_unsafe "/tmp"

# 3. Normalization tests (should resolve to sensitive paths)
assert_unsafe "/etc/../etc"
assert_unsafe "/usr/bin/."
assert_unsafe "//etc"

# 4. Safe paths (Absolute paths not in sensitive list)
assert_safe "/opt/my-app"
assert_safe "/home/user/my-project"
assert_safe "/tmp/safe-to-delete-dir"
assert_safe "/var/log/my-app"

# 5. Root-level but not "/"
assert_safe "/my-app-data"

echo -e "\n--- Running tests for add_path_to_profile ---"

# Create a temporary profile file for testing
TEMP_PROFILE=$(mktemp)

# Test 1: Add new path to profile
APP_NAME="TestApp"
TEST_PATH="/opt/test/bin"
if add_path_to_profile "$TEMP_PROFILE" "$TEST_PATH"; then
    if grep -q "$TEST_PATH" "$TEMP_PROFILE" && grep -q "Added by $APP_NAME" "$TEMP_PROFILE"; then
        echo -e "   [PASS] Path added correctly to profile"
        PASSED=$((PASSED + 1))
    else
        echo -e "   [FAIL] Path was not found in profile or comment is missing"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "   [FAIL] add_path_to_profile returned failure for new path"
    FAILED=$((FAILED + 1))
fi

# Test 2: Add same path again (should fail/skip)
if ! add_path_to_profile "$TEMP_PROFILE" "$TEST_PATH"; then
    echo -e "   [PASS] Duplicate path not added"
    PASSED=$((PASSED + 1))
else
    echo -e "   [FAIL] add_path_to_profile returned success for duplicate path"
    FAILED=$((FAILED + 1))
fi

# Test 3: Profile file does not exist
if ! add_path_to_profile "/tmp/non_existent_profile_$(date +%s)" "$TEST_PATH"; then
    echo -e "   [PASS] Handled non-existent profile"
    PASSED=$((PASSED + 1))
else
    echo -e "   [FAIL] add_path_to_profile should fail for non-existent profile"
    FAILED=$((FAILED + 1))
fi

# Test 4: Verify APP_NAME default value
unset APP_NAME
TEST_PATH2="/opt/test2/bin"
if add_path_to_profile "$TEMP_PROFILE" "$TEST_PATH2"; then
    if grep -q "Added by Application" "$TEMP_PROFILE"; then
        echo -e "   [PASS] Used default APP_NAME"
        PASSED=$((PASSED + 1))
    else
        echo -e "   [FAIL] Default APP_NAME 'Application' not found in comment"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "   [FAIL] add_path_to_profile failed for second new path"
    FAILED=$((FAILED + 1))
fi

# Test 5: REAL_USER and SERVICE_GROUP trigger chown (Mocked)
export REAL_USER="testuser"
export SERVICE_GROUP="testgroup"
TEST_PATH3="/opt/test3/bin"
if add_path_to_profile "$TEMP_PROFILE" "$TEST_PATH3"; then
    echo -e "   [PASS] add_path_to_profile worked with REAL_USER/SERVICE_GROUP"
    PASSED=$((PASSED + 1))
else
    echo -e "   [FAIL] add_path_to_profile failed with REAL_USER/SERVICE_GROUP"
    FAILED=$((FAILED + 1))
fi
unset REAL_USER
unset SERVICE_GROUP

# Cleanup
rm "$TEMP_PROFILE"

echo -e "\n--- Tests completed: $PASSED passed, $FAILED failed ---"

if [ $FAILED -ne 0 ]; then
    exit 1
fi
