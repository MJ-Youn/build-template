#!/bin/bash

# 루트 권한 확인
if [ "$EUID" -ne 0 ]; then
  echo "이 스크립트는 root 권한으로 실행해야 합니다."
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# 배포 패키지 루트 (build/dist/XXX)
PKG_ROOT="$(dirname "$SCRIPT_DIR")"

# @appName@은 Gradle 빌드 시 실제 프로젝트 이름으로 치환됨
APP_NAME="@appName@"
SERVICE_NAME="${APP_NAME}-docker"

# 실행 유저 확인 (sudo로 실행 시 실제 유저)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
SERVICE_GROUP=$(id -gn $REAL_USER)

echo "=== Docker 서비스 설치 시작 ($SERVICE_NAME) ==="

# 1. 파일 위치 확인 (스크립트와 같은 위치에 있다고 가정)
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
IMAGE_TAR="$SCRIPT_DIR/${APP_NAME}.tar"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "오류: docker-compose.yml 파일을 찾을 수 없습니다."
    echo "스크립트와 같은 위치에 파일을 두세요."
    exit 1
fi

DEST_DIR="/opt/$APP_NAME"
echo "설치 위치: $DEST_DIR"

if [ ! -d "$DEST_DIR" ]; then
    echo "디렉토리 생성 중..."
    mkdir -p "$DEST_DIR"
fi

# 2. 파일 복사
echo "설정 파일 복사 중..."
cp "$COMPOSE_FILE" "$DEST_DIR/"

# 3. Docker 이미지 로드 (있을 경우)
if [ -f "$IMAGE_TAR" ]; then
    echo "Docker 이미지 로드 중 ($IMAGE_TAR)..."
    docker load -i "$IMAGE_TAR"
else
    echo "알림: $IMAGE_TAR 파일이 없습니다. 이미지가 이미 로드되어 있거나 레지스트리에서 pull 해야 합니다."
fi

# docker-compose 명령 확인
if command -v docker-compose >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "오류: docker-compose 또는 docker compose 명령을 찾을 수 없습니다."
    exit 1
fi

echo "Docker Compose 명령: $DOCKER_COMPOSE_CMD"

# Init 시스템 감지
if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
elif [ -f /etc/init.d/cron ] || [ -f /etc/init.d/functions ]; then
    INIT_SYSTEM="sysvinit"
else
    echo "알 수 없는 Init 시스템입니다. 서비스 등록을 건너뜁니다."
    EXIT 0
fi

if [ "$INIT_SYSTEM" == "systemd" ]; then
    SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
    
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=$APP_NAME Docker Service
Requires=docker.service
After=docker.service network.target

[Service]
User=$REAL_USER
Group=$SERVICE_GROUP
WorkingDirectory=$DEST_DIR
# 이미지가 없으면 빌드 시도 (옵션)
# ExecStartPre=$DOCKER_COMPOSE_CMD build
ExecStart=$DOCKER_COMPOSE_CMD up --remove-orphans
ExecStop=$DOCKER_COMPOSE_CMD down
Restart=always
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    echo "$SERVICE_FILE 파일이 생성되었습니다."
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    echo "서비스 시작 중..."
    systemctl start $SERVICE_NAME
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo "서비스가 성공적으로 시작되었습니다! (Systemd)"
    else
        echo "서비스 시작 실패. 로그를 확인하세요: journalctl -u $SERVICE_NAME"
    fi

elif [ "$INIT_SYSTEM" == "sysvinit" ]; then
    INIT_SCRIPT="/etc/init.d/$SERVICE_NAME"

    cat <<EOF > "$INIT_SCRIPT"
#!/bin/bash
# chkconfig: 2345 20 80
# description: $APP_NAME Docker Service

WORKING_DIR="$DEST_DIR"
COMPOSE_CMD="$DOCKER_COMPOSE_CMD"
USER="$REAL_USER"

case "\$1" in
    start)
        echo "Starting $APP_NAME Docker Service..."
        su - \$USER -c "cd \$WORKING_DIR && \$COMPOSE_CMD up -d --remove-orphans"
        ;;
    stop)
        echo "Stopping $APP_NAME Docker Service..."
        su - \$USER -c "cd \$WORKING_DIR && \$COMPOSE_CMD down"
        ;;
    restart)
        \$0 stop
        \$0 start
        ;;
    status)
        su - \$USER -c "cd \$WORKING_DIR && \$COMPOSE_CMD ps"
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
esac
exit 0
EOF

    chmod +x "$INIT_SCRIPT"
    
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add $SERVICE_NAME
        chkconfig $SERVICE_NAME on
    elif command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d $SERVICE_NAME defaults
    fi
    
    echo "서비스가 등록되었습니다 (SysVinit)."
    service $SERVICE_NAME start
fi

echo "=== 설치 완료 ==="
