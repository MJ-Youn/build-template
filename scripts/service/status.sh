#!/bin/bash
# ==============================================================================
# File: status.sh
# Description: 서비스 상태 확인 스크립트
# Author: 윤명준 (MJ Yun)
# Since: 2026-02-11
# ==============================================================================

# --- [Script Init] ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 부트스트랩 (유틸리티 로드 및 폴백)
if [ -f "$SCRIPT_DIR/bootstrap.sh" ]; then
    source "$SCRIPT_DIR/bootstrap.sh"
elif [ -f "$SCRIPT_DIR/../common/bootstrap.sh" ]; then
    source "$SCRIPT_DIR/../common/bootstrap.sh"
fi

# --- [Constants & Variables] ---
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_LOC="$PROJECT_ROOT/config/"

# 환경 변수 파일 로드 (우선순위: 루트 .env -> config/.env -> bin/.env)
[ -f "$PROJECT_ROOT/.env" ] && source "$PROJECT_ROOT/.env"
[ -f "$CONFIG_LOC/.env" ] && source "$CONFIG_LOC/.env"
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"

APP_NAME="@appName@"
PID_FILE="${PID_FILE:-$SCRIPT_DIR/application.pid}"
LOG_PATH="${LOG_PATH:-$PROJECT_ROOT/log}" # 환경 변수 또는 기본값

# --- [Functions] ---

# @description 서비스 상태 및 정보 출력 (PID, Port, Log 등)
check_status() {
    # -------------------------------------------------------------
    # 🐳 [호스트 환경] Docker Compose 배포 환경 감지 및 상태 확인
    # -------------------------------------------------------------
    local COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
    if [ -f "$COMPOSE_FILE" ] && ! is_docker_container; then
        echo -e "\n${BOLD}${BLUE}================================================================${NC}"
        echo -e "${BOLD}${BLUE}🐳  $APP_NAME DOCKER STATUS CHECK                           ${NC}"
        echo -e "${BOLD}${BLUE}================================================================${NC}"

        detect_docker_compose_cmd true

        cd "$PROJECT_ROOT" || exit 1
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" ps
        echo -e "${BOLD}${BLUE}================================================================${NC}\n"
        return 0
    fi

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
check_status
