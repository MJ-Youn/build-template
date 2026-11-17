#!/bin/bash
# ==============================================================================
# File: utils.sh
# Description: 공통 유틸리티 함수 모음 (로깅, 유효성 검사, 환경 설정 등)
# Author: 윤명준 (MJ Yun)
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

# @description Docker 실행 런타임 모드 감지 (Rootless / Docker 그룹 / Sudo 필요 / 불가)
#              결과를 전역 변수 DOCKER_RUNTIME_MODE, DOCKER_CMD에 저장합니다.
#              DOCKER_RUNTIME_MODE: rootless | rootful_group | rootful_sudo | unavailable
# @return 0: 실행 가능한 Docker 환경 감지(rootless/rootful_group/rootful_sudo), 1: 미설치 또는 데몬 미실행
detect_docker_runtime_mode() {
    DOCKER_RUNTIME_MODE="unavailable"
    DOCKER_CMD="docker"

    local docker_bin
    docker_bin=$(command -v docker 2>/dev/null)
    if [ -z "$docker_bin" ]; then
        return 1
    fi

    local sec_opts=""
    local err_out=""
    local tmp_err
    tmp_err=$(mktemp 2>/dev/null || echo "/tmp/docker_detect_$$.err")

    # 1. 현재 세션 환경 그대로 docker info 조회 (Rootless 또는 docker 그룹/root 권한)
    if sec_opts=$("$docker_bin" info --format '{{.SecurityOptions}}' 2>"$tmp_err"); then
        rm -f "$tmp_err"
        if echo "$sec_opts" | grep -qi "rootless"; then
            DOCKER_RUNTIME_MODE="rootless"
        else
            DOCKER_RUNTIME_MODE="rootful_group"
        fi
        DOCKER_CMD="docker"
        return 0
    fi
    err_out=$(cat "$tmp_err" 2>/dev/null)
    rm -f "$tmp_err"

    # 2. Rootless 소켓이 존재하지만 DOCKER_HOST 미설정으로 실패한 경우 소켓 자동 보정 후 재확인
    local uid_val
    uid_val=$(id -u 2>/dev/null)
    local rootless_sock="${XDG_RUNTIME_DIR:-/run/user/$uid_val}/docker.sock"
    if [ -n "$uid_val" ] && [ "$uid_val" -ne 0 ] && [ -S "$rootless_sock" ]; then
        if sec_opts=$(DOCKER_HOST="unix://$rootless_sock" "$docker_bin" info --format '{{.SecurityOptions}}' 2>/dev/null); then
            if echo "$sec_opts" | grep -qi "rootless"; then
                export DOCKER_HOST="unix://$rootless_sock"
                DOCKER_RUNTIME_MODE="rootless"
                DOCKER_CMD="docker"
                return 0
            fi
        fi
    fi

    # 3. 일반 Docker 데몬 소켓 접근 권한 부족 또는 sudo -n docker info 성공 시 sudo 필요 모드로 판별
    if echo "$err_out" | grep -qi "permission denied"; then
        DOCKER_RUNTIME_MODE="rootful_sudo"
        DOCKER_CMD="sudo docker"
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n "$docker_bin" info >/dev/null 2>&1; then
        DOCKER_RUNTIME_MODE="rootful_sudo"
        DOCKER_CMD="sudo docker"
        return 0
    fi

    return 1
}

# @description docker-compose.yml의 각 서비스에 user: "0:0" 설정이 누락되어 있으면 자동 추가
# @param $1 docker-compose.yml 파일 경로
# @return 0: 정상 처리(추가됨 또는 이미 존재), 1: 파일 없음 또는 처리 실패
ensure_compose_user_setting() {
    local compose_file="$1"
    if [ -z "$compose_file" ] || [ ! -f "$compose_file" ]; then
        return 1
    fi

    local tmp_file
    tmp_file=$(mktemp 2>/dev/null || echo "${compose_file}.tmp.$$")

    awk '
    function flush_service_block(    i, insert_after, line) {
        if (!in_service || svc_count == 0) {
            svc_count = 0
            in_service = 0
            has_user = 0
            prop_indent = ""
            return
        }
        if (has_user || prop_indent == "") {
            for (i = 1; i <= svc_count; i++) {
                print svc_lines[i]
            }
        } else {
            insert_after = 0
            # container_name 또는 image 라인 직후 삽입을 우선 탐색
            for (i = 1; i <= svc_count; i++) {
                line = svc_lines[i]
                if (line ~ "^" prop_indent "container_name:([[:space:]]|$)") {
                    insert_after = i
                    break
                }
                if (insert_after == 0 && line ~ "^" prop_indent "image:([[:space:]]|$)") {
                    insert_after = i
                }
            }
            if (insert_after == 0) {
                insert_after = 1
            }
            for (i = 1; i <= svc_count; i++) {
                print svc_lines[i]
                if (i == insert_after) {
                    print prop_indent "user: \"0:0\""
                }
            }
        }
        svc_count = 0
        in_service = 0
        has_user = 0
        prop_indent = ""
    }
    BEGIN {
        in_services = 0
        services_indent = 0
        in_service = 0
        svc_indent = -1
        svc_count = 0
        has_user = 0
        prop_indent = ""
    }
    {
        if (!in_services) {
            print $0
            if ($0 ~ /^[ ]*services:[[:space:]]*(#.*)?$/) {
                match($0, /^[ ]*/)
                services_indent = RLENGTH
                in_services = 1
            }
            next
        }

        # 빈 줄 또는 주석 줄 처리
        if ($0 ~ /^[[:space:]]*(#.*)?$/) {
            if (in_service) {
                svc_lines[++svc_count] = $0
            } else {
                print $0
            }
            next
        }

        match($0, /^[ ]*/)
        indent_len = RLENGTH

        # services 블록을 벗어난 최상위 섹션 진입 시 버퍼 출력 후 종료
        if (indent_len <= services_indent) {
            flush_service_block()
            in_services = 0
            print $0
            next
        }

        # 새 서비스 블록 시작 판별 (services 바로 하위 레벨 키)
        if (!in_service || indent_len == svc_indent) {
            flush_service_block()
            in_service = 1
            svc_indent = indent_len
            has_user = 0
            prop_indent = ""
            svc_lines[++svc_count] = $0
            next
        }

        # 현재 서비스 내부 속성 처리
        if (prop_indent == "") {
            prop_indent = substr($0, 1, indent_len)
        }
        if (substr($0, 1, indent_len) == prop_indent && $0 ~ "^" prop_indent "user:[[:space:]]*") {
            has_user = 1
        }
        svc_lines[++svc_count] = $0
    }
    END {
        flush_service_block()
    }
    ' "$compose_file" > "$tmp_file"

    if [ $? -eq 0 ] && [ -s "$tmp_file" ]; then
        mv "$tmp_file" "$compose_file"
        return 0
    fi

    rm -f "$tmp_file"
    return 1
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

# --- [Environment Detection API] ---

# @description 현재 실행 환경이 Docker 컨테이너 내부인지 정밀 감지
# @return 0: Docker 컨테이너 내부, 1: 호스트 환경
is_docker_container() {
    # 0. 컨테이너 특유의 식별 파일 확인
    if [ -f "/.dockerenv" ]; then
        return 0
    fi

    # 1. 파일 시스템 증거 (mountinfo에 overlay/docker/containerd 흔적 확인)
    local has_mount_evidence=false
    if grep -qE '(docker|overlay|containerd)' /proc/1/mountinfo 2>/dev/null; then
        has_mount_evidence=true
    fi

    # 2. 프로세스 증거 (PID 1이 systemd/init이 아닌지 확인)
    local has_pid_evidence=false
    if [ -f /proc/1/comm ]; then
        local pid1_comm
        pid1_comm=$(cat /proc/1/comm 2>/dev/null)
        if [[ "$pid1_comm" != "systemd" && "$pid1_comm" != "init" ]]; then
            has_pid_evidence=true
        fi
    fi

    # 3. 스크립트 단독 실행 증거 (컨테이너 Entrypoint에서 직접 실행된 경우 PID가 1임)
    if [ "$$" -eq 1 ]; then
        return 0
    fi

    # ⚖️ 최종 판별 (마운트 증거와 PID 1 증거가 모두 참이면 컨테이너)
    if [ "$has_mount_evidence" = true ] && [ "$has_pid_evidence" = true ]; then
        return 0
    fi

    return 1
}
