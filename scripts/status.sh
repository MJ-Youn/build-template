#!/bin/bash
# ==============================================================================
# File: status.sh
# Description: 서비스 상태 확인 스크립트
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
    # Fallback
    echo "Warning: utils.sh not found at $UTILS_PATH"
    log_info() { echo "   ℹ️  $1"; }
    log_error() { echo "❌  $1"; }
    log_success() { echo "✅  $1"; }
fi

# --- [Constants & Variables] ---
APP_NAME="@appName@"
PID_FILE="$SCRIPT_DIR/application.pid"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
LOG_PATH="${LOG_PATH:-$INSTALL_DIR/log}" # 환경 변수 또는 기본값

# --- [Functions] ---

# @description 서비스 상태 및 정보 출력 (PID, Port, Log 등)
check_status() {
    echo -e "\n${BOLD}${BLUE}================================================================${NC}"
    echo -e "${BOLD}${BLUE}🚀  $APP_NAME STATUS CHECK                                 ${NC}"
    echo -e "${BOLD}${BLUE}================================================================${NC}"

    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
             # 포트 확인 (ss 사용)
            DETECTED_PORT="Unknown"
            if command -v ss >/dev/null 2>&1; then
                SS_OUT=$(ss -tlnp | grep "pid=$PID")
                if [ -n "$SS_OUT" ]; then
                     DETECTED_PORT=$(echo "$SS_OUT" | awk '{print $4}' | awk -F':' '{print $NF}')
                fi
            fi

            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}STATUS${NC}     : ${GREEN}RUNNING${NC}"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PID${NC}        : ${GREEN}$PID${NC}"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PORT${NC}       : ${GREEN}$DETECTED_PORT${NC}"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}LOG${NC}        : ${YELLOW}$LOG_PATH/${APP_NAME}.log${NC}"
        else
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}STATUS${NC}     : ${RED}STOPPED (PID file exists but process not found)${NC}"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PID${NC}        : ${RED}$PID${NC}"
            # PID 파일 정리 제안?
        fi
    else
        echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}STATUS${NC}     : ${RED}STOPPED${NC}"
    fi
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

# --- [Execution] ---
# 환경 변수 파일 로드 (로그 경로 등 확인용)
if [ -f "$SCRIPT_DIR/.app-env.properties" ]; then
    source "$SCRIPT_DIR/.app-env.properties"
fi

check_status
