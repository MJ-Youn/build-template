#!/bin/bash
# ==============================================================================
# File: start.sh
# Description: 서비스 시작 스크립트 (Spring Boot JAR / Standalone Tomcat 자동 지원)
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
# @var APP_TYPE 애플리케이션 타입 (jar 또는 tomcat)
APP_TYPE="@appType@"

# --- [Functions] ---

# @description Tomcat 실행 처리 (호스트 Legacy 환경)
start_tomcat_application() {
    log_header "Apache Tomcat 서비스 시작 ($APP_NAME)"

    # CATALINA_HOME 탐색 (1. 환경변수 -> 2. PROJECT_ROOT/tomcat -> 3. /usr/local/tomcat -> 4. /opt/tomcat)
    if [ -z "$CATALINA_HOME" ]; then
        if [ -d "$PROJECT_ROOT/tomcat" ] && [ -f "$PROJECT_ROOT/tomcat/bin/catalina.sh" ]; then
            CATALINA_HOME="$PROJECT_ROOT/tomcat"
        elif [ -d "/usr/local/tomcat" ]; then
            CATALINA_HOME="/usr/local/tomcat"
        elif [ -d "/opt/tomcat" ]; then
            CATALINA_HOME="/opt/tomcat"
        elif [ -d "/opt/apache-tomcat" ]; then
            CATALINA_HOME="/opt/apache-tomcat"
        fi
    fi

    if [ -z "$CATALINA_HOME" ] || [ ! -f "$CATALINA_HOME/bin/catalina.sh" ]; then
        log_error "CATALINA_HOME을 찾을 수 없습니다. Tomcat이 설치되어 있는지 확인하거나 CATALINA_HOME을 설정해주세요."
        exit 1
    fi

    export CATALINA_HOME
    export CATALINA_BASE="${CATALINA_BASE:-$CATALINA_HOME}"
    export CATALINA_PID="$PID_FILE"

    # PID 디렉토리 생성
    PID_DIR=$(dirname "$PID_FILE")
    [ ! -d "$PID_DIR" ] && mkdir -p "$PID_DIR"
    mkdir -p "$PROJECT_ROOT/logs" "$LOG_PATH"

    # 톰캣 환경 설정(setenv.sh) 동기화
    if [ -f "$PROJECT_ROOT/tomcat/bin/setenv.sh" ]; then
        cp "$PROJECT_ROOT/tomcat/bin/setenv.sh" "$CATALINA_HOME/bin/setenv.sh"
        chmod +x "$CATALINA_HOME/bin/setenv.sh"
    fi

    # 톰캣 설정 파일(conf/) 동기화 (server.xml 등)
    if [ -d "$PROJECT_ROOT/tomcat/conf" ] && [ "$CATALINA_HOME" != "$PROJECT_ROOT/tomcat" ]; then
        log_info "프로젝트의 톰캣 설정을 $CATALINA_HOME/conf 로 동기화합니다."
        cp -r "$PROJECT_ROOT/tomcat/conf/"* "$CATALINA_HOME/conf/" 2>/dev/null || true
    fi

    # webapps/ROOT 배치 동기화 (심볼릭 링크 또는 복사)
    if [ -d "$PROJECT_ROOT/webapps/ROOT" ] && [ "$CATALINA_HOME/webapps" != "$PROJECT_ROOT/webapps" ]; then
        mkdir -p "$CATALINA_HOME/webapps"
        if [ ! -e "$CATALINA_HOME/webapps/ROOT" ]; then
            log_info "ROOT 웹앱을 톰캣 webapps/ROOT 로 연결합니다."
            ln -s "$PROJECT_ROOT/webapps/ROOT" "$CATALINA_HOME/webapps/ROOT" 2>/dev/null || \
            cp -r "$PROJECT_ROOT/webapps/ROOT" "$CATALINA_HOME/webapps/"
        fi
    fi

    log_step "Tomcat을 시작합니다..."
    log_info "CATALINA_HOME: $CATALINA_HOME"
    log_info "CATALINA_PID : $CATALINA_PID"

    "$CATALINA_HOME/bin/catalina.sh" start
    local RESULT=$?

    if [ $RESULT -eq 0 ]; then
        log_success "Tomcat 서비스가 성공적으로 시작되었습니다."
    else
        log_error "Tomcat 시작 실패 (종료 코드: $RESULT)"
        exit $RESULT
    fi
}

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

    # -------------------------------------------------------------
    # 🐱 [호스트 환경] Standalone Tomcat 모드 감지 및 실행
    # -------------------------------------------------------------
    if [ "$APP_TYPE" = "tomcat" ] || [ "$APP_TYPE" = "war" ] || [ -d "$PROJECT_ROOT/webapps/ROOT" ]; then
        start_tomcat_application "$@"
        return $?
    fi

    # -------------------------------------------------------------
    # ☕ [호스트/컨테이너 환경] Spring Boot Executable JAR 실행
    # -------------------------------------------------------------
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

    # 포트 정보 파싱 (application.yml)
    if [ -z "$SERVER_PORT" ]; then
        SERVER_PORT="8443" # 기본값
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

        CLEAN_APP_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
        APP_USER="${CLEAN_APP_NAME}user"

        if [ -n "$APP_UID" ] && [ -n "$APP_GID" ]; then
            log_info "전달된 APP_UID($APP_UID), APP_GID($APP_GID)에 맞게 ${APP_USER} 권한을 조정합니다."
            groupmod -o -g "$APP_GID" "${APP_USER}" 2>/dev/null || true
            usermod -o -u "$APP_UID" "${APP_USER}" 2>/dev/null || true
        fi

        if id "${APP_USER}" &>/dev/null; then
            log_info "${APP_USER} 권한으로 애플리케이션을 실행합니다."
            
            if [ -n "$CHOWN_DIRS" ]; then
                log_info "동적 디렉토리 권한 변경 처리 (CHOWN_DIRS: $CHOWN_DIRS)"
                for DIR in $CHOWN_DIRS; do
                    mkdir -p "$DIR" 2>/dev/null || true
                    chown -R "${APP_USER}:${APP_USER}" "$DIR" 2>/dev/null || true
                done
            else
                mkdir -p "$LOG_PATH"
                chown -R "${APP_USER}:${APP_USER}" "$LOG_PATH"
                chown -R "${APP_USER}:${APP_USER}" "$PROJECT_ROOT/config" 2>/dev/null || true
            fi
            
            exec su-exec "${APP_USER}" java "${JAVA_OPTS[@]}" -jar "$JAR_FILE" "${FINAL_APP_ARGS[@]}"
        else
            log_info "${APP_USER}를 찾을 수 없어 기본 권한으로 실행합니다."
            exec java "${JAVA_OPTS[@]}" -jar "$JAR_FILE" "${FINAL_APP_ARGS[@]}"
        fi
    else
        # 일반 환경: nohup을 사용하여 백그라운드에서 실행 유지
        nohup java "${JAVA_OPTS[@]}" -jar "$JAR_FILE" "${FINAL_APP_ARGS[@]}" > /dev/null 2>&1 &
        PID=$!

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
