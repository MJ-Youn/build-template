#!/bin/bash
# ==============================================================================
# File: install_service.sh
# Description: 서비스 설치 및 실행 스크립트 (Legacy / Docker 배포 방식 지원)
#              Systemd / SysVinit 자동 감지
# Author: 윤명준 (MJ Yune)
# Since: 2026-02-11
# ==============================================================================

# --- [Script Init] ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 부트스트랩 (유틸리티 로드 및 폴백)
source "$SCRIPT_DIR/bootstrap.sh"

# --- [Constants & Variables] ---
# @appName@은 Gradle 빌드 시 실제 프로젝트 이름으로 치환됨
APP_NAME="@appName@"
# 배포 패키지 루트 (build/dist/XXX 압축 해제 위치)
PKG_ROOT="$(dirname "$SCRIPT_DIR")"

# 기본 설치 위치 정의 (환경 변수 INSTALL_DIR 또는 첫 번째 인자로 재정의 가능)
DEFAULT_INSTALL_DIR="${1:-${INSTALL_DIR:-/opt/$APP_NAME}}"

# 실행 유저 확인 (sudo로 실행 시 실제 유저)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
SERVICE_GROUP=$(id -gn "$REAL_USER")

# 전역 변수 (함수 내에서 설정됨)
DEST_DIR=""
LOG_PATH=""
DEPLOY_MODE=""  # "legacy" 또는 "docker"

# --- [Functions] ---

# @description 배포 방식 선택 (legacy / docker)
select_deploy_mode() {
    log_step "배포 방식 선택"
    echo ""
    echo -e "   ${BOLD}배포 방식을 선택하세요:${NC}"
    echo -e "   ${CYAN}1) Legacy${NC}  - Java(Jar) 직접 실행 방식"
    echo -e "   ${CYAN}2) Docker${NC}  - 배포 파일로 Docker 이미지 빌드 후 실행"
    echo ""

    while true; do
        read -p "   선택 [1/2] (기본값: 1): " MODE_INPUT
        MODE_INPUT="${MODE_INPUT:-1}"
        case "$MODE_INPUT" in
            1)
                DEPLOY_MODE="legacy"
                log_info "Legacy 배포 방식이 선택되었습니다."
                break
                ;;
            2)
                DEPLOY_MODE="docker"
                log_info "Docker 배포 방식이 선택되었습니다."
                break
                ;;
            *)
                log_warning "잘못된 입력입니다. 1 또는 2를 입력해주세요."
                ;;
        esac
    done
}

# @description 서비스 설치 메인 함수
install_service() {
    log_header "서비스 설치 시작 ($APP_NAME)"

    # 배포 방식 선택
    select_deploy_mode

    if [ "$DEPLOY_MODE" = "docker" ]; then
        install_docker_mode
    else
        install_legacy_mode
    fi
}

# ============================================================
# Legacy 배포 모드
# ============================================================

# @description Legacy 배포 모드 메인 흐름
install_legacy_mode() {
    log_header "Legacy 배포 시작"

    # 사전 요구사항 확인
    check_legacy_prerequisites

    # 설치 위치 결정 (기존 설치 감지 포함)
    determine_install_dir

    # 이전 Docker 배포 잔재 파일 정리
    cleanup_docker_artifacts

    # 파일 복사
    copy_legacy_files

    # 환경 설정 및 로그 경로
    configure_legacy_env

    # 서비스 등록
    register_legacy_service

    log_header "설치 완료"
}

# @description 이전 Docker 배포 잔재 파일 정리
# Docker 모드에서 Legacy 모드로 전환 시 루트에 남은 불필요한 파일 제거
cleanup_docker_artifacts() {
    # Docker 배포 시 루트에 복사되는 파일 목록 (Legacy에서 불필요)
    local DOCKER_ROOT_FILES=(
        "$DEST_DIR/docker-compose.yml"
        "$DEST_DIR/bootstrap.sh"
        "$DEST_DIR/utils.sh"
        "$DEST_DIR/uninstall_service.sh"
        "$DEST_DIR/.app-env.properties"
    )

    local CLEANED=0
    for f in "${DOCKER_ROOT_FILES[@]}"; do
        if [ -f "$f" ]; then
            rm -f "$f"
            CLEANED=1
        fi
    done

    # 루트의 cron 디렉토리 (Docker 잔재)
    if [ -d "$DEST_DIR/cron" ]; then
        rm -rf "$DEST_DIR/cron"
        CLEANED=1
    fi

    if [ "$CLEANED" -eq 1 ]; then
        log_info "이전 Docker 배포 잔재 파일을 정리했습니다."
    fi
}


# @description Legacy 설치 사전 요구사항 점검 (Java 등)
check_legacy_prerequisites() {
    log_step "사전 요구사항 확인"
    if ! command -v java &> /dev/null; then
        log_error "Java가 설치되어 있지 않습니다. Java를 먼저 설치해주세요."
        exit 1
    fi
    log_success "Java 설치 확인 완료."
}

# @description 설치 경로 결정 (기존 설치 감지 또는 사용자 입력)
determine_install_dir() {
    log_step "설치 위치 설정"

    # 기존 설치 감지
    PREVIOUS_INSTALL_LOC=""

    # 1. Systemd 감지
    if command -v systemctl >/dev/null 2>&1; then
        # 서비스 파일 경로 확인
        SERVICE_PATH=$(systemctl show -p FragmentPath "$APP_NAME.service" 2>/dev/null | cut -d= -f2)
        if [ -n "$SERVICE_PATH" ] && [ -f "$SERVICE_PATH" ]; then
            # ExecStart 라인에서 실제 실행 스크립트 경로 추출
            EXEC_START=$(grep "ExecStart=" "$SERVICE_PATH" | cut -d= -f2 | sed 's/^"//;s/"$//')
            if [ -n "$EXEC_START" ]; then
                 # .../bin/start.sh -> .../bin -> 부모 디렉토리 (설치 루트)
                 PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
            fi
        fi
    fi

    # 2. SysVinit 감지 (Systemd가 없거나 못 찾았을 경우)
    if [ -z "$PREVIOUS_INSTALL_LOC" ] && [ -f "/etc/init.d/$APP_NAME" ]; then
         # init 스크립트에서 실행 경로 추출 시도
         EXEC_START=$(grep "su - $REAL_USER -c" "/etc/init.d/$APP_NAME" | head -n 1 | awk -F '"' '{print $2}')
          if [ -n "$EXEC_START" ]; then
                 PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
            fi
    fi

    if [ -n "$PREVIOUS_INSTALL_LOC" ] && [ -d "$PREVIOUS_INSTALL_LOC" ]; then
        log_info "기존 설치 위치가 감지되었습니다: $PREVIOUS_INSTALL_LOC"
        read -p "   🔄 기존 위치에 재배포하시겠습니까? [Y/n] " REUSE_LOC
        REUSE_LOC=${REUSE_LOC:-Y}
        if [[ "$REUSE_LOC" =~ ^[Yy]$ ]]; then
            DEST_DIR="$PREVIOUS_INSTALL_LOC"
        fi
    fi

    if [ -z "$DEST_DIR" ]; then
        log_info "기본 설치 위치: $DEFAULT_INSTALL_DIR"
        read -p "   📂 설치할 위치를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOC
        DEST_DIR="${INPUT_LOC:-$DEFAULT_INSTALL_DIR}"
    fi

    log_info "최종 설치 위치: $DEST_DIR"
    log_info "서비스 실행 유저: $REAL_USER"

    # 디렉토리 생성 및 권한 설정
    mkdir -p "$DEST_DIR/bin"
    mkdir -p "$DEST_DIR/config"
    mkdir -p "$DEST_DIR/libs"
    mkdir -p "$DEST_DIR/run"

    # 보안 강화: 실행 파일 디렉토리는 root 소유로 설정하여 서비스 유저의 변조 방지
    chown root:root "$DEST_DIR" "$DEST_DIR/bin" "$DEST_DIR/config" "$DEST_DIR/libs"
    chmod 755 "$DEST_DIR" "$DEST_DIR/bin" "$DEST_DIR/config" "$DEST_DIR/libs"

    # 실행 시 생성되는 파일(PID 등)을 위한 디렉토리는 서비스 유저 권한 부여
    chown $REAL_USER:$SERVICE_GROUP "$DEST_DIR/run"
    chmod 755 "$DEST_DIR/run"

    log_success "설치 디렉토리 준비 완료."
}

# @description 배포 파일 복사 (bin, libs, config)
copy_legacy_files() {
    log_step "파일 복사 및 배포 중..."

    # 1. Libs (Jar)
    cp -f "$PKG_ROOT/libs/"*.jar "$DEST_DIR/libs/"

    # 2. Bin Scripts
    # Legacy 실행에 필요한 스크립트만 명시적으로 복사
    # (run_bash_tests.sh, bootstrap.sh 등 불필요한 파일 제외)
    local LEGACY_SCRIPTS=("start.sh" "stop.sh" "status.sh" "uninstall_service.sh" "utils.sh" "bootstrap.sh")
    for script in "${LEGACY_SCRIPTS[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            cp -f "$SCRIPT_DIR/$script" "$DEST_DIR/bin/"
        fi
    done

    # cron 디렉토리 복사
    if [ -d "$SCRIPT_DIR/cron" ]; then
        cp -rf "$SCRIPT_DIR/cron" "$DEST_DIR/bin/"
    fi

    # 3. .app-env.properties
    if [ -f "$SCRIPT_DIR/.app-env.properties" ]; then
        cp -f "$SCRIPT_DIR/.app-env.properties" "$DEST_DIR/bin/"
    fi

    # 4. Config
    cp -rf "$PKG_ROOT/config/"* "$DEST_DIR/config/"

    # 권한 설정
    chmod 755 "$DEST_DIR/bin/"*.sh
    chmod 644 "$DEST_DIR/libs/"*.jar
    chmod -R 644 "$DEST_DIR/config/"*
    find "$DEST_DIR/config" -type d -exec chmod 755 {} +

    # 보안 강화: 배포된 파일들은 root 소유로 설정
    chown -R root:root "$DEST_DIR/bin" "$DEST_DIR/libs" "$DEST_DIR/config"

    log_success "파일 복사 및 권한 설정 완료."
}


# @description 환경 변수 설정 및 로그 경로 확인 (Legacy 모드)
configure_legacy_env() {
    log_step "환경 설정 및 로그 경로 확인"

    DEST_PROP_FILE="$DEST_DIR/bin/.app-env.properties"

    if [ ! -f "$DEST_PROP_FILE" ]; then
        mkdir -p "$(dirname "$DEST_PROP_FILE")"
        echo "# Application Deployment Configuration" > "$DEST_PROP_FILE"
        chmod 644 "$DEST_PROP_FILE"
        chown root:root "$DEST_PROP_FILE"
        log_info "새로운 환경 설정 파일 생성: $DEST_PROP_FILE"
    fi

    # 현재 파일에서 LOG_PATH 읽기
    LOG_PATH=""
    if [ -f "$DEST_PROP_FILE" ]; then
        LOG_PATH_Line=$(grep "^LOG_PATH=" "$DEST_PROP_FILE")
        if [ -n "$LOG_PATH_Line" ]; then
            LOG_PATH=$(echo "$LOG_PATH_Line" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
    fi

    # LOG_PATH 설정 (없는 경우 사용자 입력)
    if [ -z "$LOG_PATH" ]; then
        DEFAULT_LOG_PATH="$DEST_DIR/log"
        log_info "기본 로그 경로: $DEFAULT_LOG_PATH"
        read -p "   📝 로그 경로를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOG_PATH
        LOG_PATH="${INPUT_LOG_PATH:-$DEFAULT_LOG_PATH}"

        if grep -q "^LOG_PATH=" "$DEST_PROP_FILE"; then
            sed -i "/^LOG_PATH=/c\\LOG_PATH=\"$LOG_PATH\"" "$DEST_PROP_FILE"
        else
            echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP_FILE"
        fi
        chown root:root "$DEST_PROP_FILE"
        log_info "환경 설정 파일에 LOG_PATH 저장 완료."
    fi

    # PID_FILE 설정
    NEW_PID_FILE="$DEST_DIR/run/application.pid"
    if grep -q "^PID_FILE=" "$DEST_PROP_FILE"; then
        sed -i "/^PID_FILE=/c\\PID_FILE=\"$NEW_PID_FILE\"" "$DEST_PROP_FILE"
    else
        echo "PID_FILE=\"$NEW_PID_FILE\"" >> "$DEST_PROP_FILE"
    fi
    chown root:root "$DEST_PROP_FILE"
    log_info "환경 설정 파일에 PID_FILE 저장 완료."

    log_info "로그 경로: $LOG_PATH"

    mkdir -p "$LOG_PATH"
    chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"
    chmod 755 "$LOG_PATH"
    log_success "로그 디렉토리 준비 완료."

    create_tail_log_script
}

# @description Systemd 또는 SysVinit에 Legacy 서비스 등록
register_legacy_service() {
    log_step "서비스 등록 및 시작..."
    START_SCRIPT="$DEST_DIR/bin/start.sh"
    STOP_SCRIPT="$DEST_DIR/bin/stop.sh"

    INIT_SYSTEM="unknown"
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif [ -f /etc/init.d/cron ] || [ -f /etc/init.d/functions ]; then
        INIT_SYSTEM="sysvinit"
    fi

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"

        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=$APP_NAME 서비스
After=network.target

[Service]
User=$REAL_USER
Group=$SERVICE_GROUP
Type=forking
ExecStart=$START_SCRIPT
ExecStop=$STOP_SCRIPT
PIDFile=$DEST_DIR/run/application.pid
Restart=always

[Install]
WantedBy=multi-user.target
EOF

        log_success "$SERVICE_FILE 파일이 갱신되었습니다."
        systemctl daemon-reload
        systemctl enable $APP_NAME
        if systemctl is-active --quiet $APP_NAME; then
            log_info "서비스가 실행 중입니다. 재시작합니다..."
            systemctl restart $APP_NAME
        else
            systemctl start $APP_NAME
            log_success "서비스가 시작되었습니다."
        fi

        register_cron
        check_legacy_service_status

    elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
        STATUS_SCRIPT="$DEST_DIR/bin/status.sh"
        INIT_SCRIPT="/etc/init.d/$APP_NAME"

        cat <<EOF > "$INIT_SCRIPT"
#!/bin/bash
# chkconfig: 2345 20 80
# description: $APP_NAME Service

case "\$1" in
    start)
        su - $REAL_USER -c "$START_SCRIPT"
        ;;
    stop)
        su - $REAL_USER -c "$STOP_SCRIPT"
        ;;
    restart)
        \$0 stop
        \$0 start
        ;;
    status)
        su - $REAL_USER -c "$STATUS_SCRIPT"
        ;;
    *)
        echo "사용법: \$0 {start|stop|restart|status}"
        exit 1
esac
exit 0
EOF

        chmod +x "$INIT_SCRIPT"

        if command -v chkconfig >/dev/null 2>&1; then
            chkconfig --add $APP_NAME
            chkconfig $APP_NAME on
        elif command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d $APP_NAME defaults
        fi

        log_success "서비스가 등록되었습니다 (sysvinit)."
        service $APP_NAME restart
    else
        log_error "알 수 없는 Init 시스템입니다. 서비스 등록을 건너뜁니다."
        exit 0
    fi
}

# ============================================================
# Docker 배포 모드
# ============================================================

# @description Docker 배포 모드 메인 흐름
install_docker_mode() {
    log_header "Docker 배포 시작"

    # Docker 설치 확인
    check_docker_prerequisites

    # 설치 위치 결정
    determine_docker_install_dir

    # Docker 이미지 빌드 (dist 파일 기반)
    build_docker_image_from_dist

    # docker-compose 및 관련 파일 복사
    copy_docker_files

    # 환경 설정 (LOG_PATH 등)
    configure_docker_env

    # docker-compose.yml 환경변수(.env) 설정
    configure_compose

    # 서비스 등록 (Systemd/SysVinit)
    register_docker_service

    log_header "설치 완료"
}

# @description Docker 설치 사전 요구사항 점검
check_docker_prerequisites() {
    log_step "사전 요구사항 확인"
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되어 있지 않습니다. Docker를 먼저 설치해주세요."
        exit 1
    fi
    log_success "Docker 설치 확인 완료."
}

# @description Docker 배포 시 설치 경로 결정
determine_docker_install_dir() {
    log_step "설치 위치 설정"

    # 기존 설치 위치 감지 (Systemd)
    DEST_DIR=""
    if [ -f "/etc/systemd/system/$APP_NAME.service" ]; then
        EXISTING_DIR=$(grep "WorkingDirectory=" "/etc/systemd/system/$APP_NAME.service" | cut -d= -f2)
        if [ -d "$EXISTING_DIR" ]; then
            log_info "기존 설치 위치 감지: $EXISTING_DIR"
            read -p "   기존 위치에 덮어쓰시겠습니까? (Y/n): " REUSE_LOC
            REUSE_LOC=${REUSE_LOC:-Y}
            if [[ "$REUSE_LOC" =~ ^[Yy]$ ]]; then
                DEST_DIR="$EXISTING_DIR"
            fi
        fi
    fi

    if [ -z "$DEST_DIR" ]; then
        log_info "기본 설치 위치: $DEFAULT_INSTALL_DIR"
        read -p "   📂 설치할 위치를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOC
        DEST_DIR="${INPUT_LOC:-$DEFAULT_INSTALL_DIR}"
    fi

    log_info "설치 위치: $DEST_DIR"

    mkdir -p "$DEST_DIR"
    chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"
}

# @description dist 패키지 파일로 Docker 이미지를 빌드
# dist.zip 압축 해제 경로(PKG_ROOT)를 빌드 컨텍스트로 활용
# PKG_ROOT/docker/Dockerfile을 사용하여 이미지 생성
build_docker_image_from_dist() {
    log_step "Docker 이미지 빌드 중 (배포 파일 기반)..."

    DOCKERFILE_PATH="$PKG_ROOT/docker/Dockerfile"

    if [ ! -f "$DOCKERFILE_PATH" ]; then
        log_error "Dockerfile을 찾을 수 없습니다: $DOCKERFILE_PATH"
        exit 1
    fi

    local IMAGE_TAG="${APP_NAME}:latest"

    log_info "빌드 컨텍스트: $PKG_ROOT"
    log_info "Dockerfile: $DOCKERFILE_PATH"
    log_info "이미지 태그: $IMAGE_TAG"

    docker build -t "$IMAGE_TAG" -f "$DOCKERFILE_PATH" "$PKG_ROOT"

    if [ $? -ne 0 ]; then
        log_error "Docker 이미지 빌드 실패"
        exit 1
    fi

    log_success "Docker 이미지 빌드 완료: $IMAGE_TAG"
}

# @description Docker 관련 파일 복사 (docker-compose, uninstall 스크립트 등)
copy_docker_files() {
    log_step "Docker 배포 파일 복사 중..."

    local DOCKER_DIR="$PKG_ROOT/docker"
    local COMPOSE_SRC="$DOCKER_DIR/docker-compose.yml"

    if [ ! -f "$COMPOSE_SRC" ]; then
        log_error "docker-compose.yml을 찾을 수 없습니다: $COMPOSE_SRC"
        exit 1
    fi

    cp "$COMPOSE_SRC" "$DEST_DIR/"

    # uninstall 스크립트 복사
    local UNINSTALL_SRC="$SCRIPT_DIR/uninstall_service.sh"
    if [ -f "$UNINSTALL_SRC" ]; then
        cp "$UNINSTALL_SRC" "$DEST_DIR/"
        chmod +x "$DEST_DIR/uninstall_service.sh"
    fi

    # bootstrap.sh 복사 (uninstall_service.sh가 source하여 사용)
    local BOOTSTRAP_SRC="$SCRIPT_DIR/bootstrap.sh"
    if [ -f "$BOOTSTRAP_SRC" ]; then
        cp "$BOOTSTRAP_SRC" "$DEST_DIR/"
    fi

    # utils.sh 복사
    local UTILS_SRC="$SCRIPT_DIR/utils.sh"
    if [ -f "$UTILS_SRC" ]; then
        cp "$UTILS_SRC" "$DEST_DIR/"
    fi

    # cron 디렉토리 복사
    if [ -d "$SCRIPT_DIR/cron" ]; then
        cp -r "$SCRIPT_DIR/cron" "$DEST_DIR/"
    fi

    # config 폴더 복사 (Host Mount용)
    local CONFIG_SRC="$PKG_ROOT/config"
    if [ -d "$CONFIG_SRC" ]; then
        cp -r "$CONFIG_SRC" "$DEST_DIR/"
        log_info "config 폴더 복사 완료 (Host Mount용)"
    fi

    log_success "Docker 배포 파일 복사 완료."
}

# @description 환경 변수 설정 (Docker 모드 - LOG_PATH 등)
configure_docker_env() {
    log_step "환경 설정 및 로그 경로 확인"

    # .app-env.properties 복사 및 로드
    local SRC_PROP="$SCRIPT_DIR/.app-env.properties"
    local DEST_PROP="$DEST_DIR/.app-env.properties"
    LOG_PATH=""

    if [ -f "$SRC_PROP" ]; then
        cp "$SRC_PROP" "$DEST_PROP"
        source "$DEST_PROP"
    else
        echo "# Application Deployment Configuration" > "$DEST_PROP"
    fi

    # LOG_PATH 설정
    if [ -z "$LOG_PATH" ]; then
        local DEFAULT_LOG_PATH="$DEST_DIR/log"
        log_info "기본 로그 경로: $DEFAULT_LOG_PATH"
        read -p "   📝 로그 경로를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOG_PATH
        LOG_PATH="${INPUT_LOG_PATH:-$DEFAULT_LOG_PATH}"

        if grep -q "^LOG_PATH=" "$DEST_PROP"; then
            grep -v "^LOG_PATH=" "$DEST_PROP" > "$DEST_PROP.tmp"
            echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP.tmp"
            mv "$DEST_PROP.tmp" "$DEST_PROP"
        else
            echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP"
        fi
    fi

    log_info "로그 경로: $LOG_PATH"

    mkdir -p "$LOG_PATH"
    chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"
    chmod 755 "$LOG_PATH"
    log_success "로그 디렉토리 준비 완료."

    create_tail_log_script
}

# @description docker-compose.yml 환경변수(.env 파일) 설정
configure_compose() {
    local COMPOSE_FILE="$DEST_DIR/docker-compose.yml"
    local ENV_FILE="$DEST_DIR/.env"
    log_step "docker-compose.yml 환경변수(.env) 설정 중..."

    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "docker-compose.yml 파일을 찾을 수 없습니다: $COMPOSE_FILE"
        exit 1
    fi

    cat <<EOF > "$ENV_FILE"
# ==========================================================
# Docker Compose Environment Variables
# Generated by install_service.sh
# ==========================================================
APP_NAME=$APP_NAME
LOG_PATH=$LOG_PATH
DEST_DIR=$DEST_DIR
DOCKER_IMAGE=${APP_NAME}:latest
EOF

    log_success "환경 및 볼륨(.env) 설정 업데이트 완료"

    # 빈 config 폴더 마운트로 인한 컨테이너 내부 config 초기화 방지
    local CONFIG_DIR="$DEST_DIR/config"
    mkdir -p "$CONFIG_DIR"

    if [ -z "$(ls -A "$CONFIG_DIR")" ]; then
        log_step "초기 Host Config 파일 생성 중..."
        docker run --rm -v "$CONFIG_DIR:/tmp_config" "${APP_NAME}:latest" sh -c "cp -r /app/config/* /tmp_config/ 2>/dev/null || true"
        log_success "Host Config 마운트 폴더 초기화 완료"
    fi
}

# @description Docker 서비스를 Systemd 또는 SysVinit에 등록
register_docker_service() {
    # Init 시스템 감지
    local INIT_SYSTEM="sysvinit"
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif [ -f /etc/init.d/cron ] || [ -f /etc/init.d/functions ]; then
        INIT_SYSTEM="sysvinit"
    else
        log_error "알 수 없는 Init 시스템입니다."
        exit 1
    fi

    # Docker Compose 명령어 감지
    detect_docker_compose_cmd
    log_info "Docker Compose 명령어: $DOCKER_COMPOSE_CMD"

    local COMPOSE_FILE="$DEST_DIR/docker-compose.yml"
    log_step "서비스 등록 및 시작..."

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        local SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"

        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=$APP_NAME Docker Container Service
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DEST_DIR
ExecStart=$DOCKER_COMPOSE_CMD -f $COMPOSE_FILE up
ExecStop=$DOCKER_COMPOSE_CMD -f $COMPOSE_FILE down
Restart=always

[Install]
WantedBy=multi-user.target
EOF

        log_success "$SERVICE_FILE 파일이 생성되었습니다."
        systemctl daemon-reload
        systemctl enable $APP_NAME

        if systemctl is-active --quiet $APP_NAME; then
            log_info "서비스가 실행 중입니다. 재시작합니다..."
            systemctl restart $APP_NAME
        else
            systemctl start $APP_NAME
            log_success "서비스가 시작되었습니다."
        fi

        register_cron

        # 서비스 상태 출력
        sleep 2
        local CONTAINER_STATUS
        local CONTAINER_ID
        CONTAINER_STATUS=$(docker ps -f "name=${APP_NAME}-app" --format "{{.Status}}")
        CONTAINER_ID=$(docker ps -f "name=${APP_NAME}-app" --format "{{.ID}}")

        echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${BLUE}║                  🐳 DOCKER SERVICE STARTED                     ║${NC}"
        echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}SERVICE${NC}    : ${CYAN}$APP_NAME${NC}"
        echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}CONTAINER${NC}  : ${GREEN}$CONTAINER_ID${NC}"
        echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}STATUS${NC}     : ${GREEN}$CONTAINER_STATUS${NC}"
        echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}LOG${NC}        : ${YELLOW}$LOG_PATH/${NC}"
        echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"

    elif [ "$INIT_SYSTEM" = "sysvinit" ]; then
        local INIT_SCRIPT="/etc/init.d/$APP_NAME"

        cat <<EOF > "$INIT_SCRIPT"
#!/bin/bash
# chkconfig: 2345 20 80
# description: $APP_NAME Docker Container Service

case "\$1" in
    start)
        cd $DEST_DIR
        $DOCKER_COMPOSE_CMD -f $COMPOSE_FILE up -d
        ;;
    stop)
        cd $DEST_DIR
        $DOCKER_COMPOSE_CMD -f $COMPOSE_FILE down
        ;;
    restart)
        \$0 stop
        \$0 start
        ;;
    status)
        docker ps -f "name=${APP_NAME}-app"
        ;;
    *)
        echo "사용법: \$0 {start|stop|restart|status}"
        exit 1
esac
exit 0
EOF
        chmod +x "$INIT_SCRIPT"

        if command -v chkconfig >/dev/null 2>&1; then
            chkconfig --add $APP_NAME
            chkconfig $APP_NAME on
        elif command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d $APP_NAME defaults
        fi

        log_success "서비스가 등록되었습니다 (sysvinit)."
        service $APP_NAME restart
    fi
}

# @description Docker Compose 명령어 감지 (docker compose vs docker-compose)
detect_docker_compose_cmd() {
    local DOCKER_BIN
    DOCKER_BIN=$(command -v docker)
    if [ -z "$DOCKER_BIN" ]; then
        log_error "Docker 실행 파일을 찾을 수 없습니다."
        exit 1
    fi

    if $DOCKER_BIN compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="$DOCKER_BIN compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD=$(command -v docker-compose)
    else
        log_error "Docker Compose를 찾을 수 없습니다."
        exit 1
    fi
}

# ============================================================
# 공통 유틸리티 함수
# ============================================================

# @description Cron 작업 등록
register_cron() {
    log_step "Cron 작업 등록..."
    local SRC_CRON_FILE=""

    if [ "$DEPLOY_MODE" = "docker" ]; then
        SRC_CRON_FILE="$DEST_DIR/cron/crond"
    else
        SRC_CRON_FILE="$PKG_ROOT/bin/cron/crond"
    fi

    local TARGET_CRON_FILE="/etc/cron.d/$APP_NAME"

    if [ -d "/etc/cron.d" ] && [ -f "$SRC_CRON_FILE" ]; then
        sed -e "s|@REAL_USER@|$REAL_USER|g" \
            -e "s|@LOG_PATH@|$LOG_PATH|g" \
            -e "s|@APP_NAME@|$APP_NAME|g" \
            "$SRC_CRON_FILE" > "$TARGET_CRON_FILE"

        chmod 644 "$TARGET_CRON_FILE"
        log_success "Cron 작업이 등록되었습니다: $TARGET_CRON_FILE"
    else
        if [ ! -d "/etc/cron.d" ]; then
            log_warning "/etc/cron.d 디렉토리가 존재하지 않습니다."
        fi
        if [ ! -f "$SRC_CRON_FILE" ]; then
            log_warning "Cron 설정 템플릿을 찾을 수 없습니다: $SRC_CRON_FILE"
        fi
        log_warning "Cron 등록을 건너뜁니다."
    fi
}

# @description tail-log 편의 스크립트 생성
create_tail_log_script() {
    log_step "유틸리티 스크립트 생성 중..."
    local USER_BIN="$USER_HOME/bin"
    if [ ! -d "$USER_BIN" ]; then
        log_info "사용자 bin 디렉토리 생성: $USER_BIN"
        mkdir -p "$USER_BIN"
        chown $REAL_USER:$SERVICE_GROUP "$USER_BIN"
    fi

    local TAIL_SCRIPT_NAME="tail-log-${APP_NAME}.sh"
    local TARGET_TAIL_SCRIPT="$USER_BIN/$TAIL_SCRIPT_NAME"

    if [ "$DEPLOY_MODE" = "docker" ]; then
        cat <<EOF > "$TARGET_TAIL_SCRIPT"
#!/bin/bash
# Docker 로그 확인 스크립트
LOG_FILE="$LOG_PATH/${APP_NAME}.log"

if [ -f "\$LOG_FILE" ]; then
    echo "로그 파일($LOG_PATH/${APP_NAME}.log)을 추적합니다..."
    tail -F -n 1000 "\$LOG_FILE"
else
    echo "로그 파일이 아직 생성되지 않았거나 경로가 다릅니다."
    echo "Docker 컨테이너 로그를 확인합니다..."
    docker logs -f --tail 1000 ${APP_NAME}-app
fi
EOF
    else
        cat <<EOF > "$TARGET_TAIL_SCRIPT"
#!/bin/bash
LOG_FILE="$LOG_PATH/${APP_NAME}.log"
if [ ! -f "\$LOG_FILE" ]; then
    echo "로그 파일을 찾을 수 없습니다: \$LOG_FILE"
    echo "서비스가 실행 중인지 확인해주세요."
    exit 1
fi
tail -F -n 1000 "\$LOG_FILE"
EOF
    fi

    chown $REAL_USER:$SERVICE_GROUP "$TARGET_TAIL_SCRIPT"
    chmod +x "$TARGET_TAIL_SCRIPT"
    log_success "로그 확인 스크립트 생성 완료: $TARGET_TAIL_SCRIPT"

    register_path
}

# @description PATH 환경 변수 등록 (~/.zshrc, ~/.bashrc 등)
register_path() {
    log_step "PATH 환경 변수 등록"
    local USER_BIN="$USER_HOME/bin"

    # 쉘 프로파일 파일 목록
    local RC_FILES=(".zshrc" ".bashrc" ".bash_profile" ".profile")

    # 1. 현재 sudo 세션의 PATH에 이미 포함된 경우
    if [[ ":$PATH:" == *":$USER_BIN:"* ]]; then
        log_info "PATH에 이미 $USER_BIN 이 포함되어 있습니다."
        return
    fi

    # 2. sudo로 실행 시 $PATH에 없더라도 프로파일에 이미 등록된 경우 체크
    local ALREADY_REGISTERED=0
    local REGISTERED_FILE=""
    for rcfile in "${RC_FILES[@]}"; do
        local profile="$USER_HOME/$rcfile"
        if [ -f "$profile" ] && grep -q "$USER_BIN" "$profile" 2>/dev/null; then
            ALREADY_REGISTERED=1
            REGISTERED_FILE="~/$rcfile"
            break
        fi
    done

    if [ "$ALREADY_REGISTERED" -eq 1 ]; then
        log_info "$USER_BIN 이 $REGISTERED_FILE 에 이미 등록되어 있습니다."
        log_info "(sudo 실행 환경이라 현재 세션 PATH에는 반영되지 않습니다. 정상입니다.)"
        return
    fi

    # 3. 미등록 → 프로파일 파일에 추가
    log_info "현재 PATH에 $USER_BIN 이 포함되어 있지 않습니다. 등록합니다."

    local UPDATED=0
    for rcfile in "${RC_FILES[@]}"; do
        if add_path_to_profile "$USER_HOME/$rcfile" "$USER_BIN"; then
            UPDATED=1
        fi
    done

    if [ $UPDATED -eq 1 ]; then
        export PATH="$PATH:$USER_BIN"
        log_success "현재 설치 세션에 PATH가 적용되었습니다."
        log_warning "새로운 터미널부터는 자동으로 적용되지만,"
        log_warning "현재 열려있는 터미널에 즉시 적용하려면 다음 명령을 실행해주세요:"

        if [[ "$SHELL" == *"zsh"* ]]; then
             echo -e "    ${BOLD}source ~/.zshrc${NC}"
        else
             echo -e "    ${BOLD}source ~/.bashrc${NC}"
        fi
    elif [ ! -f "$USER_HOME/.zshrc" ] && [ ! -f "$USER_HOME/.bashrc" ]; then
        log_warning "쉘 설정 파일을 찾을 수 없어 PATH를 자동 등록하지 못했습니다."
        log_info "수동으로 추가해주세요: export PATH=\"\$PATH:$USER_BIN\""
    fi
}


# @description Legacy 배포 완료 후 서비스 상태 확인
check_legacy_service_status() {
    sleep 2
    local CURRENT_PID
    CURRENT_PID=$(systemctl show --property MainPID --value $APP_NAME)

    local DETECTED_PORT="Unknown"
    if command -v ss >/dev/null 2>&1; then
        local SS_OUT
        SS_OUT=$(ss -tlnp | grep "pid=$CURRENT_PID")
        if [ -n "$SS_OUT" ]; then
            DETECTED_PORT=$(echo "$SS_OUT" | awk '{print $4}' | awk -F':' '{print $NF}')
        fi
    fi

    if [ "$DETECTED_PORT" = "Unknown" ] || [ -z "$DETECTED_PORT" ]; then
        local APP_YML="$DEST_DIR/config/application.yml"
        if [ -f "$APP_YML" ]; then
            local PARSED_PORT
            PARSED_PORT=$(grep -E "^\s*port:\s*[0-9]+" "$APP_YML" | awk '{print $2}')
            if [ -n "$PARSED_PORT" ]; then
                DETECTED_PORT="$PARSED_PORT (Configured)"
            fi
        fi
    fi

    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                  🚀 SERVICE STARTED                            ║${NC}"
    echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}SERVICE${NC} : ${CYAN}$APP_NAME${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PID${NC}     : ${GREEN}$CURRENT_PID${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PORT${NC}    : ${GREEN}$DETECTED_PORT${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}LOG${NC}     : ${YELLOW}$LOG_PATH/${APP_NAME}.log${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

# --- [Execution] ---

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
  echo "Error: 이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

install_service
