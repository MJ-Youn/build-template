#!/bin/bash

# ==============================================================================
# File: run_bash_tests.sh
# Description: bash 테스트 스크립트 실행기
# ==============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
TEST_DIR="$SCRIPT_DIR/tests"

PASSED_SCRIPTS=0
FAILED_SCRIPTS=0

echo "🚀 Running all bash tests in $TEST_DIR..."

for test_script in "$TEST_DIR"/test_*.sh; do
    if [ -f "$test_script" ]; then
        echo "----------------------------------------------------------------"
        echo "🏃 Executing: $(basename "$test_script")"
        if bash "$test_script"; then
            echo "✅ $(basename "$test_script") passed"
            PASSED_SCRIPTS=$((PASSED_SCRIPTS + 1))
        else
            echo "❌ $(basename "$test_script") failed"
            FAILED_SCRIPTS=$((FAILED_SCRIPTS + 1))
        fi
    fi
done

echo "================================================================"
echo "📊 Summary: $PASSED_SCRIPTS scripts passed, $FAILED_SCRIPTS scripts failed"
echo "================================================================"

if [ $FAILED_SCRIPTS -ne 0 ]; then
    exit 1
fi
