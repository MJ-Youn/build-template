#!/bin/bash
# ==============================================================================
# File: utils.sh
# Description: 공통 유틸리티 함수 모음 (로깅, 유효성 검사, 환경 설정 등)
# Author: 윤명준 (MJ Yune)
# Since: 2026-02-11
# ==============================================================================

# --- [Color Definitions] ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- [Logging API] ---

# @description 헤더 스타일의 로그 출력
# @param $1 메시지
# @param $2 아이콘 (Optional, Default: 🚀)
log_header() {
    local message="$1"
    local icon="${2:-🚀}"
    echo -e "\n${BOLD}${BLUE}================================================================${NC}"
    echo -e "${BOLD}${BLUE}${icon}  $message ${NC}"
    echo -e "${BOLD}${BLUE}================================================================${NC}"
}

# @description 단계 진행 로그 출력
# @param $1 메시지
log_step() { 
    echo -e "${BOLD}${CYAN}➡️  $1${NC}" 
}

# @description 일반 정보 로그 출력
# @param $1 메시지
log_info() { 
    echo -e "   ℹ️  $1" 
}

# @description 성공 로그 출력
# @param $1 메시지
log_success() { 
    echo -e "${BOLD}${GREEN}✅  $1${NC}" 
}

# @description 경고 로그 출력
# @param $1 메시지
log_warning() { 
    echo -e "${BOLD}${YELLOW}⚠️  $1${NC}" 
}

# @description 에러 로그 출력
# @param $1 메시지
log_error() { 
    echo -e "${BOLD}${RED}❌  $1${NC}" 
}

# --- [Validation API] ---

# @description 경로 안전성 검사 (시스템 중요 디렉토리 변조 및 삭제 방지)
# @param $1 검사할 경로
# @return 0: 안전함, 1: 위험함
is_safe_path() {
    local path=$1
    if [ -z "$path" ]; then
        return 1
    fi

    # 경로 정규화 (심볼릭 링크 해제 및 .. 처리)
    local normalized_path
    normalized_path=$(readlink -f "$path" 2>/dev/null || echo "$path")

    # 1. 절대 경로 여부 확인 및 루트 디렉토리 거부
    if [[ ! "$normalized_path" =~ ^/ ]] || [[ "$normalized_path" == "/" ]]; then
        return 1
    fi

    # 2. 삭제/변조 금지된 중요 시스템 경로 목록 (정확한 일치)
    case "$normalized_path" in
        "/bin" | "/boot" | "/dev" | "/etc" | "/home" | "/lib" | "/lib64" | \
        "/media" | "/mnt" | "/opt" | "/proc" | "/root" | "/run" | "/sbin" | \
        "/srv" | "/sys" | "/tmp" | "/usr" | "/var" | "/usr/bin" | "/usr/sbin" | \
        "/usr/lib" | "/var/log" | "/usr/local/bin" | "/usr/local/sbin" | "/usr/local/lib" | \
        "/log")
            return 1 # Not safe
            ;;
    esac

    # 3. 중요 시스템 경로의 하위 디렉토리 거부 (Privilege Escalation 방지)
    # /opt/myapp 이나 /var/log/myapp 등은 허용하되, 시스템 바이너리/설정 경로는 보호
    case "$normalized_path" in
        "/bin/"* | "/boot/"* | "/dev/"* | "/etc/"* | "/lib/"* | "/lib64/"* | \
        "/proc/"* | "/root/"* | "/run/"* | "/sbin/"* | "/sys/"* | "/usr/bin/"* | \
        "/usr/sbin/"* | "/usr/lib/"* | "/usr/local/bin/"* | "/usr/local/sbin/"* | \
        "/usr/local/lib/"*)
            return 1 # Not safe
            ;;
    esac

    return 0 # Safe
}

# --- [System API] ---

# @description Docker Compose 명령어 감지 (docker compose vs docker-compose)
# @param $1 에러 발생 시 종료 여부 (true/false, default: false)
detect_docker_compose_cmd() {
    local fail_on_error="${1:-false}"

    if [ -n "$DOCKER_COMPOSE_CMD" ]; then
        return 0
    fi

    local DOCKER_BIN
    DOCKER_BIN=$(command -v docker)
    if [ -z "$DOCKER_BIN" ]; then
        if [ "$fail_on_error" = "true" ]; then
            log_error "Docker 실행 파일을 찾을 수 없습니다."
            exit 1
        else
            log_warning "Docker 실행 파일을 찾을 수 없습니다. 컨테이너 작업을 건너뜁니다."
            return 1
        fi
    fi

    if $DOCKER_BIN compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="$DOCKER_BIN compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD=$(command -v docker-compose)
    else
        if [ "$fail_on_error" = "true" ]; then
            log_error "Docker Compose를 찾을 수 없습니다."
            exit 1
        else
            log_warning "Docker Compose를 찾을 수 없어 컨테이너 작업을 건너뜁니다."
            return 1
        fi
    fi
    return 0
}

# @description 사용자 쉘 프로필에 PATH 추가
# @param $1 프로필 파일 경로 (예: ~/.bashrc)
# @param $2 추가할 bin 경로
# @return 0: 추가됨, 1: 이미 존재하거나 실패
add_path_to_profile() {
    local profile="$1"
    local bin_path="$2"
    local app_name="${APP_NAME:-Application}" # 전역 변수 APP_NAME 활용, 없으면 Default
    
    if [ -f "$profile" ]; then
        # 경로가 이미 파일 내에 존재하는지 확인 (단순 문자열 매칭)
        if ! grep -q "$bin_path" "$profile"; then
            log_info "$profile 에 PATH 추가 중..."
            echo -e "\n# Added by $app_name installer" >> "$profile"
            echo "export PATH=\"\$PATH:$bin_path\"" >> "$profile"
            
            # 권한 복구 (sudo로 실행되었을 경우 owner 유지)
            # REAL_USER, SERVICE_GROUP은 호출하는 스크립트에서 정의되어야 함
            if [ -n "$REAL_USER" ] && [ -n "$SERVICE_GROUP" ]; then
                 chown $REAL_USER:$SERVICE_GROUP "$profile"
            fi
            
            log_success "$profile 업데이트 완료"
            return 0
        fi
    fi
    return 1
}

# --- [Wait API] ---

# @description 특정 조건이 만족될 때까지 대기 (Polling)
# @param $1 조건 확인을 위한 명령어 (문자열)
# @param $2 최대 대기 시간 (초, 기본값: 5)
# @param $3 확인 주기 (초, 기본값: 0.2)
# @return 0: 성공, 1: 타임아웃
wait_for_condition() {
    local condition_cmd="$1"
    local timeout="${2:-5}"
    local interval="${3:-0.2}"
    local start_time=$SECONDS

    while true; do
        if eval "$condition_cmd" >/dev/null 2>&1; then
            return 0
        fi

        if (( SECONDS - start_time >= timeout )); then
            return 1
        fi

        sleep "$interval"
    done
}
