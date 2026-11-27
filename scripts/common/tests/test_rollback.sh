#!/bin/bash
# ==============================================================================
# File: test_rollback.sh
# Description: 배포 스냅샷 생성, 롤백(Legacy/Docker), 스냅샷 Pruning 및 권한 검증 테스트
# Author: 윤명준 (MJ Yun)
# ==============================================================================

set -u

TEST_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
COMMON_DIR="$(dirname "$TEST_SCRIPT_DIR")"
REPO_ROOT="$(dirname "$(dirname "$COMMON_DIR")")"

INSTALL_SCRIPT="$REPO_ROOT/scripts/deploy/install_service.sh"
ROLLBACK_SCRIPT="$REPO_ROOT/scripts/deploy/rollback_service.sh"

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

assert_file_exists() {
    local path="$1"
    local label="$2"
    if [ -e "$path" ] || [ -L "$path" ]; then
        echo "  [PASS] $label ($path)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (not found: $path)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_file_not_exists() {
    local path="$1"
    local label="$2"
    if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        echo "  [PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (still exists: $path)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  [PASS] $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] $label (missing '$needle')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ------------------------------------------------------------------------------
# Mock 환경 구성 (HOME, systemctl, docker, crontab, java 등)
# ------------------------------------------------------------------------------
MOCK_HOME="$TMP_ROOT/home"
MOCK_BIN="$TMP_ROOT/mock_bin"
mkdir -p "$MOCK_HOME/.config/systemd/user" "$MOCK_HOME/bin" "$MOCK_BIN"

cat <<'EOF' > "$MOCK_BIN/systemctl"
#!/bin/bash
exit 0
EOF

cat <<'EOF' > "$MOCK_BIN/java"
#!/bin/bash
echo "openjdk version 17"
exit 0
EOF

cat <<'EOF' > "$MOCK_BIN/crontab"
#!/bin/bash
exit 0
EOF

DOCKER_LOG="$TMP_ROOT/docker_calls.log"
cat <<EOF > "$MOCK_BIN/docker"
#!/bin/bash
echo "\$*" >> "$DOCKER_LOG"
case "\$1" in
    info)
        echo "[name=seccomp,profile=builtin name=rootless]"
        exit 0
        ;;
    compose)
        exit 0
        ;;
    inspect)
        if [ "\$2" = "--format={{.Image}}" ]; then
            echo "sha256:old_image_id_1234"
        fi
        exit 0
        ;;
    image)
        if [ "\$2" = "inspect" ]; then
            exit 0
        fi
        ;;
    tag|rmi|load|build|pull|ps)
        exit 0
        ;;
esac
exit 0
EOF

chmod +x "$MOCK_BIN/systemctl" "$MOCK_BIN/java" "$MOCK_BIN/crontab" "$MOCK_BIN/docker"

ORIG_PATH="$PATH"
ORIG_HOME="$HOME"
export HOME="$MOCK_HOME"
export PATH="$MOCK_BIN:$ORIG_PATH"

# ------------------------------------------------------------------------------
# 1. 초기 배포 상태(스냅샷 없음) 롤백 거부 테스트
# ------------------------------------------------------------------------------
echo "▶ Test 1: 초기 배포 상태 롤백 거부 검증"
INIT_DIR="$TMP_ROOT/init_app"
mkdir -p "$INIT_DIR/bin"
cp "$ROLLBACK_SCRIPT" "$INIT_DIR/bin/rollback_service.sh"
cp "$REPO_ROOT/scripts/common/bootstrap.sh" "$INIT_DIR/bin/"
cp "$REPO_ROOT/scripts/common/utils.sh" "$INIT_DIR/bin/"

set +e
OUT_INIT=$(bash "$INIT_DIR/bin/rollback_service.sh" --yes 2>&1)
RC_INIT=$?
set -e
assert_equals "1" "$RC_INIT" "초기 배포 시 롤백 종료 코드 1 반환"
assert_contains "$OUT_INIT" "초기 배포" "초기 배포 안내 메시지 출력"

# ------------------------------------------------------------------------------
# 2. Legacy JAR 1차 설치 -> 2차 덮어쓰기 -> 스냅샷 생성 및 롤백 복원 테스트
# ------------------------------------------------------------------------------
echo "▶ Test 2: Legacy JAR 재배포 스냅샷 생성 및 롤백 검증"

PKG_V1="$TMP_ROOT/pkg_v1"
PKG_V2="$TMP_ROOT/pkg_v2"
DEST_APP="$MOCK_HOME/apps/mytestapp"
LOG_APP="$MOCK_HOME/logs/mytestapp"

for ver in v1 v2; do
    PKG="$TMP_ROOT/pkg_${ver}"
    mkdir -p "$PKG/deploy" "$PKG/bin" "$PKG/libs" "$PKG/config"
    cp "$INSTALL_SCRIPT" "$PKG/deploy/install_service.sh"
    cp "$ROLLBACK_SCRIPT" "$PKG/deploy/rollback_service.sh"
    cp "$REPO_ROOT/scripts/deploy/uninstall_service.sh" "$PKG/deploy/"
    cp "$REPO_ROOT/scripts/common/bootstrap.sh" "$PKG/deploy/"
    cp "$REPO_ROOT/scripts/common/utils.sh" "$PKG/deploy/"
    cp "$REPO_ROOT/scripts/service/start.sh" "$PKG/bin/"
    cp "$REPO_ROOT/scripts/service/stop.sh" "$PKG/bin/"
    cp "$REPO_ROOT/scripts/service/status.sh" "$PKG/bin/"
    sed -i.bak 's/@appName@/mytestapp/g' "$PKG/deploy/install_service.sh" "$PKG/deploy/rollback_service.sh" "$PKG/bin/start.sh"
    rm -f "$PKG/deploy/"*.bak "$PKG/bin/"*.bak
    echo "jar-${ver}" > "$PKG/libs/app-${ver}.jar"
    cat <<EOF > "$PKG/config/application.yml"
server:
  port: 8080
app:
  version: ${ver}
EOF
done

# 2-1. 1차 설치 (초기 배포이므로 스냅샷 없어야 함)
printf "%s\n%s\n" "$DEST_APP" "$LOG_APP" | bash "$PKG_V1/deploy/install_service.sh" --user --mode=legacy --type=jar >/dev/null 2>&1
assert_file_exists "$DEST_APP/libs/app-v1.jar" "1차 설치 JAR 존재"
assert_file_exists "$DEST_APP/bin/rollback_service.sh" "설치 경로 bin/rollback_service.sh 배치 확인"
assert_file_not_exists "$DEST_APP/.rollback" "초기 배포 시 .rollback 미생성"

# 2-2. 2차 덮어쓰기 설치 (v1 스냅샷이 생성되어야 함)
bash "$PKG_V2/deploy/install_service.sh" --user --mode=legacy --type=jar >/dev/null 2>&1
assert_file_exists "$DEST_APP/libs/app-v2.jar" "2차 설치 JAR 존재"
assert_file_exists "$DEST_APP/.rollback/latest" "재배포 시 .rollback/latest 생성"

LATEST_REV=$(basename "$(readlink "$DEST_APP/.rollback/latest")")
assert_file_exists "$DEST_APP/.rollback/$LATEST_REV/meta.env" "스냅샷 meta.env 생성"
assert_file_exists "$DEST_APP/.rollback/$LATEST_REV/app_files.tar.gz" "스냅샷 app_files.tar.gz 생성"
assert_file_exists "$DEST_APP/.rollback/$LATEST_REV/system/service.unit" "스냅샷 service.unit 백업"

# 2-3. --list 출력 확인
LIST_OUT=$(bash "$DEST_APP/bin/rollback_service.sh" --list 2>&1)
assert_contains "$LIST_OUT" "$LATEST_REV" "--list 출력에 리비전 ID 포함"
assert_contains "$LIST_OUT" "legacy" "--list 출력에 배포 방식 포함"

# 2-4. install_service.sh --rollback -y 로 롤백 실행
bash "$PKG_V2/deploy/install_service.sh" --rollback --yes >/dev/null 2>&1
assert_file_exists "$DEST_APP/libs/app-v1.jar" "롤백 후 v1 JAR 복원"
assert_file_not_exists "$DEST_APP/libs/app-v2.jar" "롤백 후 v2 JAR 제거"
VER_IN_YML=$(grep "version:" "$DEST_APP/config/application.yml" | awk '{print $2}')
assert_equals "v1" "$VER_IN_YML" "롤백 후 application.yml v1 복원"
assert_file_not_exists "$DEST_APP/.rollback/$LATEST_REV" "적용 완료된 스냅샷 소비(정리)"

# ------------------------------------------------------------------------------
# 3. MAX_ROLLBACK_COUNT Pruning 테스트
# ------------------------------------------------------------------------------
echo "▶ Test 3: MAX_ROLLBACK_COUNT 초과 스냅샷 자동 정리 검증"
export MAX_ROLLBACK_COUNT=2
bash "$PKG_V2/deploy/install_service.sh" --user --mode=legacy --type=jar >/dev/null 2>&1
sleep 1
bash "$PKG_V2/deploy/install_service.sh" --user --mode=legacy --type=jar >/dev/null 2>&1
sleep 1
bash "$PKG_V2/deploy/install_service.sh" --user --mode=legacy --type=jar >/dev/null 2>&1

SNAP_COUNT=$(find "$DEST_APP/.rollback" -maxdepth 1 -mindepth 1 -type d -name "rev_*" | wc -l | tr -d ' ')
assert_equals "2" "$SNAP_COUNT" "MAX_ROLLBACK_COUNT=2 유지 확인"

# ------------------------------------------------------------------------------
# 4. Docker 모드 스냅샷(docker tag) 및 롤백(docker tag 복원) 테스트
# ------------------------------------------------------------------------------
echo "▶ Test 4: Docker 모드 스냅샷 및 롤백 검증"
DOCKER_APP="$MOCK_HOME/apps/mydockerapp"
PKG_D1="$TMP_ROOT/pkg_d1"
mkdir -p "$PKG_D1/deploy" "$PKG_D1/docker" "$PKG_D1/bin" "$PKG_D1/config"
cp "$INSTALL_SCRIPT" "$PKG_D1/deploy/install_service.sh"
cp "$ROLLBACK_SCRIPT" "$PKG_D1/deploy/rollback_service.sh"
cp "$REPO_ROOT/scripts/deploy/uninstall_service.sh" "$PKG_D1/deploy/"
cp "$REPO_ROOT/scripts/common/bootstrap.sh" "$PKG_D1/deploy/"
cp "$REPO_ROOT/scripts/common/utils.sh" "$PKG_D1/deploy/"
cp "$REPO_ROOT/scripts/service/start.sh" "$PKG_D1/bin/"
cp "$REPO_ROOT/scripts/service/stop.sh" "$PKG_D1/bin/"
cp "$REPO_ROOT/scripts/service/status.sh" "$PKG_D1/bin/"
sed -i.bak 's/@appName@/mydockerapp/g; s/@dockerImage@/mydockerapp:1.0.0/g' "$PKG_D1/deploy/install_service.sh" "$PKG_D1/deploy/rollback_service.sh" "$PKG_D1/bin/start.sh"
rm -f "$PKG_D1/deploy/"*.bak "$PKG_D1/bin/"*.bak

cat <<'EOF' > "$PKG_D1/docker/docker-compose.yml"
services:
  app:
    image: ${DOCKER_IMAGE}
    container_name: mydockerapp
EOF
echo "app: v1" > "$PKG_D1/config/app.txt"

# 1차 Docker 설치
printf "%s\n%s\n" "$DOCKER_APP" "$MOCK_HOME/logs/mydockerapp" | bash "$PKG_D1/deploy/install_service.sh" --user --mode=docker >/dev/null 2>&1
assert_file_exists "$DOCKER_APP/docker-compose.yml" "Docker 1차 설치 완료"

# 2차 Docker 덮어쓰기
: > "$DOCKER_LOG"
echo "app: v2" > "$PKG_D1/config/app.txt"
bash "$PKG_D1/deploy/install_service.sh" --user --mode=docker >/dev/null 2>&1
DOCKER_CALLS=$(cat "$DOCKER_LOG")
assert_contains "$DOCKER_CALLS" "tag sha256:old_image_id_1234 mydockerapp:rollback-" "재배포 시 이전 Docker 이미지 태그 백업 호출"

# Docker 롤백 실행
: > "$DOCKER_LOG"
bash "$DOCKER_APP/bin/rollback_service.sh" --yes >/dev/null 2>&1
ROLLBACK_DOCKER_CALLS=$(cat "$DOCKER_LOG")
assert_contains "$ROLLBACK_DOCKER_CALLS" "tag mydockerapp:rollback-" "롤백 시 백업 이미지 태그를 원래 태그로 복원"
RESTORED_TXT=$(cat "$DOCKER_APP/config/app.txt")
assert_equals "app: v1" "$RESTORED_TXT" "Docker 롤백 후 config/app.txt 복원"

# ------------------------------------------------------------------------------
# 5. System Mode(IS_USER_MODE=0) 스냅샷 비-root 실행 차단 테스트
# ------------------------------------------------------------------------------
echo "▶ Test 5: System Mode 스냅샷 비-root 롤백 차단 검증"
if [ "$EUID" -ne 0 ]; then
    SYS_APP="$TMP_ROOT/sys_app"
    mkdir -p "$SYS_APP/.rollback/rev_20261127_000000/system" "$SYS_APP/bin"
    cp "$ROLLBACK_SCRIPT" "$SYS_APP/bin/rollback_service.sh"
    cp "$REPO_ROOT/scripts/common/bootstrap.sh" "$SYS_APP/bin/"
    cp "$REPO_ROOT/scripts/common/utils.sh" "$SYS_APP/bin/"
    tar -czf "$SYS_APP/.rollback/rev_20261127_000000/app_files.tar.gz" -C "$SYS_APP" bin
    cat <<EOF > "$SYS_APP/.rollback/rev_20261127_000000/meta.env"
REV_ID="rev_20261127_000000"
CREATED_AT="2026-11-27 00:00:00"
APP_NAME="sysapp"
DEST_DIR="$SYS_APP"
LOG_PATH="$TMP_ROOT/syslog"
REAL_USER="root"
SERVICE_GROUP="root"
DEPLOY_MODE="legacy"
RUNTIME_ENGINE="jar"
IS_USER_MODE="0"
INIT_SYSTEM="systemd-system"
EOF
    ln -sfn "rev_20261127_000000" "$SYS_APP/.rollback/latest"

    set +e
    SYS_OUT=$(bash "$SYS_APP/bin/rollback_service.sh" --yes 2>&1)
    SYS_RC=$?
    set -e
    assert_equals "1" "$SYS_RC" "비-root 환경에서 System Mode 롤백 차단(exit 1)"
    assert_contains "$SYS_OUT" "sudo" "sudo 필요 안내 출력"
fi

export HOME="$ORIG_HOME"
export PATH="$ORIG_PATH"

echo "================================================================"
echo "📊 Rollback Test Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "================================================================"

if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
fi
