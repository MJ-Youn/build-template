#!/bin/bash
# ==============================================================================
# File: start.sh
# Description: 서비스 시작 스크립트
# Author: 윤명준 (MJ Yune)
# Since: 2026-02-11
# ==============================================================================

# --- [Script Init] ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# 부트스트랩 (유틸리티 로드 및 폴백)
source "$SCRIPT_DIR/bootstrap.sh"

# --- [Constants & Variables] ---
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_LOC="$PROJECT_ROOT/config/"

# .app-env.properties 로드 (LOG_PATH, PID_FILE 등)
if [ -f "$SCRIPT_DIR/.app-env.properties" ]; then
    source "$SCRIPT_DIR/.app-env.properties"
fi
LOG_PATH="${LOG_PATH:-$PROJECT_ROOT/log}"
PID_FILE="${PID_FILE:-$SCRIPT_DIR/application.pid}"

# @var APP_NAME 애플리케이션 이름 (Gradle 빌드 시 치환)
APP_NAME="build_test"
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
)

# Docker 환경 감지 및 실행 분기
if [ -f /.dockerenv ] || [ "$$" -eq 1 ]; then
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

    # exec로 프로세스 대체 (PID 1 유지)
    exec java -jar "${JAVA_OPTS[@]}" "$JAR_FILE"
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
