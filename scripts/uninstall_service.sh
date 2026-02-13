#!/bin/bash
# ==============================================================================
# File: uninstall_service.sh
# Description: 서비스 제거 스크립트 (Systemd/SysVinit 지원)
# Author: 윤명준 (MJ Yune)
# Since: 2026-02-11
# ==============================================================================

# --- [Script Init] ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# utils.sh 로드
UTILS_PATH="$SCRIPT_DIR/utils.sh"
if [ -f "$UTILS_PATH" ]; then
    source "$UTILS_PATH"
else
    echo "Warning: utils.sh not found at $UTILS_PATH. Using basic logging."
    # Define basic logging functions (Fallback)
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'

    log_header() { echo -e "\n${BOLD}${RED}=== $1 ===${NC}"; }
    log_step() { echo -e "\n${BOLD}➡️  $1${NC}"; }
    log_info() { echo -e "   ${CYAN}ℹ️  $1${NC}"; }
    log_success() { echo -e "${GREEN}✅  $1${NC}"; }
    log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
    log_error() { echo -e "${RED}❌  $1${NC}"; exit 1; }
    is_safe_path() { return 0; } # Fallback: always safe
fi

# --- [Constants & Variables] ---
APP_NAME="@appName@"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
# 환경 변수 파일 (로그 경로 등 확인용)
PROP_FILE="$SCRIPT_DIR/.app-env.properties"

# 실행 유저 확인
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")

# --- [Functions] ---

# @description 서비스 제거 메인 함수
uninstall_service() {
    log_header "서비스 삭제 시작 ($APP_NAME)" "🗑️"

    log_warning "이 작업은 되돌릴 수 없습니다."
    log_info "설치 디렉토리: $INSTALL_DIR"
    
    # 사용자 확인
    confirm_uninstall

    # 1. 서비스 중지 및 비활성화
    stop_and_disable_service

    # 2. Cron 작업 삭제
    remove_cron

    # 3. 로그 삭제 확인
    remove_logs

    # 4. 유틸리티 스크립트 삭제
    remove_utility_scripts

    # 5. 설치 디렉토리 삭제
    remove_install_dir

    log_header "삭제 완료"
    echo -e "   ${GREEN}모든 구성 요소가 제거되었습니다. 이용해 주셔서 감사합니다.${NC}"
}

# @description 사용자에게 삭제 확인 요청
confirm_uninstall() {
    read -p "   ❓ 정말로 삭제하시겠습니까? (y/N): " CONFIRM
    CONFIRM=${CONFIRM:-N}

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "삭제가 취소되었습니다."
        exit 0
    fi
}

# @description 서비스 중지 및 비활성화
stop_and_disable_service() {
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
}

# @description Cron 작업 제거
remove_cron() {
    CRON_FILE="/etc/cron.d/$APP_NAME"
    if [ -f "$CRON_FILE" ]; then
        log_info "Cron 작업 삭제: $CRON_FILE"
        rm "$CRON_FILE"
        log_success "Cron 작업이 제거되었습니다."
    fi
}

# @description 로그 파일 및 디렉토리 제거 확인
remove_logs() {
    log_step "로그 데이터 처리"

    # 로그 경로 파악 (.app-env.properties 읽기)
    LOG_PATH=""
    if [ -f "$PROP_FILE" ]; then
        LOG_PATH_Line=$(grep "^LOG_PATH=" "$PROP_FILE")
        if [ -n "$LOG_PATH_Line" ]; then
            LOG_PATH=$(echo "$LOG_PATH_Line" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
    fi
    # 기본값
    LOG_PATH="${LOG_PATH:-$INSTALL_DIR/log}"

    if [ -d "$LOG_PATH" ]; then
        log_info "감지된 로그 경로: $LOG_PATH"
        read -p "   ❓ 로그 파일도 함께 삭제하시겠습니까? (y/N): " DEL_LOG
        DEL_LOG=${DEL_LOG:-N}
        
        if [[ "$DEL_LOG" =~ ^[Yy]$ ]]; then
            if is_safe_path "$LOG_PATH"; then
                 log_info "로그 디렉토리 삭제 중..."
                 rm -rf "$LOG_PATH"
                 log_success "로그 파일이 삭제되었습니다."
            else
                log_error "위험한 로그 경로가 감지되었습니다: $LOG_PATH. 로그 삭제를 건너뜁니다."
            fi
        else
            log_info "로그 파일은 보존되었습니다."
        fi
    else
        log_info "로그 디렉토리가 존재하지 않습니다."
    fi
}

# @description 유틸리티 스크립트 제거 (tail-log 등)
remove_utility_scripts() {
    log_step "유틸리티 스크립트 정리"
    TAIL_SCRIPT="$USER_HOME/bin/tail-log-${APP_NAME}.sh"
    if [ -f "$TAIL_SCRIPT" ]; then
        log_info "로그 확인 스크립트 삭제: $TAIL_SCRIPT"
        rm "$TAIL_SCRIPT"
    fi
}

# @description 설치 디렉토리 제거
remove_install_dir() {
    log_step "설치 파일 삭제"
    log_info "설치 디렉토리 제거: $INSTALL_DIR"
    
    # 주의: INSTALL_DIR가 시스템 중요 디렉토리인지 체크
    if ! is_safe_path "$INSTALL_DIR"; then
        log_error "잘못된 또는 위험한 설치 경로 감지 ($INSTALL_DIR). 삭제를 중단합니다."
        exit 1
    fi

    rm -rf "$INSTALL_DIR"
}

# --- [Execution] ---

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
  echo "Error: 이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

uninstall_service
