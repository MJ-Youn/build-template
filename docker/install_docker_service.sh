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
    echo -e "\n${BOLD}${BLUE}================================================================${NC}"
    echo -e "${BOLD}${BLUE}🐳  $1 ${NC}"
    echo -e "${BOLD}${BLUE}================================================================${NC}"
}
log_step() { echo -e "${BOLD}${CYAN}➡️  $1${NC}"; }
log_info() { echo -e "   ℹ️  $1"; }
log_success() { echo -e "${BOLD}${GREEN}✅  $1${NC}"; }
log_warning() { echo -e "${BOLD}${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${BOLD}${RED}❌  $1${NC}"; }

# --- [Script Start] ---

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
  log_error "이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# @appName@은 Gradle 빌드 시 실제 프로젝트 이름으로 치환됨
APP_NAME="@appName@"
IMAGE_TAR="$SCRIPT_DIR/${APP_NAME}.tar"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# 실행 유저 확인 (sudo로 실행 시 실제 유저)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
SERVICE_GROUP=$(id -gn $REAL_USER)

log_header "Docker 서비스 설치 시작 ($APP_NAME)"

# Docker 설치 확인
if ! command -v docker &> /dev/null; then
    log_error "Docker가 설치되어 있지 않습니다. Docker를 먼저 설치해주세요."
    exit 1
fi

# .app-env.properties 로드
PROP_FILE="$SCRIPT_DIR/.app-env.properties"
LOG_PATH=""

if [ -f "$PROP_FILE" ]; then
    log_info "환경 설정 파일 로드: $PROP_FILE"
    source "$PROP_FILE"
else
    log_warning "환경 설정 파일을 찾을 수 없습니다: $PROP_FILE"
fi

# LOG_PATH 설정 (properties에 없으면 사용자 입력)
if [ -z "$LOG_PATH" ]; then
    DEFAULT_LOG_PATH="/var/log/$APP_NAME"
    log_info "기본 로그 경로: $DEFAULT_LOG_PATH"
    read -p "   📝 로그 경로를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOG_PATH
    LOG_PATH="${INPUT_LOG_PATH:-$DEFAULT_LOG_PATH}"
fi

log_info "로그 경로: $LOG_PATH"

# 로그 디렉토리 생성
mkdir -p "$LOG_PATH"
chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"

# Docker 이미지 로드
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

# docker-compose.yml 변수 치환
log_step "docker-compose.yml 설정 중..."
if [ ! -f "$COMPOSE_FILE" ]; then
    log_error "docker-compose.yml 파일을 찾을 수 없습니다: $COMPOSE_FILE"
    exit 1
fi

# 임시 파일에 치환된 내용 저장
TEMP_COMPOSE="/tmp/${APP_NAME}-docker-compose.yml"
sed -e "s|@LOG_PATH@|$LOG_PATH|g" \
    -e "s|@APP_NAME@|$APP_NAME|g" \
    "$COMPOSE_FILE" > "$TEMP_COMPOSE"

# 원본 파일에 덮어쓰기
mv "$TEMP_COMPOSE" "$COMPOSE_FILE"
log_success "설정 파일 업데이트 완료"

# Init 시스템 감지
if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
elif [ -f /etc/init.d/cron ] || [ -f /etc/init.d/functions ]; then
    INIT_SYSTEM="sysvinit"
else
    log_error "알 수 없는 Init 시스템입니다."
    exit 1
fi

# Docker Compose 명령어 감지
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD=$(command -v docker-compose)
else
    log_error "Docker Compose를 찾을 수 없습니다."
    exit 1
fi

log_info "Docker Compose 명령어: $DOCKER_COMPOSE_CMD"

# Systemd/SysVinit 서비스 등록
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
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/env $DOCKER_COMPOSE_CMD -f $COMPOSE_FILE up -d
ExecStop=/usr/bin/env $DOCKER_COMPOSE_CMD -f $COMPOSE_FILE down
Restart=on-failure
User=$REAL_USER
Group=$SERVICE_GROUP

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

    # Cron 작업 등록 (로그 정리)
    log_step "Cron 작업 등록..."
    SRC_CRON_FILE="$SCRIPT_DIR/cron/crond"
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
        cd $SCRIPT_DIR
        /usr/bin/docker-compose -f $COMPOSE_FILE up -d
        ;;
    stop)
        cd $SCRIPT_DIR
        /usr/bin/docker-compose -f $COMPOSE_FILE down
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

log_header "설치 완료"
