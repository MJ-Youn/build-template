#!/bin/bash
# ==============================================================================
# File: uninstall_service.sh
# Description: 서비스 제거 스크립트 (Legacy / Docker 배포 방식 모두 지원)
#              배포 방식을 자동 감지하여 적절한 제거 절차를 수행합니다.
# Author: 윤명준 (MJ Yune)
# Since: 2026-02-11
# ==============================================================================

# --- [Script Init] ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 부트스트랩 (유틸리티 로드 및 폴백)
source "$SCRIPT_DIR/bootstrap.sh"

# --- [Constants & Variables] ---
# build_test은 Gradle 빌드 시 실제 프로젝트 이름으로 치환됨
APP_NAME="build_test"
# 배포 방식에 따라 INSTALL_DIR 결정:
# - Legacy 모드: 스크립트가 bin/ 하위에 있으므로 부모 디렉토리가 설치 루트
# - Docker 모드: 스크립트가 설치 루트에 직접 있으므로 SCRIPT_DIR 자체가 설치 루트
if [ "$(basename "$SCRIPT_DIR")" = "bin" ]; then
    INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
else
    INSTALL_DIR="$SCRIPT_DIR"
fi

# 환경 변수 파일 (로그 경로 등 확인용)
# Legacy: bin/.app-env.properties / Docker: .app-env.properties (INSTALL_DIR 바로 아래)
if [ -f "$INSTALL_DIR/.app-env.properties" ]; then
    PROP_FILE="$INSTALL_DIR/.app-env.properties"
elif [ -f "$SCRIPT_DIR/.app-env.properties" ]; then
    PROP_FILE="$SCRIPT_DIR/.app-env.properties"
else
    PROP_FILE="$SCRIPT_DIR/.app-env.properties"
fi

# 실행 유저 확인
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# 배포 방식 (자동 감지 또는 사용자 선택)
DEPLOY_MODE=""

# Docker-compose 명령어 (Docker 모드에서만 사용)
DOCKER_COMPOSE_CMD=""

# --- [Functions] ---

# @description 현재 배포 방식을 자동으로 감지
# docker-compose.yml 파일 또는 Systemd 서비스 파일의 내용을 기반으로 판단
detect_deploy_mode() {
    log_step "배포 방식 감지 중..."

    local SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"

    # 1. Systemd 서비스 파일에서 감지
    if [ -f "$SERVICE_FILE" ]; then
        if grep -q "docker" "$SERVICE_FILE" 2>/dev/null; then
            DEPLOY_MODE="docker"
            log_info "Docker 배포 방식 감지됨 (Systemd 서비스 파일 기반)"
            return
        else
            DEPLOY_MODE="legacy"
            log_info "Legacy 배포 방식 감지됨 (Systemd 서비스 파일 기반)"
            return
        fi
    fi

    # 2. SysVinit init.d 스크립트에서 감지
    local INIT_SCRIPT="/etc/init.d/$APP_NAME"
    if [ -f "$INIT_SCRIPT" ]; then
        if grep -q "docker" "$INIT_SCRIPT" 2>/dev/null; then
            DEPLOY_MODE="docker"
            log_info "Docker 배포 방식 감지됨 (init.d 스크립트 기반)"
            return
        else
            DEPLOY_MODE="legacy"
            log_info "Legacy 배포 방식 감지됨 (init.d 스크립트 기반)"
            return
        fi
    fi

    # 3. 설치 디렉토리 내 docker-compose.yml 존재 여부로 감지
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        DEPLOY_MODE="docker"
        log_info "Docker 배포 방식 감지됨 (docker-compose.yml 파일 기반)"
        return
    fi

    # 4. 자동 감지 실패 → 사용자 선택
    log_warning "배포 방식을 자동으로 감지할 수 없습니다."
    echo ""
    echo -e "   ${BOLD}제거할 배포 방식을 선택하세요:${NC}"
    echo -e "   ${CYAN}1) Legacy${NC}  - Java(Jar) 직접 실행 방식"
    echo -e "   ${CYAN}2) Docker${NC}  - Docker 컨테이너 실행 방식"
    echo ""

    while true; do
        read -p "   선택 [1/2] (기본값: 1): " MODE_INPUT
        MODE_INPUT="${MODE_INPUT:-1}"
        case "$MODE_INPUT" in
            1)
                DEPLOY_MODE="legacy"
                break
                ;;
            2)
                DEPLOY_MODE="docker"
                break
                ;;
            *)
                log_warning "잘못된 입력입니다. 1 또는 2를 입력해주세요."
                ;;
        esac
    done
}

# @description 서비스 제거 메인 함수
uninstall_service() {
    log_header "서비스 삭제 시작 ($APP_NAME)" "🗑️"

    log_warning "이 작업은 되돌릴 수 없습니다."
    log_info "설치 디렉토리: $INSTALL_DIR"

    # 배포 방식 감지
    detect_deploy_mode
    log_info "제거 대상 배포 방식: $DEPLOY_MODE"

    # 사용자 확인
    confirm_uninstall

    # 1. 서비스 중지 및 비활성화
    stop_and_disable_service

    # 2. Cron 작업 삭제
    remove_cron

    # 3. 로그 삭제 확인
    remove_logs

    # [Docker 전용] Docker 이미지 삭제
    if [ "$DEPLOY_MODE" = "docker" ]; then
        remove_docker_image
    fi

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

# @description 서비스 중지 및 비활성화 (Legacy + Docker 통합)
# Docker 모드에서는 서비스 중지 전 docker-compose down을 먼저 실행
stop_and_disable_service() {
    log_step "서비스 중지 및 비활성화..."

    local SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"
    local INIT_SCRIPT="/etc/init.d/$APP_NAME"

    # Docker 모드: docker-compose down으로 컨테이너 먼저 정리
    if [ "$DEPLOY_MODE" = "docker" ]; then
        local COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
        if [ -f "$COMPOSE_FILE" ]; then
            log_info "컨테이너 정리 중 (docker-compose down)..."
            detect_docker_compose_cmd
            $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down 2>/dev/null || true
        fi
    fi

    # Systemd 서비스 제거
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet $APP_NAME 2>/dev/null; then
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
        service $APP_NAME stop 2>/dev/null || true
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
    local CRON_FILE="/etc/cron.d/$APP_NAME"
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
    local LOG_PATH=""
    if [ -f "$PROP_FILE" ]; then
        local LOG_PATH_Line
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
                # 로그 경로가 앱 전용 디렉토리이면 전체 삭제
                log_info "로그 디렉토리 삭제 중..."
                rm -rf "$LOG_PATH"
                log_success "로그 파일이 삭제되었습니다."
            else
                # 시스템 공유 디렉토리인 경우 APP_NAME으로 시작하는 파일만 선택 삭제
                log_warning "'$LOG_PATH' 는 시스템 공유 디렉토리입니다."
                log_info "디렉토리 전체 삭제 대신 '$APP_NAME' 관련 파일만 삭제합니다."
                local DELETED_COUNT=0
                while IFS= read -r -d '' f; do
                    log_info "삭제: $f"
                    rm -f "$f"
                    DELETED_COUNT=$((DELETED_COUNT + 1))
                done < <(find "$LOG_PATH" -maxdepth 1 -name "${APP_NAME}*" -print0 2>/dev/null)

                if [ "$DELETED_COUNT" -gt 0 ]; then
                    log_success "$DELETED_COUNT 개의 로그 파일이 삭제되었습니다."
                else
                    log_info "삭제할 '$APP_NAME' 관련 로그 파일이 없습니다."
                fi
            fi
        else
            log_info "로그 파일은 보존되었습니다."
        fi
    else
        log_info "로그 디렉토리가 존재하지 않습니다."
    fi
}

# @description Docker 이미지 제거 (Docker 모드 전용)
remove_docker_image() {
    log_step "Docker 이미지 정리"

    # tar 아카이브 파일 삭제 (있는 경우)
    local TAR_FILE="$INSTALL_DIR/$APP_NAME.tar"
    if [ -f "$TAR_FILE" ]; then
        log_info "Docker 이미지 아카이브 발견: $TAR_FILE"
        rm "$TAR_FILE"
        log_success "이미지 아카이브 삭제됨."
    fi

    # Docker 이미지 삭제 여부 확인
    read -p "   ❓ Docker 이미지($APP_NAME:latest)를 삭제하시겠습니까? (y/N): " DEL_IMG
    DEL_IMG=${DEL_IMG:-N}
    if [[ "$DEL_IMG" =~ ^[Yy]$ ]]; then
        if docker image inspect "$APP_NAME:latest" >/dev/null 2>&1; then
            docker rmi "$APP_NAME:latest"
            log_success "Docker 이미지 삭제 완료 ($APP_NAME:latest)"
        else
            log_warning "이미지 '$APP_NAME:latest'를 찾을 수 없어 삭제를 건너뜁니다."
        fi
    fi
}

# @description 유틸리티 스크립트 제거 (tail-log 등)
remove_utility_scripts() {
    log_step "유틸리티 스크립트 정리"
    local TAIL_SCRIPT="$USER_HOME/bin/tail-log-${APP_NAME}.sh"
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
  echo "Error: 이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

uninstall_service
