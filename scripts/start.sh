#!/bin/bash
# ==============================================================================
# File: start.sh
# Description: 서비스 시작 스크립트
# Author: 윤명준 (MJ Yun)
# Since: 2026-02-11
# ==============================================================================

# --- [Script Init] ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 부트스트랩 (유틸리티 로드 및 폴백)
source "$SCRIPT_DIR/bootstrap.sh"

# --- [Constants & Variables] ---
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_LOC="$PROJECT_ROOT/config/"

# .env 로드 (LOG_PATH, PID_FILE 등)
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi
LOG_PATH="${LOG_PATH:-$PROJECT_ROOT/log}"
PID_FILE="${PID_FILE:-$SCRIPT_DIR/application.pid}"

# @var APP_NAME 애플리케이션 이름 (Gradle 빌드 시 치환)
APP_NAME="@appName@"
# @var JAR_FILE 실행할 JAR 파일 경로
JAR_FILE=$(find "$PROJECT_ROOT/libs" -name "*.jar" | head -n 1)

if [ -z "$JAR_FILE" ]; then
  echo "오류: $PROJECT_ROOT/libs 경로에서 애플리케이션 JAR 파일을 찾을 수 없습니다."
  exit 1
fi

log_step "애플리케이션을 시작합니다..."
log_info "JAR 파일: $JAR_FILE"
log_info "설정 경로: $CONFIG_LOC"
log_info "로그 경로: $LOG_PATH"

# 애플리케이션 실행
log_step "애플리케이션을 시작합니다..."

# 포트 정보 파싱 (application.yml)
SERVER_PORT="8080" # 기본값
APP_YML="$PROJECT_ROOT/config/application.yml"
if [ -f "$APP_YML" ]; then
   # 간단한 파싱: "port: 1234" 형태 검색
   DETECTED_PORT=$(grep -E "^\s*port:\s*[0-9]+" "$APP_YML" | awk '{print $2}')
   if [ -n "$DETECTED_PORT" ]; then
       SERVER_PORT="$DETECTED_PORT"
   fi
fi

# 공통 실행 옵션
# 주의: spring.config.location이 디렉토리일 경우 끝에 /가 있어야 함
JAVA_OPTS=(
    "-Dspring.config.location=$CONFIG_LOC"
    "-Dapp.name=$APP_NAME"
    "-Dlog.path=$LOG_PATH"
    "-Dlogging.config=$PROJECT_ROOT/config/log4j2.yml"
    $EXTRA_JAVA_OPTS
)

# Docker 환경 감지 및 실행 분기
IS_DOCKER=false

# 1. 파일 시스템 증거 (조작 불가)
HAS_MOUNT_EVIDENCE=false
# /proc/1/mountinfo에 컨테이너 특유의 파일 시스템(overlay 등) 흔적이 있는지 확인
if grep -qE '(docker|overlay|containerd)' /proc/1/mountinfo 2>/dev/null; then
    HAS_MOUNT_EVIDENCE=true
fi

# 2. 프로세스 증거 (조작 불가)
HAS_PID_EVIDENCE=false
if [ -f /proc/1/comm ]; then
    PID1_COMM=$(cat /proc/1/comm 2>/dev/null)
    # PID 1이 호스트 OS의 기본 init 프로세스(systemd, init)가 아니라면 증거로 채택
    if [[ "$PID1_COMM" != "systemd" && "$PID1_COMM" != "init" ]]; then
        HAS_PID_EVIDENCE=true
    fi
fi

# 3. 스크립트 단독 실행 증거 (컨테이너 Entrypoint에서 직접 실행된 경우)
# 이 경우는 PID 1 자체가 이 스크립트이므로 강력한 컨테이너 증거가 됨
IS_DIRECT_ENTRYPOINT=false
if [ "$$" -eq 1 ]; then
    IS_DIRECT_ENTRYPOINT=true
fi

# ⚖️ 최종 판별 (AND 로직 적용)
# A. 마운트 증거와 PID 1 증거가 '모두' 참이거나 (일반적인 Docker 환경)
# B. 스크립트 자체가 PID 1로 직접 실행된 경우 (알파인 등에서 직접 쉘 호출)
if [ "$HAS_MOUNT_EVIDENCE" = true ] && [ "$HAS_PID_EVIDENCE" = true ]; then
    IS_DOCKER=true
elif [ "$IS_DIRECT_ENTRYPOINT" = true ]; then
    IS_DOCKER=true
fi

if [ "$IS_DOCKER" = true ]; then
    log_info "Docker 환경 감지: 포그라운드 모드로 실행합니다."
    
    # 실행 정보 출력 (Docker)
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                  🚀 DOCKER EXECUTION SUMMARY                   ║${NC}"
    echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}MODE${NC}    : ${CYAN}FOREGROUND (exec)${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}APP${NC}     : ${CYAN}$APP_NAME${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PORT${NC}    : ${GREEN}$SERVER_PORT${NC} (Configured)"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}LOG${NC}     : ${YELLOW}$LOG_PATH/${APP_NAME}.log${NC} (Console + File)"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"

    # APP_NAME에서 특수문자, 공백, 대문자를 제거하여 안전한 Linux 계정명 생성
    CLEAN_APP_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    APP_USER="${CLEAN_APP_NAME}user"

    # APP_UID / APP_GID 환경 변수가 있으면 해당 UID/GID로 ${APP_USER} 권한 변경
    if [ -n "$APP_UID" ] && [ -n "$APP_GID" ]; then
        log_info "전달된 APP_UID($APP_UID), APP_GID($APP_GID)에 맞게 ${APP_USER} 권한을 조정합니다."
        groupmod -o -g "$APP_GID" "${APP_USER}" 2>/dev/null || true
        usermod -o -u "$APP_UID" "${APP_USER}" 2>/dev/null || true
    fi

    # 디렉토리 권한 설정 (Docker 볼륨 마운트 시 root 소유권 문제 해결)
    if id "${APP_USER}" &>/dev/null; then
        log_info "${APP_USER} 권한으로 애플리케이션을 실행합니다."
        
        # CHOWN_DIRS 환경변수가 있으면 해당 디렉토리들을 순회하며 권한 변경
        if [ -n "$CHOWN_DIRS" ]; then
            log_info "동적 디렉토리 권한 변경 처리 (CHOWN_DIRS: $CHOWN_DIRS)"
            for DIR in $CHOWN_DIRS; do
                mkdir -p "$DIR" 2>/dev/null || true
                chown -R "${APP_USER}:${APP_USER}" "$DIR" 2>/dev/null || true
            done
        else
            # 하위 호환성을 위해 기존 로직 유지
            mkdir -p "$LOG_PATH"
            chown -R "${APP_USER}:${APP_USER}" "$LOG_PATH"
            chown -R "${APP_USER}:${APP_USER}" "$PROJECT_ROOT/config" 2>/dev/null || true
        fi
        
        # exec로 프로세스 대체 (PID 1 유지) 및 su-exec로 권한 강등
        exec su-exec "${APP_USER}" java -jar "${JAVA_OPTS[@]}" "$JAR_FILE"
    else
        log_info "${APP_USER}를 찾을 수 없어 기본 권한으로 실행합니다."
        # exec로 프로세스 대체 (PID 1 유지)
        exec java -jar "${JAVA_OPTS[@]}" "$JAR_FILE"
    fi
else
    # 일반 환경: nohup을 사용하여 백그라운드에서 실행 유지
    nohup java -jar "${JAVA_OPTS[@]}" "$JAR_FILE" > /dev/null 2>&1 &
    PID=$!

    # PID 파일 디렉토리 확인 및 생성 (source 트리 등 대응)
    PID_DIR=$(dirname "$PID_FILE")
    if [ ! -d "$PID_DIR" ] && [ -w "$(dirname "$PID_DIR")" ]; then
        mkdir -p "$PID_DIR"
    fi

    echo $PID > "$PID_FILE"
    
    log_success "애플리케이션이 시작되었습니다."

    # 실행 정보 출력 (General)
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                  🚀 EXECUTION SUMMARY                          ║${NC}"
    echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PID${NC}     : ${GREEN}$PID${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PORT${NC}    : ${GREEN}$SERVER_PORT${NC} (Configured)"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}APP${NC}     : ${CYAN}$APP_NAME${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}LOG${NC}     : ${YELLOW}$LOG_PATH/${APP_NAME}.log${NC}"
    echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 📋 ${BOLD}COMMAND${NC} :${NC}"
    echo -e "${BOLD}${BLUE}║${NC} nohup java -jar ${JAVA_OPTS[*]} \"$JAR_FILE\""
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
fi
