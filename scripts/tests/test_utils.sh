#!/bin/bash

# Source the utility script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../utils.sh"

# Test results
PASSED=0
FAILED=0

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

# 6. Relative paths
# If readlink -f is available, it resolves to absolute path.
# We can simulate readlink failure by using a path that might not resolve if we were in a restricted env,
# but here it seems to always resolve to absolute.
# To test the [[ ! "$normalized_path" =~ ^/ ]] logic, we'd need readlink -f to fail or return relative.
# We can try to test with a value that we know will remain relative if readlink fails.
# Since we can't easily make readlink fail, we trust the logic for absolute paths for now.

echo "--- Tests completed: $PASSED passed, $FAILED failed ---"

if [ $FAILED -ne 0 ]; then
    exit 1
fi
