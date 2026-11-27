#!/bin/bash
# ==============================================================================
# File: test_build_deploy.sh
# Description: build_deploy.sh --help, --profiles 분석 및 이전 Profile 기억 기능 테스트
# Author: 윤명준 (MJ Yun)
# ==============================================================================

set -u

TEST_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
COMMON_DIR="$(dirname "$TEST_SCRIPT_DIR")"
REPO_ROOT="$(dirname "$(dirname "$COMMON_DIR")")"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  [PASS] $label (expected=$expected)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (expected='$expected', actual='$actual')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if echo "$haystack" | grep -Fq -- "$needle"; then
        echo "  [PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (missing '$needle')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# 테스트용 프로젝트 루트 구성
PROJ_DIR="$TMP_ROOT/project"
mkdir -p "$PROJ_DIR/config" "$PROJ_DIR/config.profiles/dev" "$PROJ_DIR/config.profiles/prod" "$PROJ_DIR/build/distributions"
cp "$REPO_ROOT/build_deploy.sh" "$PROJ_DIR/build_deploy.sh"
chmod +x "$PROJ_DIR/build_deploy.sh"

touch "$PROJ_DIR/config/application.yml"
touch "$PROJ_DIR/config/application-staging.yml"
touch "$PROJ_DIR/config.profiles/dev/application-dev.yml"
touch "$PROJ_DIR/config.profiles/prod/application-prod.yml"

# Mock gradlew & zip 생성
GRADLE_CALL_LOG="$TMP_ROOT/gradle_calls.log"
cat <<EOF > "$PROJ_DIR/gradlew"
#!/bin/bash
echo "\$*" >> "$GRADLE_CALL_LOG"
mkdir -p "$PROJ_DIR/build/distributions"
TMP_PKG="$TMP_ROOT/pkg_src"
rm -rf "\$TMP_PKG"
mkdir -p "\$TMP_PKG/deploy"
cat <<'EOS' > "\$TMP_PKG/deploy/install_service.sh"
#!/bin/bash
echo "mock install_service.sh executed: \$*"
exit 0
EOS
chmod +x "\$TMP_PKG/deploy/install_service.sh"
(cd "\$TMP_PKG" && zip -q -r "$PROJ_DIR/build/distributions/app-1.0.0.dist.zip" .)
exit 0
EOF
chmod +x "$PROJ_DIR/gradlew"

# 1. --help 확인
echo "▶ Test 1: build_deploy.sh --help 출력 검증"
HELP_OUT=$(bash "$PROJ_DIR/build_deploy.sh" --help 2>&1)
assert_contains "$HELP_OUT" "--profiles" "--help에 --profiles 옵션 포함"
assert_contains "$HELP_OUT" "직전 프로파일" "--help에 이전 프로파일 자동 재배포 안내 포함"

# 2. --profiles 목록 분석 확인
echo "▶ Test 2: --profiles 실행 시 config / config.profiles 분석 검증"
PROFILES_OUT=$(bash "$PROJ_DIR/build_deploy.sh" --profiles 2>&1)
assert_contains "$PROFILES_OUT" "dev" "config.profiles/dev 감지"
assert_contains "$PROFILES_OUT" "prod" "config.profiles/prod 감지"
assert_contains "$PROFILES_OUT" "staging" "config/application-staging.yml 감지"

# 3. 최초 실행 시 profile 미지정 -> 목록 출력 후 종료(exit 1)
echo "▶ Test 3: 최초 실행 시 profile 미지정 안내 검증"
set +e
NO_ENV_OUT=$(bash "$PROJ_DIR/build_deploy.sh" --no-pull 2>&1)
NO_ENV_RC=$?
set -e
assert_equals "1" "$NO_ENV_RC" "최초 실행 profile 미지정 시 exit 1"
assert_contains "$NO_ENV_OUT" "사용 가능한 배포 프로파일" "profile 미지정 시 사용 가능한 목록 출력"
assert_contains "$NO_ENV_OUT" "staging" "목록에 staging 포함"

# 4. 최초 배포 실행 (prod) -> .build_deploy.env 저장 확인
echo "▶ Test 4: 최초 배포 후 이전 Profile 저장 검증"
: > "$GRADLE_CALL_LOG"
bash "$PROJ_DIR/build_deploy.sh" prod --no-pull >/dev/null 2>&1
assert_contains "$(cat "$GRADLE_CALL_LOG")" "-Penv=prod" "prod 프로파일로 Gradle 빌드 호출"
assert_contains "$(cat "$PROJ_DIR/.build_deploy.env")" 'LAST_PROFILE="prod"' ".build_deploy.env에 LAST_PROFILE=prod 저장"

# 5. 이후 profile 미지정 실행 -> 이전 profile(prod) 자동 재사용 검증
echo "▶ Test 5: profile 미지정 재실행 시 이전 Profile 자동 사용 검증"
: > "$GRADLE_CALL_LOG"
REUSE_OUT=$(bash "$PROJ_DIR/build_deploy.sh" --no-pull 2>&1)
assert_contains "$REUSE_OUT" "이전 배포 프로파일" "이전 프로파일 자동 사용 안내 출력"
assert_contains "$(cat "$GRADLE_CALL_LOG")" "-Penv=prod" "재실행 시 자동으로 -Penv=prod 전달"

echo "================================================================"
echo "📊 build_deploy Test Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "================================================================"

if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
fi
