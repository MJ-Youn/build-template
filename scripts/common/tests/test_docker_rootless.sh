#!/bin/bash
# ==============================================================================
# File: test_docker_rootless.sh
# Description: Rootless Docker 환경 감지, docker-compose user 보정 및 .env 동적 생성 단위 테스트
# Author: 윤명준 (MJ Yun)
# ==============================================================================

set -u

TEST_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
COMMON_DIR="$(dirname "$TEST_SCRIPT_DIR")"
REPO_ROOT="$(dirname "$(dirname "$COMMON_DIR")")"

source "$COMMON_DIR/utils.sh"

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

# ------------------------------------------------------------------------------
# 1. detect_docker_runtime_mode 테스트 (Mock docker 바이너리 사용)
# ------------------------------------------------------------------------------
echo "▶ Test 1: detect_docker_runtime_mode"

MOCK_BIN_DIR="$TMP_ROOT/mock_bin"
mkdir -p "$MOCK_BIN_DIR"
ORIG_PATH="$PATH"

# 1-1. Rootless Docker 모킹
cat <<'EOF' > "$MOCK_BIN_DIR/docker"
#!/bin/bash
if [ "$1" = "info" ]; then
    echo "[name=seccomp,profile=builtin name=rootless name=cgroupns]"
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/docker"
PATH="$MOCK_BIN_DIR:$ORIG_PATH"
detect_docker_runtime_mode
rc=$?
assert_equals "0" "$rc" "rootless 반환 코드"
assert_equals "rootless" "$DOCKER_RUNTIME_MODE" "rootless 모드 감지"
assert_equals "docker" "$DOCKER_CMD" "rootless DOCKER_CMD"

# 1-2. 일반 Docker (docker 그룹 권한 보유) 모킹
cat <<'EOF' > "$MOCK_BIN_DIR/docker"
#!/bin/bash
if [ "$1" = "info" ]; then
    echo "[name=apparmor name=seccomp,profile=builtin name=cgroupns]"
    exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/docker"
detect_docker_runtime_mode
rc=$?
assert_equals "0" "$rc" "rootful_group 반환 코드"
assert_equals "rootful_group" "$DOCKER_RUNTIME_MODE" "rootful_group 모드 감지"
assert_equals "docker" "$DOCKER_CMD" "rootful_group DOCKER_CMD"

# 1-3. 일반 Docker (sudo 필요 - permission denied) 모킹
cat <<'EOF' > "$MOCK_BIN_DIR/docker"
#!/bin/bash
if [ "$1" = "info" ]; then
    echo "permission denied while trying to connect to the Docker daemon socket" >&2
    exit 1
fi
exit 1
EOF
chmod +x "$MOCK_BIN_DIR/docker"
detect_docker_runtime_mode
rc=$?
assert_equals "0" "$rc" "rootful_sudo 반환 코드"
assert_equals "rootful_sudo" "$DOCKER_RUNTIME_MODE" "rootful_sudo 모드 감지"
assert_equals "sudo docker" "$DOCKER_CMD" "rootful_sudo DOCKER_CMD"

# 1-4. 데몬 미실행/연결 불가 모킹 (sudo도 실패하도록 mock sudo 배치)
cat <<'EOF' > "$MOCK_BIN_DIR/docker"
#!/bin/bash
if [ "$1" = "info" ]; then
    echo "Cannot connect to the Docker daemon." >&2
    exit 1
fi
exit 1
EOF
cat <<'EOF' > "$MOCK_BIN_DIR/sudo"
#!/bin/bash
exit 1
EOF
chmod +x "$MOCK_BIN_DIR/docker" "$MOCK_BIN_DIR/sudo"
detect_docker_runtime_mode
rc=$?
assert_equals "1" "$rc" "unavailable 반환 코드"
assert_equals "unavailable" "$DOCKER_RUNTIME_MODE" "unavailable 모드 감지"

PATH="$ORIG_PATH"

# ------------------------------------------------------------------------------
# 2. ensure_compose_user_setting 테스트
# ------------------------------------------------------------------------------
echo "▶ Test 2: ensure_compose_user_setting"

# 2-1. user 누락된 표준 compose 파일에 user: "0:0" 삽입 및 멱등성 확인
COMPOSE_1="$TMP_ROOT/compose1.yml"
cat <<'EOF' > "$COMPOSE_1"
services:
  app:
    image: ${DOCKER_IMAGE:-app:latest}
    container_name: ${APP_NAME:-app}
    ports:
      - "8080:8080"
EOF
ensure_compose_user_setting "$COMPOSE_1"
assert_equals "0" "$?" "compose1 처리 성공"
assert_equals "1" "$(grep -c 'user: "0:0"' "$COMPOSE_1")" "user: \"0:0\" 1회 삽입"

# 2회 연속 실행 시 중복 삽입 방지 (멱등성)
ensure_compose_user_setting "$COMPOSE_1"
assert_equals "1" "$(grep -c 'user: "0:0"' "$COMPOSE_1")" "멱등성: 재실행 후에도 1개 유지"

# 2-2. 이미 커스텀 user가 지정된 서비스는 보존, 누락된 서비스에만 추가 + 최상위 networks 섹션 보존
COMPOSE_2="$TMP_ROOT/compose2.yml"
cat <<'EOF' > "$COMPOSE_2"
services:
  web:
    build: .
    ports:
      - "8080:8080"
  db:
    image: postgres:16
    user: "999:999"

networks:
  default:
    driver: bridge
EOF
ensure_compose_user_setting "$COMPOSE_2"
assert_equals "0" "$?" "compose2 처리 성공"
assert_equals "1" "$(grep -c '    user: "0:0"' "$COMPOSE_2")" "web 서비스에만 user: \"0:0\" 삽입"
assert_equals "1" "$(grep -c '    user: "999:999"' "$COMPOSE_2")" "db 서비스의 기존 user 설정 유지"

# ------------------------------------------------------------------------------
# 3. install_service.sh configure_compose 통합 테스트 (.env UID/GID 동적 생성)
# ------------------------------------------------------------------------------
echo "▶ Test 3: configure_compose (.env APP_UID/APP_GID 동적 분기)"

INSTALL_FUNCS_FILE="$TMP_ROOT/install_funcs.sh"
# 마지막 메인 실행부(install_service)를 제외하고 함수 정의만 추출
sed '/^# --- \[Execution\] ---$/,$d' "$REPO_ROOT/scripts/deploy/install_service.sh" > "$INSTALL_FUNCS_FILE"

# 테스트용 변수 초기화 후 함수 로드
SCRIPT_DIR="$REPO_ROOT/scripts/deploy"
PKG_ROOT="$TMP_ROOT/pkg"
mkdir -p "$PKG_ROOT/config"
APP_NAME="sample-app"
REAL_USER="$(id -un)"
SERVICE_GROUP="$(id -gn)"
LOG_PATH="$TMP_ROOT/logs"
HTTP_PORT="8080"

# shellcheck disable=SC1090
source "$INSTALL_FUNCS_FILE"

# 3-1. Rootless Docker 환경 테스트
DEST_DIR="$TMP_ROOT/dest_rootless"
mkdir -p "$DEST_DIR/config"
touch "$DEST_DIR/config/application.yml"
cp "$TMP_ROOT/compose1.yml" "$DEST_DIR/docker-compose.yml"
# user 라인 제거해 누락 상태 시뮬레이션
grep -v 'user:' "$TMP_ROOT/compose1.yml" > "$DEST_DIR/docker-compose.yml"
DOCKER_RUNTIME_MODE="rootless"

configure_compose
assert_equals "0" "$(grep '^APP_UID=' "$DEST_DIR/.env" | cut -d= -f2)" "Rootless 환경 APP_UID=0"
assert_equals "0" "$(grep '^APP_GID=' "$DEST_DIR/.env" | cut -d= -f2)" "Rootless 환경 APP_GID=0"
assert_equals "1" "$(grep -c 'user: "0:0"' "$DEST_DIR/docker-compose.yml")" "Rootless 환경 docker-compose user 보정"

# 3-2. 일반 Docker 환경 테스트
DEST_DIR="$TMP_ROOT/dest_rootful"
mkdir -p "$DEST_DIR/config"
touch "$DEST_DIR/config/application.yml"
grep -v 'user:' "$TMP_ROOT/compose1.yml" > "$DEST_DIR/docker-compose.yml"
DOCKER_RUNTIME_MODE="rootful_group"

configure_compose
assert_equals "$(id -u "$REAL_USER")" "$(grep '^APP_UID=' "$DEST_DIR/.env" | cut -d= -f2)" "일반 Docker 환경 APP_UID=호스트 UID"
assert_equals "$(id -g "$REAL_USER")" "$(grep '^APP_GID=' "$DEST_DIR/.env" | cut -d= -f2)" "일반 Docker 환경 APP_GID=호스트 GID"

echo "----------------------------------------------------------------"
echo "Result: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
fi
exit 0

