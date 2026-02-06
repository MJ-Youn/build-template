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

# 실행 유저 확인 (sudo로 실행 시 실제 유저)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
SERVICE_GROUP=$(id -gn $REAL_USER)

echo "=== 서비스 설치 시작 ($APP_NAME) ==="

# 기존 설치 감지
PREVIOUS_INSTALL_LOC=""
if command -v systemctl >/dev/null 2>&1; then
    SERVICE_PATH=$(systemctl show -p FragmentPath "$APP_NAME.service" 2>/dev/null | cut -d= -f2)
    if [ -f "$SERVICE_PATH" ]; then
        # ExecStart 라인에서 실제 실행 스크립트 경로 추출
        EXEC_START=$(grep "ExecStart=" "$SERVICE_PATH" | cut -d= -f2)
        if [ -n "$EXEC_START" ]; then
             # .../bin/start.sh -> .../bin -> 부모 디렉토리
             PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
        fi
    fi
elif [ -f "/etc/init.d/$APP_NAME" ]; then
     # init 스크립트에서 실행 경로 추출 시도
     EXEC_START=$(grep "su - $REAL_USER -c" "/etc/init.d/$APP_NAME" | head -n 1 | awk -F '"' '{print $2}')
      if [ -n "$EXEC_START" ]; then
             PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
        fi
fi

DEST_DIR=""
if [ -n "$PREVIOUS_INSTALL_LOC" ] && [ -d "$PREVIOUS_INSTALL_LOC" ]; then
    echo "기존 설치 위치가 감지되었습니다: $PREVIOUS_INSTALL_LOC"
    read -p "기존 위치에 재배포하시겠습니까? [Y/n] " REUSE_LOC
    REUSE_LOC=${REUSE_LOC:-Y}
    if [[ "$REUSE_LOC" =~ ^[Yy]$ ]]; then
        DEST_DIR="$PREVIOUS_INSTALL_LOC"
    fi
fi

if [ -z "$DEST_DIR" ]; then
    echo "기존 설치 위치를 사용하지 않거나 찾지 못했습니다."
    echo "기본 설치 위치: /opt/$APP_NAME"
    read -p "설치할 위치를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOC
    if [ -z "$INPUT_LOC" ]; then
        DEST_DIR="/opt/$APP_NAME"
    else
        DEST_DIR="$INPUT_LOC"
    fi
fi

echo "설치 위치: $DEST_DIR"
echo "서비스 실행 유저: $REAL_USER"

# 디렉토리 생성
echo "디렉토리 생성 중..."
mkdir -p "$DEST_DIR/bin"
mkdir -p "$DEST_DIR/config"
# 로그 경로 설정 로직
# 1. properties 파일에서 확인
LOG_PATH=""
PROP_FILE="$PKG_ROOT/bin/.app-env.properties"

if [ -f "$PROP_FILE" ]; then
    # PROJECT_ROOT를 DEST_DIR로 치환하여 평가 필요
    PROJECT_ROOT="$DEST_DIR"
    # source로 변수 로드 (LOG_PATH)
    source "$PROP_FILE"
fi

# 2. properties에 없으면 사용자 입력
if [ -z "$LOG_PATH" ]; then
    DEFAULT_LOG_PATH="$DEST_DIR/log"
    echo "기본 로그 경로: $DEFAULT_LOG_PATH"
    read -p "로그 경로를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOG_PATH
    LOG_PATH="${INPUT_LOG_PATH:-$DEFAULT_LOG_PATH}"
    
    # 입력받은 값을 properties 파일에 저장 (선택 사항)
    # 여기서는 앱 구동 시 start.sh가 사용할 수 있도록 properties 파일을 수정하거나 생성해야 함.
    # 하지만 PKG_ROOT의 bin은 이미 복사되었음 ($DEST_DIR/bin).
    # 따라서 대상 디렉토리의 properties를 업데이트해야 함.
    DEST_PROP_FILE="$DEST_DIR/bin/.app-env.properties"
    
    # 만약 properties 파일이 없으면 생성
    if [ ! -f "$DEST_PROP_FILE" ]; then
        mkdir -p "$(dirname "$DEST_PROP_FILE")"
        echo "# Application Deployment Configuration" > "$DEST_PROP_FILE"
    fi
    
    # LOG_PATH 추가 (기존 값 있으면 덮어쓰기는 복잡하므로, 일단 추가/수정 로직 간단히)
    # sed로 LOG_PATH 라인이 있으면 변경, 없으면 추가
    if grep -q "^LOG_PATH=" "$DEST_PROP_FILE"; then
        # Mac/Linux 호환 sed (임시 파일 사용)
        grep -v "^LOG_PATH=" "$DEST_PROP_FILE" > "$DEST_PROP_FILE.tmp"
        echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP_FILE.tmp"
        mv "$DEST_PROP_FILE.tmp" "$DEST_PROP_FILE"
    else
        echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP_FILE"
    fi
else
    echo "설정 파일에 정의된 로그 경로를 사용합니다: $LOG_PATH"
fi

echo "로그 경로: $LOG_PATH"

# 디렉토리 생성
echo "디렉토리 생성 중..."
mkdir -p "$DEST_DIR/bin"
mkdir -p "$DEST_DIR/config"
mkdir -p "$LOG_PATH"
mkdir -p "$DEST_DIR/libs"

# 파일 복사
echo "파일 복사 중..."
# 기존 파일 덮어쓰기
cp -f "$PKG_ROOT/libs/"*.jar "$DEST_DIR/libs/"
cp -f "$PKG_ROOT/bin/"*.sh "$DEST_DIR/bin/"

# 설정 파일(config) 복사
# 배포 패키지에 포함된 설정 파일로 덮어씁니다.
# (사용자별 커스텀 설정 보존이 필요하다면 별도 백업 로직이 필요할 수 있습니다)
cp -rf "$PKG_ROOT/config/"* "$DEST_DIR/config/"

# 만약 위에서 사용자 입력으로 LOG_PATH가 변경되었다면, 
# 복사된 bin/.app-env.properties는 원본(빌드 시점) 파일임.
# 따라서 사용자 입력값으로 다시 갱신해줘야 함.
if [ -n "$INPUT_LOG_PATH" ]; then
    DEST_PROP_FILE="$DEST_DIR/bin/.app-env.properties"
    if grep -q "^LOG_PATH=" "$DEST_PROP_FILE"; then
        grep -v "^LOG_PATH=" "$DEST_PROP_FILE" > "$DEST_PROP_FILE.tmp"
        echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP_FILE.tmp"
        mv "$DEST_PROP_FILE.tmp" "$DEST_PROP_FILE"
    else
        echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP_FILE"
    fi
fi

# 권한 설정
chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"
# 로그 디렉토리가 DEST_DIR 외부에 있을 수 있으므로 별도 권한 설정
chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"
chmod +x "$DEST_DIR/bin/"*.sh

# tail-log 스크립트 생성 및 설치 (인라인 생성)
USER_BIN="$USER_HOME/bin"
if [ ! -d "$USER_BIN" ]; then
    echo "사용자 bin 디렉토리 생성: $USER_BIN"
    mkdir -p "$USER_BIN"
    chown $REAL_USER:$SERVICE_GROUP "$USER_BIN"
fi

TAIL_SCRIPT_NAME="tail-log-${APP_NAME}.sh"
TARGET_TAIL_SCRIPT="$USER_BIN/$TAIL_SCRIPT_NAME"

echo "로그 확인 스크립트 생성 중: $TARGET_TAIL_SCRIPT"
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

chown $REAL_USER:$SERVICE_GROUP "$TARGET_TAIL_SCRIPT"
chmod +x "$TARGET_TAIL_SCRIPT"

# PATH 안내
if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
    echo "참고: $USER_BIN 경로가 PATH 환경 변수에 없습니다. ~/.bashrc 등에 추가해주세요."
fi

# 서비스 등록
START_SCRIPT="$DEST_DIR/bin/start.sh"
STOP_SCRIPT="$DEST_DIR/bin/stop.sh"

# Init 시스템 감지
if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
elif [ -f /etc/init.d/cron ] || [ -f /etc/init.d/functions ]; then
    INIT_SYSTEM="sysvinit"
else
    echo "알 수 없는 Init 시스템입니다. 서비스 등록을 건너뜁니다."
    exit 0
fi

if [ "$INIT_SYSTEM" == "systemd" ]; then
    SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"
    
    # 서비스 파일이 이미 존재하고 내용이 같다면 skip 가능하지만, 
    # 경로가 변경되었을 수 있으므로 재생성
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
PIDFile=$DEST_DIR/bin/application.pid
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    echo "$SERVICE_FILE 파일이 갱신되었습니다."
    systemctl daemon-reload
    systemctl enable $APP_NAME
    # 이미 실행 중인 경우 재시작할지 물어보거나 자동 재시작
    if systemctl is-active --quiet $APP_NAME; then
        echo "서비스가 실행 중입니다. 재시작합니다."
        systemctl restart $APP_NAME
    else
        systemctl start $APP_NAME
        echo "서비스가 시작되었습니다."
    fi

elif [ "$INIT_SYSTEM" == "sysvinit" ]; then
    STATUS_SCRIPT="$DEST_DIR/bin/status.sh"

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
    
    echo "서비스가 등록되었습니다 (sysvinit)."
    service $APP_NAME restart
fi

echo "=== 설치 완료 ==="
