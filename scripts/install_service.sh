#!/bin/bash
# ==============================================================================
# File: install_service.sh
# Description: 서비스 설치 및 실행 스크립트 (Systemd/SysVinit 지원)
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
    # Fallback functions if utils.sh is not found
    echo "Warning: utils.sh not found at $UTILS_PATH. Using basic logging."
    # Define basic logging functions
    # ANSI color codes
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color

    log_header() { echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}"; }
    log_step() { echo -e "\n${BOLD}➡️  $1${NC}"; }
    log_info() { echo -e "   ${CYAN}ℹ️  $1${NC}"; }
    log_success() { echo -e "${GREEN}✅  $1${NC}"; }
    log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
    log_error() { echo -e "${RED}❌  $1${NC}"; exit 1; }
    # Dummy add_path_to_profile for fallback
    add_path_to_profile() { return 1; }
fi

# --- [Constants & Variables] ---
# @appName@은 Gradle 빌드 시 실제 프로젝트 이름으로 치환됨
APP_NAME="@appName@"
# 배포 패키지 루트 (build/dist/XXX)
PKG_ROOT="$(dirname "$SCRIPT_DIR")"

# 기본 설치 위치 정의 (환경 변수 INSTALL_DIR 또는 첫 번째 인자로 재정의 가능)
DEFAULT_INSTALL_DIR="${1:-${INSTALL_DIR:-/opt/$APP_NAME}}"

# 실행 유저 확인 (sudo로 실행 시 실제 유저)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
SERVICE_GROUP=$(id -gn $REAL_USER)

# 전역 변수 (함수 내에서 설정됨)
DEST_DIR=""
LOG_PATH=""

# --- [Functions] ---

# @description 서비스 설치 메인 함수
install_service() {
    log_header "서비스 설치 시작 ($APP_NAME)"

    # 사전 요구사항 확인
    check_prerequisites

    # 설치 위치 결정 (기존 설치 감지 포함)
    determine_install_dir

    # 파일 복사
    copy_files

    # 환경 설정 및 로그 경로
    configure_env

    # 서비스 등록
    register_service
    
    log_header "설치 완료"
}

# @description 설치 사전 요구사항 점검 (Java 등)
check_prerequisites() {
    log_step "사전 요구사항 확인"
    # Java 설치 확인
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
         # init 스크립트에서 실행 경로 추출 시도 (su - user -c "SCRIPT")
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
    
    chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"
    log_success "설치 디렉토리 준비 완료."
}

# @description 배포 파일 복사 (bin, libs, config)
copy_files() {
    log_step "파일 복사 및 배포 중..."
    
    # 1. Libs (Jar)
    # 기존 파일 덮어쓰기
    cp -f "$PKG_ROOT/libs/"*.jar "$DEST_DIR/libs/"
    
    # 2. Bin Scripts
    # install_service.sh 제외하고 나머지 스크립트 복사
    find "$SCRIPT_DIR" -maxdepth 1 -name "*.sh" ! -name "install_service.sh" -exec cp -f {} "$DEST_DIR/bin/" \;
    
    # 3. Utils & Hidden Files
    if [ -f "$SCRIPT_DIR/.app-env.properties" ]; then
        cp -f "$SCRIPT_DIR/.app-env.properties" "$DEST_DIR/bin/"
    fi
    # utils.sh가 SCRIPT_DIR에 있다면 복사 (개발 환경 등 고려)
    if [ -f "$SCRIPT_DIR/utils.sh" ]; then
         cp -f "$SCRIPT_DIR/utils.sh" "$DEST_DIR/bin/"
    elif [ -f "$UTILS_PATH" ]; then
         cp -f "$UTILS_PATH" "$DEST_DIR/bin/"
    fi
    
    # 4. Config
    # 배포 패키지에 포함된 설정 파일로 덮어씁니다.
    cp -rf "$PKG_ROOT/config/"* "$DEST_DIR/config/"
    
    # 권한 설정 (실행 스크립트)
    chmod +x "$DEST_DIR/bin/"*.sh
    chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"
    log_success "파일 복사 및 권한 설정 완료."
}

# @description 환경 변수 설정 및 로그 경로 확인
configure_env() {
    log_step "환경 설정 및 로그 경로 확인"
    
    # properties 파일 확인 (복사된 파일 기준)
    DEST_PROP_FILE="$DEST_DIR/bin/.app-env.properties"
    
    # 만약 파일이 없으면 생성
    if [ ! -f "$DEST_PROP_FILE" ]; then
        mkdir -p "$(dirname "$DEST_PROP_FILE")"
        echo "# Application Deployment Configuration" > "$DEST_PROP_FILE"
        chmod 644 "$DEST_PROP_FILE"
        chown $REAL_USER:$SERVICE_GROUP "$DEST_PROP_FILE"
        log_info "새로운 환경 설정 파일 생성: $DEST_PROP_FILE"
    fi

    # 현재 파일 로드
    LOG_PATH=""
    if [ -f "$DEST_PROP_FILE" ]; then
        # DEST_DIR context에서 로드하기 위해 변수 치환 필요할 수 있으나, 
        # 여기서는 단순 값 읽기가 목적
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
        
        # 파일에 저장
        if grep -q "^LOG_PATH=" "$DEST_PROP_FILE"; then
            sed -i "/^LOG_PATH=/c\LOG_PATH=\"$LOG_PATH\"" "$DEST_PROP_FILE"
        else
            echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP_FILE"
        fi
        chown $REAL_USER:$SERVICE_GROUP "$DEST_PROP_FILE"
        log_info "환경 설정 파일에 LOG_PATH 저장 완료."
    fi

    log_info "로그 경로: $LOG_PATH"

    # 로그 디렉토리 생성 및 권한
    mkdir -p "$LOG_PATH"
    chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"
    chmod 777 "$LOG_PATH" # 로그는 넓은 권한 허용 (필요 시 조정)
    log_success "로그 디렉토리 준비 완료."

    # tail-log 스크립트 생성
    create_tail_log_script
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
    log_success "로그 확인 스크립트 생성 완료: $TARGET_TAIL_SCRIPT"

    # PATH 자동 등록 (utils.sh 함수 사용)
    register_path
}

register_path() {
    log_step "PATH 환경 변수 등록"
    USER_BIN="$USER_HOME/bin"
    if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
        log_info "현재 PATH에 $USER_BIN 이 포함되어 있지 않습니다."
        
        UPDATED=0
        # 주요 프로필 파일 확인 (존재하는 모든 설정 파일에 추가 시도)
        for rcfile in ".zshrc" ".bashrc" ".bash_profile" ".profile"; do
            if add_path_to_profile "$USER_HOME/$rcfile" "$USER_BIN"; then
                UPDATED=1
            fi
        done
        
        if [ $UPDATED -eq 1 ]; then
            # 현재 스크립트 세션에 즉시 적용
            export PATH="$PATH:$USER_BIN"
            log_success "현재 설치 세션에 PATH가 적용되었습니다."

            log_warning "새로운 터미널부터는 자동으로 적용되지만,"
            log_warning "현재 열려있는 터미널에 즉시 적용하려면 다음 명령을 실행해주세요:"
            
            # 쉘 감지하여 적절한 명령어 안내
            if [[ "$SHELL" == *"zsh"* ]]; then
                 echo -e "    ${BOLD}source ~/.zshrc${NC}"
            else
                 echo -e "    ${BOLD}source ~/.bashrc${NC}"
            fi
        elif [ ! -f "$USER_HOME/.zshrc" ] && [ ! -f "$USER_HOME/.bashrc" ]; then
            log_warning "쉘 설정 파일을 찾을 수 없어 PATH를 자동 등록하지 못했습니다."
            log_info "수동으로 추가해주세요: export PATH=\"\$PATH:$USER_BIN\""
        fi
    else
        log_info "PATH에 이미 $USER_BIN 이 포함되어 있습니다."
    fi
}

register_service() {
    log_step "서비스 등록 및 시작..."
    START_SCRIPT="$DEST_DIR/bin/start.sh"
    STOP_SCRIPT="$DEST_DIR/bin/stop.sh"

    # Init 시스템 감지
    INIT_SYSTEM="unknown" # Default to unknown
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif [ -f /etc/init.d/cron ] || [ -f /etc/init.d/functions ]; then # Common SysVinit indicators
        INIT_SYSTEM="sysvinit"
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

        log_success "$SERVICE_FILE 파일이 갱신되었습니다."
        systemctl daemon-reload
        systemctl enable $APP_NAME
        # 이미 실행 중인 경우 재시작할지 물어보거나 자동 재시작
        if systemctl is-active --quiet $APP_NAME; then
            log_info "서비스가 실행 중입니다. 재시작합니다..."
            systemctl restart $APP_NAME
        else
            systemctl start $APP_NAME
            log_success "서비스가 시작되었습니다."
        fi

        # Cron 작업 등록
        register_cron
        
        # 상태 확인
        check_service_status

    elif [ "$INIT_SYSTEM" == "sysvinit" ]; then
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

register_cron() {
    log_step "Cron 작업 등록..."
    SRC_CRON_FILE="$PKG_ROOT/bin/cron/crond"
    TARGET_CRON_FILE="/etc/cron.d/$APP_NAME"
    
    if [ -d "/etc/cron.d" ] && [ -f "$SRC_CRON_FILE" ]; then
        # 템플릿 파일 복사 및 변수 치환 (@REAL_USER@, @LOG_PATH@, @APP_NAME@)
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

check_service_status() {
    # 서비스 상태 확인 및 정보 출력
    sleep 2 # 서비스 구동 대기
    CURRENT_PID=$(systemctl show --property MainPID --value $APP_NAME)
    
    # 포트 확인 (ss 명령어가 있다면 사용, 없으면 설정 파일 추정)
    DETECTED_PORT="Unknown"
    if command -v ss >/dev/null 2>&1; then
        # MainPID로 리스닝 포트 검색
        SS_OUT=$(ss -tlnp | grep "pid=$CURRENT_PID")
        if [ -n "$SS_OUT" ]; then
             DETECTED_PORT=$(echo "$SS_OUT" | awk '{print $4}' | awk -F':' '{print $NF}')
        fi
    fi
    
    # ss로 못 찾았으면 설정 파일에서 파싱
    if [ "$DETECTED_PORT" == "Unknown" ] || [ -z "$DETECTED_PORT" ]; then
        APP_YML="$DEST_DIR/config/application.yml"
        if [ -f "$APP_YML" ]; then
             # 간단한 파싱: "port: 1234" 형태 검색
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
