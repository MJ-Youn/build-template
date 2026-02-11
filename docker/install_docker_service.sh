#!/bin/bash
# ==============================================================================
# File: install_docker_service.sh
# Description: Docker 서비스 설치 및 실행 스크립트
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
    # utils.sh가 없으면 최소한의 로깅 함수 정의 (Fallback)
    echo "Warning: utils.sh not found at $UTILS_PATH"
    log_header() { echo "🚀  $1"; }
    log_step() { echo "➡️  $1"; }
    log_info() { echo "   ℹ️  $1"; }
    log_success() { echo "✅  $1"; }
    log_warning() { echo "⚠️  $1"; }
    log_error() { echo "❌  $1"; }
fi

# --- [Constants & Variables] ---
APP_NAME="@appName@"
IMAGE_TAR="$SCRIPT_DIR/${APP_NAME}.tar"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
PROP_FILE="$SCRIPT_DIR/.app-env.properties" # 초기 로드용

# 기본 설치 위치 정의 (환경 변수 INSTALL_DIR 또는 첫 번째 인자로 재정의 가능)
DEFAULT_INSTALL_DIR="${1:-${INSTALL_DIR:-/opt/$APP_NAME}}"

# 실행 유저 확인 (sudo로 실행 시 실제 유저)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
SERVICE_GROUP=$(id -gn $REAL_USER)

# --- [Functions] ---

# @description Docker 서비스 설치 메인 함수
install_docker_service() {
    log_header "Docker 서비스 설치 시작 ($APP_NAME)" "🐳"

    # Docker 설치 확인
    if ! command -v docker &> /dev/null; then
        log_error "Docker가 설치되어 있지 않습니다. Docker를 먼저 설치해주세요."
        exit 1
    fi

    # 설치 위치 결정
    determine_install_dir

    # 파일 복사
    copy_files

    # 환경 설정 및 로그 경로
    configure_env

    # Docker 이미지 로드
    load_docker_image

    # docker-compose.yml 설정
    configure_compose

    # 서비스 등록 (Systemd/SysVinit)
    register_service

    log_header "설치 완료"
}

# @description 설치 경로 결정 (기존 설치 감지 또는 사용자 입력)
determine_install_dir() {
    log_step "설치 위치 설정"
    
    # 기존 설치 위치 감지 로직 (Systemd)
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

    # 디렉토리 생성 및 권한 설정
    mkdir -p "$DEST_DIR"
    chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"
}

# @description 배포 파일 복사 (Docker 관련)
copy_files() {
    log_step "파일 복사 중..."
    cp "$COMPOSE_FILE" "$DEST_DIR/"
    cp "$PROP_FILE" "$DEST_DIR/" 2>/dev/null
    
    if [ -d "$SCRIPT_DIR/cron" ]; then
         cp -r "$SCRIPT_DIR/cron" "$DEST_DIR/"
    fi
    
    # uninstall 스크립트 및 utils.sh 복사
    if [ -f "$SCRIPT_DIR/uninstall_docker_service.sh" ]; then
        cp "$SCRIPT_DIR/uninstall_docker_service.sh" "$DEST_DIR/"
        chmod +x "$DEST_DIR/uninstall_docker_service.sh"
    fi
    if [ -f "$UTILS_PATH" ]; then
        cp "$UTILS_PATH" "$DEST_DIR/"
    fi
}

# @description 환경 변수 설정 (.app-env.properties)
configure_env() {
    # .app-env.properties 로드 (복사된 파일 기준)
    PROP_FILE="$DEST_DIR/.app-env.properties"
    LOG_PATH=""

    if [ -f "$PROP_FILE" ]; then
        log_info "환경 설정 파일 로드: $PROP_FILE"
        source "$PROP_FILE"
    else
        echo "# Application Deployment Configuration" > "$PROP_FILE"
    fi

    # LOG_PATH 설정
    if [ -z "$LOG_PATH" ]; then
        DEFAULT_LOG_PATH="$DEST_DIR/log"
        log_info "기본 로그 경로: $DEFAULT_LOG_PATH"
        read -p "   📝 로그 경로를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOG_PATH
        LOG_PATH="${INPUT_LOG_PATH:-$DEFAULT_LOG_PATH}"
        
        # 설정 파일에 저장
        if grep -q "^LOG_PATH=" "$PROP_FILE"; then
            grep -v "^LOG_PATH=" "$PROP_FILE" > "$PROP_FILE.tmp"
            echo "LOG_PATH=\"$LOG_PATH\"" >> "$PROP_FILE.tmp"
            mv "$PROP_FILE.tmp" "$PROP_FILE"
        else
            echo "LOG_PATH=\"$LOG_PATH\"" >> "$PROP_FILE"
        fi
    fi

    log_info "로그 경로: $LOG_PATH"

    # 로그 디렉토리 생성
    mkdir -p "$LOG_PATH"
    chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"
    chmod 777 "$LOG_PATH"
    
    # tail-log 스크립트 생성
    create_tail_log_script
}

# @description Docker 이미지 로드
load_docker_image() {
    log_step "Docker 이미지 로드 중..."
    if [ ! -f "$IMAGE_TAR" ]; then
        log_error "Docker 이미지 파일을 찾을 수 없습니다: $IMAGE_TAR"
        exit 1
    fi

    docker load -i "$IMAGE_TAR"
    if [ $? -ne 0 ]; then
        log_error "Docker 이미지 로드 실패"
        exit 1
    fi
    log_success "Docker 이미지 로드 완료"
}

# @description docker-compose.yml 설정 (포트, 볼륨 매핑)
configure_compose() {
    COMPOSE_FILE="$DEST_DIR/docker-compose.yml"
    log_step "docker-compose.yml 설정 중..."
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "docker-compose.yml 파일을 찾을 수 없습니다: $COMPOSE_FILE"
        exit 1
    fi

    # 임시 파일에 치환된 내용 저장 (sed 호환성 고려)
    TEMP_COMPOSE="/tmp/${APP_NAME}-docker-compose.yml"
    sed -e "s|@LOG_PATH@|$LOG_PATH|g" \
        -e "s|@APP_NAME@|$APP_NAME|g" \
        "$COMPOSE_FILE" > "$TEMP_COMPOSE"

    mv "$TEMP_COMPOSE" "$COMPOSE_FILE"
    log_success "설정 파일 업데이트 완료"
}

register_service() {
    # Init 시스템 감지
    INIT_SYSTEM="sysvinit" # Default fallback
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

    log_step "서비스 등록 및 시작..."

    if [ "$INIT_SYSTEM" == "systemd" ]; then
        SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"
        
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

        # Cron 작업 등록
        register_cron

        # 서비스 상태 확인
        sleep 2
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

    elif [ "$INIT_SYSTEM" == "sysvinit" ]; then
        INIT_SCRIPT="/etc/init.d/$APP_NAME"
        
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

detect_docker_compose_cmd() {
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

register_cron() {
    log_step "Cron 작업 등록..."
    SRC_CRON_FILE="$DEST_DIR/cron/crond"
    TARGET_CRON_FILE="/etc/cron.d/$APP_NAME"
    
    if [ -d "/etc/cron.d" ] && [ -f "$SRC_CRON_FILE" ]; then
        sed -e "s|@REAL_USER@|$REAL_USER|g" \
            -e "s|@LOG_PATH@|$LOG_PATH|g" \
            -e "s|@APP_NAME@|$APP_NAME|g" \
            "$SRC_CRON_FILE" > "$TARGET_CRON_FILE"
            
        chmod 644 "$TARGET_CRON_FILE"
        log_success "Cron 작업이 등록되었습니다: $TARGET_CRON_FILE"
    else
        log_warning "Cron 등록을 건너뜁니다."
    fi
}

create_tail_log_script() {
    log_step "유틸리티 스크립트 생성 중..."
    USER_BIN="$USER_HOME/bin"
    if [ ! -d "$USER_BIN" ]; then
        log_info "사용자 bin 디렉토리 생성: $USER_BIN"
        mkdir -p "$USER_BIN"
        chown $REAL_USER:$SERVICE_GROUP "$USER_BIN"
    fi

    TAIL_SCRIPT_NAME="tail-log-${APP_NAME}.sh"
    TARGET_TAIL_SCRIPT="$USER_BIN/$TAIL_SCRIPT_NAME"

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

    chown $REAL_USER:$SERVICE_GROUP "$TARGET_TAIL_SCRIPT"
    chmod +x "$TARGET_TAIL_SCRIPT"
    log_success "로그 확인 스크립트 생성 완료: $TARGET_TAIL_SCRIPT"

    # PATH 자동 등록
    log_step "PATH 환경 변수 등록"
    if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
        log_info "현재 PATH에 $USER_BIN 이 포함되어 있지 않습니다."
        
        UPDATED=0
        for rcfile in ".zshrc" ".bashrc" ".bash_profile" ".profile"; do
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
        fi
    else
        log_info "PATH에 이미 $USER_BIN 이 포함되어 있습니다."
    fi
}

# --- [Execution] ---

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
  # log_error 함수가 정의되지 않았을 수 있으므로 echo로 출력
  echo "Error: 이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

install_docker_service
