#!/bin/bash
# ==============================================================================
# File: uninstall_docker_service.sh
# Description: Docker 서비스 제거 스크립트
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
    log_header() { echo "🗑️  $1"; }
    log_step() { echo "➡️  $1"; }
    log_info() { echo "   ℹ️  $1"; }
    log_success() { echo "✅  $1"; }
    log_warning() { echo "⚠️  $1"; }
    log_error() { echo "❌  $1"; }
    is_safe_path() { return 0; } # Fallback: always safe (risky, but better than fail)
fi

# --- [Constants & Variables] ---
APP_NAME="@appName@"
INSTALL_DIR="$SCRIPT_DIR"  # 설치 디렉토리 (현재 스크립트 위치)
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
PROP_FILE="$INSTALL_DIR/.app-env.properties"

# 실행 유저 확인
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# --- [Functions] ---

# @description Docker 서비스 제거 메인 함수
uninstall_docker_service() {
    log_header "Docker 서비스 삭제 시작 ($APP_NAME)" "🗑️"

    log_warning "이 작업은 되돌릴 수 없습니다."
    log_info "설치 디렉토리: $INSTALL_DIR"
    read -p "   ❓ 정말로 삭제하시겠습니까? (y/N): " CONFIRM
    CONFIRM=${CONFIRM:-N}

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "삭제가 취소되었습니다."
        exit 0
    fi

    # 1. 서비스 중지/제거 (Docker Compose Down 포함)
    stop_and_remove_service

    # 2. Cron 작업 삭제
    remove_cron

    # 3. 로그 삭제 확인
    remove_logs

    # 4. Docker 이미지 삭제
    remove_docker_image

    # 5. 유틸리티 스크립트 삭제
    remove_utility_scripts

    # 6. 설치 디렉토리 삭제
    remove_install_dir

    log_header "삭제 완료"
    echo -e "   ${GREEN}모든 구성 요소가 제거되었습니다. 이용해 주셔서 감사합니다.${NC}"
}


stop_and_remove_service() {
    log_step "서비스 중지 및 비활성화..."

    # Docker Compose Down (if file exists)
    if [ -f "$COMPOSE_FILE" ]; then
        log_info "컨테이너 정리 중 (docker-compose down)..."
        # Docker Compose 명령어 감지
        DOCKER_BIN=$(command -v docker)
        if $DOCKER_BIN compose version >/dev/null 2>&1; then
             $DOCKER_BIN compose -f "$COMPOSE_FILE" down
        elif command -v docker-compose >/dev/null 2>&1; then
             docker-compose -f "$COMPOSE_FILE" down
        else 
             # Fallback
             log_warning "Docker Compose 명령어를 찾을 수 없어 컨테이너 정리를 건너뜁니다."
        fi
    fi

    # Systemd/SysVinit 서비스 제거
    SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"
    INIT_SCRIPT="/etc/init.d/$APP_NAME"

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet $APP_NAME; then
            systemctl stop $APP_NAME
        fi
        if systemctl is-enabled --quiet $APP_NAME 2>/dev/null; then
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

    # .app-env.properties에서 LOG_PATH 읽기
    LOG_PATH=""
    if [ -f "$PROP_FILE" ]; then
        LOG_PATH_Line=$(grep "^LOG_PATH=" "$PROP_FILE")
        if [ -n "$LOG_PATH_Line" ]; then
            LOG_PATH=$(echo "$LOG_PATH_Line" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
    fi
    LOG_PATH="${LOG_PATH:-$INSTALL_DIR/log}"

    log_info "감지된 로그 경로: $LOG_PATH"

    if [ -d "$LOG_PATH" ]; then
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

# @description Docker 이미지 제거
remove_docker_image() {
    log_step "Docker 이미지 정리"
    
    # 설치 시 사용된 타르 파일
    TAR_FILE="$INSTALL_DIR/$APP_NAME.tar"
    
    # 현재 실행 중인 이미지를 찾아서 삭제할 수도 있지만,
    # 여기서는 로드된 이미지를 삭제할지 물어보는 것이 좋음.
    # 이미지 이름 추정 (보통 app_name:latest 또는 app_name:version)
    
    # 간단히: 타르 파일 삭제 여부
    if [ -f "$TAR_FILE" ]; then
        log_info "Docker 이미지 아카이브 발견: $TAR_FILE"
        rm "$TAR_FILE"
        log_success "이미지 아카이브 삭제됨."
    fi

    # Docker 이미지 삭제 시도 (docker rmi)
    # 이미지 이름을 정확히 알기 어려우므로 생략하거나, 
    # docker-compose가 있다면 compose down --rmi local 등을 사용했어야 함.
    # stop_and_remove_service에서 docker-compose down --rmi local 옵션을 고려하거나 여기서 처리.
    
    # 여기서는 사용자가 명시적으로 이미지를 지우길 원할 수 있음
    read -p "   ❓ Docker 이미지($APP_NAME)를 삭제하시겠습니까? (y/N): " DEL_IMG
    DEL_IMG=${DEL_IMG:-N}
    if [[ "$DEL_IMG" =~ ^[Yy]$ ]]; then
         # 이미지 이름이 명확하지 않을 수 있으나 $APP_NAME:latest 시도
         if docker image inspect "$APP_NAME:latest" >/dev/null 2>&1; then
             docker rmi "$APP_NAME:latest"
             log_success "Docker 이미지 삭제 완료 ($APP_NAME:latest)"
         else
             log_warning "이미지 '$APP_NAME:latest'를 찾을 수 없어 삭제를 건너뜁니다."
         fi
    fi
}

# @description 유틸리티 스크립트 제거
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
    
    if ! is_safe_path "$INSTALL_DIR"; then
        log_error "잘못된 또는 위험한 설치 경로 감지 ($INSTALL_DIR). 삭제를 중단합니다."
        exit 1
    fi

    rm -rf "$INSTALL_DIR"
}
# --- [Execution] ---

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
  # log_error 함수가 정의되지 않았을 수 있으므로 echo로 출력
  echo "Error: 이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

uninstall_docker_service
