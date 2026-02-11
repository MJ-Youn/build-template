#!/bin/bash

# --- [Color & Style Definition] ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- [Logging Functions] ---
log_header() {
    echo -e "\n${BOLD}${RED}================================================================${NC}"
    echo -e "${BOLD}${RED}🗑️  $1 ${NC}"
    echo -e "${BOLD}${RED}================================================================${NC}"
}
log_step() { echo -e "${BOLD}${CYAN}➡️  $1${NC}"; }
log_info() { echo -e "   ℹ️  $1"; }
log_success() { echo -e "${BOLD}${GREEN}✅  $1${NC}"; }
log_warning() { echo -e "${BOLD}${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${BOLD}${RED}❌  $1${NC}"; }

# --- [Path Validation Function] ---
is_safe_path() {
    local path=$1
    if [ -z "$path" ]; then
        return 1
    fi

    # Normalize path (resolve .. and symlinks)
    local normalized_path
    normalized_path=$(readlink -f "$path" 2>/dev/null || echo "$path")

    # List of sensitive system directories (absolute paths)
    local sensitive_paths=(
        "/" "/bin" "/boot" "/dev" "/etc" "/home" "/lib" "/lib64"
        "/media" "/mnt" "/opt" "/proc" "/root" "/run" "/sbin"
        "/srv" "/sys" "/tmp" "/usr" "/var" "/usr/bin" "/usr/sbin"
        "/usr/lib" "/var/log" "/usr/local/bin" "/usr/local/sbin" "/usr/local/lib"
    )

    for p in "${sensitive_paths[@]}"; do
        if [[ "$normalized_path" == "$p" ]]; then
            return 1 # Not safe
        fi
    done

    # Ensure it's not one of the root level directories (e.g., /etc, /bin)
    if [[ "$normalized_path" =~ ^/[^/]+$ ]]; then
        return 1 # Not safe
    fi

    # Ensure it's an absolute path and not just /
    if [[ ! "$normalized_path" =~ ^/ ]] || [[ "$normalized_path" == "/" ]]; then
        return 1 # Not safe
    fi

    return 0 # Safe
}

# --- [Script Start] ---

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
  log_error "이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# uninstall_service.sh는 bin 디렉토리에 위치하므로 상위 디렉토리가 프로젝트 루트
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP_NAME="@appName@"

# 실행 유저 확인
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")

log_header "서비스 삭제 시작 ($APP_NAME)"

log_warning "이 작업은 되돌릴 수 없습니다."
log_info "설치 디렉토리: $PROJECT_ROOT"
read -p "   ❓ 정말로 삭제하시겠습니까? (y/N): " CONFIRM
CONFIRM=${CONFIRM:-N}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log_info "삭제가 취소되었습니다."
    exit 0
fi

# 1. 서비스 중지 및 비활성화
log_step "서비스 중지 및 비활성화..."

SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"
INIT_SCRIPT="/etc/init.d/$APP_NAME"

if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet $APP_NAME; then
        log_info "서비스 중지 중..."
        systemctl stop $APP_NAME
    fi
    if systemctl is-enabled --quiet $APP_NAME 2>/dev/null; then
        log_info "서비스 비활성화 중..."
        systemctl disable $APP_NAME
    fi
    
    if [ -f "$SERVICE_FILE" ]; then
        log_info "서비스 파일 삭제: $SERVICE_FILE"
        rm "$SERVICE_FILE"
        systemctl daemon-reload
    fi
elif [ -f "$INIT_SCRIPT" ]; then
    service $APP_NAME stop
    rm "$INIT_SCRIPT"
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --del $APP_NAME
    elif command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d -f $APP_NAME remove
    fi
fi

log_success "서비스가 시스템에서 제거되었습니다."

# 1.5 Cron 작업 삭제
CRON_FILE="/etc/cron.d/$APP_NAME"
if [ -f "$CRON_FILE" ]; then
    log_info "Cron 작업 삭제: $CRON_FILE"
    rm "$CRON_FILE"
    log_success "Cron 작업이 제거되었습니다."
fi

# 2. 로그 삭제 확인
# 로그 경로 파악 (.app-env.properties 읽기)
LOG_PATH=""
PROP_FILE="$SCRIPT_DIR/.app-env.properties"
if [ -f "$PROP_FILE" ]; then
    # properties 파일에서 LOG_PATH 추출 (eval 없이 간단히)
    # LOG_PATH="/opt/..." 형식이므로 cut 등을 사용
    LOG_PATH_Line=$(grep "^LOG_PATH=" "$PROP_FILE")
    if [ -n "$LOG_PATH_Line" ]; then
        # 값 부분만 추출하고 따옴표 제거
        LOG_PATH=$(echo "$LOG_PATH_Line" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    fi
fi
LOG_PATH="${LOG_PATH:-$PROJECT_ROOT/log}"

log_step "로그 데이터 처리"
log_info "감지된 로그 경로: $LOG_PATH"

if [ -d "$LOG_PATH" ]; then
    read -p "   ❓ 로그 파일도 함께 삭제하시겠습니까? (y/N): " DEL_LOG
    DEL_LOG=${DEL_LOG:-N}
    
    if [[ "$DEL_LOG" =~ ^[Yy]$ ]]; then
        if is_safe_path "$LOG_PATH"; then
            # 설치 경로 외부에 있는 경우 소유자 확인으로 추가 보안 계층 제공
            N_LOG_PATH=$(readlink -f "$LOG_PATH" 2>/dev/null || echo "$LOG_PATH")
            N_PROJECT_ROOT=$(readlink -f "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
            IS_INSIDE_PROJECT=0
            if [[ "$N_LOG_PATH" == "$N_PROJECT_ROOT" ]] || [[ "$N_LOG_PATH" == "$N_PROJECT_ROOT"/* ]]; then
                IS_INSIDE_PROJECT=1
            fi

            if [ $IS_INSIDE_PROJECT -eq 1 ] || [ "$(stat -c '%U' "$N_LOG_PATH" 2>/dev/null)" == "$REAL_USER" ]; then
                log_info "로그 디렉토리 삭제 중..."
                rm -rf "$LOG_PATH"
                log_success "로그 파일이 삭제되었습니다."
            else
                log_error "로그 경로가 설치 경로 외부에 있으며 소유자가 실행 유저와 일치하지 않습니다. 삭제를 건너뜁니다."
                log_info "해당 로그 경로는 수동으로 확인 후 삭제해 주세요: $LOG_PATH"
            fi
        else
            log_error "위험한 로그 경로가 감지되었습니다: $LOG_PATH. 로그 삭제를 건너뜁니다."
        fi
    else
        log_info "로그 파일은 보존되었습니다."
    fi
else
    log_info "로그 디렉토리가 존재하지 않습니다."
fi

# 3. 유틸리티 스크립트 삭제
log_step "유틸리티 스크립트 정리"
TAIL_SCRIPT="$USER_HOME/bin/tail-log-${APP_NAME}.sh"
if [ -f "$TAIL_SCRIPT" ]; then
    log_info "로그 확인 스크립트 삭제: $TAIL_SCRIPT"
    rm "$TAIL_SCRIPT"
fi

# 4. 설치 디렉토리 삭제 (자기 자신 포함)
log_step "설치 파일 삭제"
log_info "설치 디렉토리 제거: $PROJECT_ROOT"

# 주의: PROJECT_ROOT가 시스템 중요 디렉토리인지 체크
if ! is_safe_path "$PROJECT_ROOT"; then
    log_error "잘못된 또는 위험한 설치 경로 감지 ($PROJECT_ROOT). 삭제를 중단합니다."
    exit 1
fi

# 현재 스크립트($0)가 삭제되면 실행이 멈출 수 있으므로, 
# 백그라운드세 subshell로 삭제를 실행하고 종료하거나, 
# 가장 마지막에 rm -rf 수행.
rm -rf "$PROJECT_ROOT"

log_header "삭제 완료"
echo -e "   ${GREEN}모든 구성 요소가 제거되었습니다. 이용해 주셔서 감사합니다.${NC}"
exit 0
