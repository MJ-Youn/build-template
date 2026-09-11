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
if [ -f "$SCRIPT_DIR/bootstrap.sh" ]; then
    source "$SCRIPT_DIR/bootstrap.sh"
elif [ -f "$SCRIPT_DIR/../common/bootstrap.sh" ]; then
    source "$SCRIPT_DIR/../common/bootstrap.sh"
fi

# --- [Constants & Variables] ---
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_LOC="$PROJECT_ROOT/config/"

# .env 로드 (우선순위: 루트 .env -> config/.env -> bin/.env)
[ -f "$PROJECT_ROOT/.env" ] && source "$PROJECT_ROOT/.env"
[ -f "$CONFIG_LOC/.env" ] && source "$CONFIG_LOC/.env"
[ -f "$SCRIPT_DIR/.env" ] && source "$SCRIPT_DIR/.env"

LOG_PATH="${LOG_PATH:-$PROJECT_ROOT/log}"
PID_FILE="${PID_FILE:-$SCRIPT_DIR/application.pid}"

# @var APP_NAME 애플리케이션 이름 (Gradle/Maven 빌드 시 치환)
APP_NAME="@appName@"
# --- [Functions] ---

# @description 애플리케이션 시작 처리 (Docker 감지 및 Foreground/Background 실행)
start_application() {
    # -------------------------------------------------------------
    # 🐳 [호스트 환경] Docker Compose 배포 환경 감지 및 실행
    # -------------------------------------------------------------
    local COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
    if [ -f "$COMPOSE_FILE" ] && ! is_docker_container; then
        log_header "Docker Compose 서비스 시작 ($APP_NAME)"

        detect_docker_compose_cmd true

        log_info "Docker Compose 명령어: $DOCKER_COMPOSE_CMD"
        log_info "Compose 파일: $COMPOSE_FILE"

        cd "$PROJECT_ROOT" || exit 1

        # 백그라운드 옵션(-d 또는 --detach) 확인
        if [[ "$*" == *"-d"* ]] || [[ "$*" == *"--detach"* ]]; then
            log_info "백그라운드(-d) 모드로 컨테이너를 실행합니다."
            exec $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up -d
        else
            log_info "포그라운드 모드로 컨테이너를 실행합니다 (Systemd 연동)."
            exec $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up
        fi
    fi

    # @var JAR_FILE 실행할 JAR 파일 경로
    JAR_FILE=$(find "$PROJECT_ROOT/libs" "$PROJECT_ROOT/lib" -name "*.jar" 2>/dev/null | head -n 1)

    if [ -z "$JAR_FILE" ]; then
      echo "오류: $PROJECT_ROOT/(lib|libs) 경로에서 애플리케이션 JAR 파일을 찾을 수 없습니다."
      exit 1
    fi

    log_step "애플리케이션을 시작합니다..."
    log_info "JAR 파일: $JAR_FILE"
    log_info "설정 경로: $CONFIG_LOC"
    log_info "로그 경로: $LOG_PATH"

    # 애플리케이션 실행
    log_step "애플리케이션을 시작합니다..."

    # 포트 정보 파싱 (application.yml)
    if [ -z "$SERVER_PORT" ]; then
        SERVER_PORT="8080" # 기본값
        APP_YML="$PROJECT_ROOT/config/application.yml"
        if [ -f "$APP_YML" ]; then
           # 간단한 파싱: "port: 1234" 형태 검색
           DETECTED_PORT=$(grep -E "^\s*port:\s*[0-9]+" "$APP_YML" | awk '{print $2}')
           if [ -n "$DETECTED_PORT" ]; then
               SERVER_PORT="$DETECTED_PORT"
           fi
        fi
    fi

    # 공통 실행 옵션 조립
    # 주의: spring.config.location이 디렉토리일 경우 끝에 /가 있어야 함
    JAVA_OPTS=(
        "-Dspring.config.location=$CONFIG_LOC"
        "-Dapp.name=$APP_NAME"
        "-Dlog.path=$LOG_PATH"
        "-Dlogging.config=$PROJECT_ROOT/config/log4j2.yml"
    )

    # 힙 메모리 옵션 추가 (JVM_XMS, JVM_XMX)
    [ -n "$JVM_XMS" ] && JAVA_OPTS+=("$JVM_XMS")
    [ -n "$JVM_XMX" ] && JAVA_OPTS+=("$JVM_XMX")

    # 추가 JVM 옵션 배열 분해 및 추가 (EXTRA_JAVA_OPTS)
    if [ -n "$EXTRA_JAVA_OPTS" ]; then
        read -r -a EXTRA_OPTS_ARR <<< "$EXTRA_JAVA_OPTS"
        JAVA_OPTS+=("${EXTRA_OPTS_ARR[@]}")
    fi

    # Spring Boot 애플리케이션 파라미터 (APP_ARGS 및 커맨드라인 인자 결합)
    FINAL_APP_ARGS=()
    if [ -n "$APP_ARGS" ]; then
        read -r -a APP_ARGS_ARR <<< "$APP_ARGS"
        FINAL_APP_ARGS+=("${APP_ARGS_ARR[@]}")
    fi
    FINAL_APP_ARGS+=("$@")

    # Docker 컨테이너 내부 실행 분기 (is_docker_container 함수 활용)
    if is_docker_container; then
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
            exec su-exec "${APP_USER}" java "${JAVA_OPTS[@]}" -jar "$JAR_FILE" "${FINAL_APP_ARGS[@]}"
        else
            log_info "${APP_USER}를 찾을 수 없어 기본 권한으로 실행합니다."
            # exec로 프로세스 대체 (PID 1 유지)
            exec java "${JAVA_OPTS[@]}" -jar "$JAR_FILE" "${FINAL_APP_ARGS[@]}"
        fi
    else
        # 일반 환경: nohup을 사용하여 백그라운드에서 실행 유지
        nohup java "${JAVA_OPTS[@]}" -jar "$JAR_FILE" "${FINAL_APP_ARGS[@]}" > /dev/null 2>&1 &
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
        echo -e "${BOLD}${BLUE}║${NC} nohup java ${JAVA_OPTS[*]} -jar \"$JAR_FILE\" ${FINAL_APP_ARGS[*]}"
        echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    fi
}

# --- [Execution] ---
start_application "$@"
