#!/bin/bash
# ==============================================================================
# File: stop.sh
# Description: 서비스 종료 스크립트
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
    log_step() { echo "➡️  $1"; }
    log_info() { echo "   ℹ️  $1"; }
    log_success() { echo "✅  $1"; }
    log_error() { echo "❌  $1"; }
fi

# --- [Constants & Variables] ---
# .app-env.properties 로드
if [ -f "$SCRIPT_DIR/.app-env.properties" ]; then
    source "$SCRIPT_DIR/.app-env.properties"
fi

PID_FILE="${PID_FILE:-$SCRIPT_DIR/application.pid}"
# @var STOP_TIMEOUT 종료 대기 시간 (초)
STOP_TIMEOUT=${STOP_TIMEOUT:-10}

# --- [Functions] ---

# @description 애플리케이션 종료 처리
# @return 0: 종료 성공 또는 이미 종료됨
stop_application() {
    log_step "애플리케이션을 종료합니다..."

    if [ ! -f "$PID_FILE" ]; then
        log_info "PID 파일을 찾을 수 없습니다 ($PID_FILE). 애플리케이션이 실행 중이지 않을 수 있습니다."
        return 0
    fi

    PID=$(cat "$PID_FILE")

    if [ -z "$PID" ]; then
        log_warning "PID 파일이 비어있습니다. 파일을 삭제합니다."
        rm "$PID_FILE"
        return 0
    fi

    if ps -p "$PID" > /dev/null 2>&1; then
        kill "$PID"
        log_info "종료 신호(SIGTERM)를 보냈습니다 (PID: $PID)."
        
        # 종료 대기 (최대 $STOP_TIMEOUT초)
        count=0
        while ps -p "$PID" > /dev/null 2>&1; do
            echo -n "."
            sleep 1
            count=$((count+1))
            if [ $count -ge $STOP_TIMEOUT ]; then
                echo ""
                log_warning "애플리케이션이 ${STOP_TIMEOUT}초 내에 응답하지 않아 강제 종료(SIGKILL)합니다."
                kill -9 "$PID"
                break
            fi
        done
        echo ""
        log_success "애플리케이션이 종료되었습니다."
        rm "$PID_FILE"
    else
        log_info "해당 PID($PID)의 프로세스가 존재하지 않습니다. PID 파일을 정리합니다."
        rm "$PID_FILE"
    fi
}

# --- [Execution] ---
stop_application
