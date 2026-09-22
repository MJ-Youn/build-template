#!/bin/bash
# ==============================================================================
# File: install_service.sh
# Description: 서비스 설치 및 실행 스크립트 (Legacy / Docker 배포 방식 지원)
#              Systemd / SysVinit 자동 감지
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
# @appName@은 Gradle 빌드 시 실제 프로젝트 이름으로 치환됨
APP_NAME="@appName@"
if [ "$(basename "$SCRIPT_DIR")" = "bin" ] || [ "$(basename "$SCRIPT_DIR")" = "deploy" ]; then
    PKG_ROOT="$(dirname "$SCRIPT_DIR")"
else
    PKG_ROOT="$SCRIPT_DIR"
fi

# 배포 권한 모드 설정: 기본값은 일반 사용자(Non-root) 배포 모드 (Default: User Mode)
IS_USER_MODE=1

# 시스템/루트(sudo) 배포 모드 환경변수 감지
if [ "${SUDO_MODE:-}" = "true" ] || [ "${ROOT_MODE:-}" = "true" ] || [ "${USE_SUDO:-}" = "true" ] || [ "${SYSTEM_MODE:-}" = "true" ]; then
    IS_USER_MODE=0
elif [ "${NON_ROOT:-}" = "true" ] || [ "${USER_MODE:-}" = "true" ]; then
    IS_USER_MODE=1
fi

RUNTIME_ENGINE="${RUNTIME_ENGINE:-${TYPE:-}}"
DEPLOY_MODE=""
TARGET_CATALINA_HOME="${CATALINA_HOME:-}"
SYSTEMD_EXTRA_ENV=""
POSITIONAL_INSTALL_DIR=""

# CLI 인자 분석 (--sudo, --root, --user, --type=..., --mode=..., --tomcat-home=...)
for arg in "$@"; do
    case "$arg" in
        --sudo|--root|--system|--system-mode)
            IS_USER_MODE=0
            ;;
        --user|--non-root|--user-mode)
            IS_USER_MODE=1
            ;;
        --type=*)
            RUNTIME_ENGINE="${arg#*=}"
            ;;
        --mode=*)
            DEPLOY_MODE="${arg#*=}"
            ;;
        --tomcat-home=*|--catalina-home=*)
            TARGET_CATALINA_HOME="${arg#*=}"
            ;;
        --*)
            ;;
        *)
            if [ -z "$POSITIONAL_INSTALL_DIR" ]; then
                POSITIONAL_INSTALL_DIR="$arg"
            fi
            ;;
    esac
done

# 실행 유저 확인 (sudo로 실행 시 실제 유저, 일반 사용자 모드 시 현재 유저)
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)
[ -z "$USER_HOME" ] && USER_HOME="$HOME"
SERVICE_GROUP=$(id -gn "$REAL_USER" 2>/dev/null || id -gn 2>/dev/null || echo "users")

# 기본 설치 및 로그 위치 정의
if [ "$IS_USER_MODE" -eq 1 ]; then
    DEFAULT_INSTALL_DIR="${POSITIONAL_INSTALL_DIR:-${INSTALL_DIR:-$USER_HOME/apps/$APP_NAME}}"
    DEFAULT_LOG_BASE="$USER_HOME/logs/$APP_NAME"
else
    DEFAULT_INSTALL_DIR="${POSITIONAL_INSTALL_DIR:-${INSTALL_DIR:-/opt/$APP_NAME}}"
    DEFAULT_LOG_BASE="/log/$APP_NAME"
fi

# 전역 변수 (함수 내에서 설정됨)
DEST_DIR=""
LOG_PATH=""
# 기존 서비스 감지 및 덮어쓰기 플래그
EXISTING_SERVICE_FOUND=0
OVERWRITE_EXISTING=""
PREVIOUS_INSTALL_LOC=""
PREVIOUS_LOG_PATH=""

# --- [Functions] ---

# @description 유저 모드에서는 chown을 안전하게 bypass (권한 에러 방지)
chown() {
    if [ "$IS_USER_MODE" -eq 1 ]; then
        return 0
    fi
    command chown "$@"
}

# @description 경로 쓰기 권한 검사 (디렉토리가 없으면 생성 가능한 부모 디렉토리까지 검사)
validate_path_writable() {
    local target_path="$1"
    local path_type="${2:-경로}"

    if [ -z "$target_path" ]; then
        return 0
    fi

    # 디렉토리가 이미 존재할 경우 쓰기 권한 직접 확인
    if [ -e "$target_path" ]; then
        if [ ! -w "$target_path" ]; then
            echo ""
            log_error "${path_type}에 쓰기 권한이 없습니다: $target_path"
            echo -e "   ${YELLOW}현재 사용자($REAL_USER)는 해당 경로에 파일을 쓸 권한이 없습니다.${NC}"
            if [ "$IS_USER_MODE" -eq 1 ]; then
                echo -e "   ${CYAN}💡 일반 사용자 모드 권장 경로:${NC}"
                echo -e "      - 설치 위치: ${GREEN}$USER_HOME/apps/$APP_NAME${NC}"
                echo -e "      - 로그 경로: ${GREEN}$USER_HOME/logs/$APP_NAME${NC}"
            fi
            echo ""
            exit 1
        fi
        return 0
    fi

    # 디렉토리가 아직 없는 경우 가장 가까운 존재하는 상위 디렉토리 탐색
    local curr_path="$target_path"
    while [ ! -e "$curr_path" ] && [ "$curr_path" != "/" ] && [ "$curr_path" != "." ]; do
        curr_path=$(dirname "$curr_path")
    done

    if [ ! -w "$curr_path" ]; then
        echo ""
        log_error "${path_type}를 생성할 권한이 없습니다: $target_path"
        echo -e "   ${YELLOW}상위 디렉토리(${curr_path})에 디렉토리 생성(쓰기) 권한이 없습니다.${NC}"
        if [ "$IS_USER_MODE" -eq 1 ]; then
            echo -e "   ${CYAN}💡 일반 사용자 모드 권장 경로:${NC}"
            echo -e "      - 설치 위치: ${GREEN}$USER_HOME/apps/$APP_NAME${NC}"
            echo -e "      - 로그 경로: ${GREEN}$USER_HOME/logs/$APP_NAME${NC}"
        fi
        echo ""
        exit 1
    fi

    return 0
}

# @description 일반 사용자 모드(--user) 사전 요구사항 및 설정 검증
validate_user_mode_prerequisites() {
    [ "$IS_USER_MODE" -ne 1 ] && return 0

    log_step "일반 사용자 모드(--user) 사전 유효성 검증..."

    # 1. 서비스 포트 검증 (1~1023 특권 포트 바인딩 차단)
    local CHECK_PORT=""
    if [ -n "$HTTP_PORT" ] && [[ "$HTTP_PORT" =~ ^[0-9]+$ ]]; then
        CHECK_PORT="$HTTP_PORT"
    fi
    if [ -z "$CHECK_PORT" ]; then
        local APP_YML="$PKG_ROOT/config/application.yml"
        if [ -f "$APP_YML" ]; then
            local PARSED_PORT
            PARSED_PORT=$(grep -E "^\s*port:\s*[0-9]+" "$APP_YML" 2>/dev/null | awk '{print $2}')
            if [ -n "$PARSED_PORT" ] && [[ "$PARSED_PORT" =~ ^[0-9]+$ ]]; then
                CHECK_PORT="$PARSED_PORT"
            fi
        fi
    fi
    if [ -z "$CHECK_PORT" ]; then
        local TOKEN_PORT="@httpPort@"
        if [[ "$TOKEN_PORT" =~ ^[0-9]+$ ]]; then
            CHECK_PORT="$TOKEN_PORT"
        fi
    fi

    if [ -n "$CHECK_PORT" ] && [ "$CHECK_PORT" -lt 1024 ]; then
        echo ""
        log_error "특권 포트(Privileged Port: ${CHECK_PORT}번) 사용 불가"
        echo -e "   ${YELLOW}Linux 커널 보안 정책상 1024 미만의 포트는 root(sudo) 권한 없이 바인딩할 수 없습니다.${NC}"
        echo ""
        echo -e "   ${BOLD}권장 해결 방법:${NC}"
        echo -e "   1) 포트를 1024 이상(예: 8080, 8443)으로 변경하여 배포"
        echo -e "   2) 또는 앞단에 Nginx/HAProxy 등 리버스 프록시를 두고 80/443 포트 포워딩"
        echo -e "   3) 또는 시스템 관리자가 Java 바이너리에 포트 바인딩 권한 부여:"
        echo -e "      ${CYAN}sudo setcap 'cap_net_bind_service=+ep' \$(readlink -f \$(which java))${NC}"
        echo ""
        log_error "일반 사용자 모드 배포를 안전하게 중단합니다."
        exit 1
    fi

    # 2. Docker 배포 모드일 때 Docker 실행 권한 검증
    if [ "$DEPLOY_MODE" = "docker" ]; then
        if ! docker ps >/dev/null 2>&1; then
            echo ""
            log_error "Docker 데몬 접근 권한 부족 (sudo 필요)"
            echo -e "   ${YELLOW}현재 사용자($REAL_USER)는 sudo 없이 Docker 데몬을 제어할 수 없습니다.${NC}"
            echo ""
            echo -e "   ${BOLD}권장 해결 방법:${NC}"
            echo -e "   1) 시스템 관리자에게 docker 그룹 등록 요청:"
            echo -e "      ${CYAN}sudo usermod -aG docker $REAL_USER${NC}"
            echo -e "   2) 등록 후 터미널 재접속 또는 다음 명령 실행:"
            echo -e "      ${CYAN}newgrp docker${NC}"
            echo ""
            log_error "일반 사용자 모드 배포를 안전하게 중단합니다."
            exit 1
        fi
    fi

    # 3. systemd user 세션 유효성 검증 및 환경변수 보정
    if command -v systemctl >/dev/null 2>&1; then
        local USER_UID
        USER_UID=$(id -u "$REAL_USER" 2>/dev/null)
        if [ -z "$XDG_RUNTIME_DIR" ] && [ -d "/run/user/$USER_UID" ]; then
            export XDG_RUNTIME_DIR="/run/user/$USER_UID"
        fi
        if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] && [ -S "/run/user/$USER_UID/bus" ]; then
            export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"
        fi
    fi

    log_success "일반 사용자 모드 사전 점검 완료."
}

# @description 일반 사용자 모드 배포 완료 후 필수 후속 조치 안내 카드 출력
print_user_mode_post_instructions() {
    [ "$IS_USER_MODE" -ne 1 ] && return 0

    echo ""
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              💡 일반 사용자 모드(User Mode) 안내 사항        ║${NC}"
    echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"

    # Linger 설정 점검
    local LINGER_STATUS=""
    if command -v loginctl >/dev/null 2>&1; then
        LINGER_STATUS=$(loginctl show-user "$REAL_USER" --property=Linger 2>/dev/null | cut -d= -f2)
    fi

    if [ "$LINGER_STATUS" != "yes" ]; then
        echo -e "${BOLD}${CYAN}║${NC} 🔹 ${BOLD}부팅 시 자동 실행(Linger) 설정 권고${NC}"
        echo -e "${BOLD}${CYAN}║${NC}   로그아웃하거나 서버 재부팅 후에도 서비스가 유지되려면"
        echo -e "${BOLD}${CYAN}║${NC}   시스템 관리자(root)에게 아래 명령을 1회 실행 요청해 주세요:"
        echo -e "${BOLD}${CYAN}║${NC}   👉 ${YELLOW}sudo loginctl enable-linger $REAL_USER${NC}"
        echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    else
        echo -e "${BOLD}${CYAN}║${NC} 🔹 ${GREEN}✓ 부팅 시 자동 실행(Linger)이 이미 활성화되어 있습니다.${NC}"
        echo -e "${BOLD}${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    fi

    echo -e "${BOLD}${CYAN}║${NC} 🔹 ${BOLD}서비스 제어 명령어 (sudo 불필요)${NC}"
    echo -e "${BOLD}${CYAN}║${NC}   - 상태 확인 : ${GREEN}systemctl --user status $APP_NAME${NC}"
    echo -e "${BOLD}${CYAN}║${NC}   - 서비스 중지 : ${GREEN}systemctl --user stop $APP_NAME${NC}"
    echo -e "${BOLD}${CYAN}║${NC}   - 서비스 시작 : ${GREEN}systemctl --user start $APP_NAME${NC}"
    echo -e "${BOLD}${CYAN}║${NC}   - 서비스 재시작 : ${GREEN}systemctl --user restart $APP_NAME${NC}"
    echo -e "${BOLD}${CYAN}║${NC}   - 실시간 로그 : ${GREEN}tail-log-${APP_NAME}.sh${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# @description 애플리케이션 런타임 엔진 선택 (jar / tomcat)
select_runtime_engine() {
    # Docker 배포 모드인 경우 런타임 엔진은 컨테이너 내부에서 구동되므로 선택 생략
    if [ "$DEPLOY_MODE" = "docker" ]; then
        RUNTIME_ENGINE="${RUNTIME_ENGINE:-docker}"
        return 0
    fi

    if [ -n "$RUNTIME_ENGINE" ]; then
        log_info "지정된 런타임 엔진($RUNTIME_ENGINE)으로 진행합니다."
        return 0
    fi

    # 1. 자동 감지: 외장 톰캣 패키지(webapps/ROOT 또는 tomcat 디렉토리) 감지 시
    if [ -d "$PKG_ROOT/webapps/ROOT" ] || [ -d "$PKG_ROOT/tomcat" ]; then
        RUNTIME_ENGINE="tomcat"
        log_info "런타임 엔진 자동 감지: Standalone Apache Tomcat (webapps/tomcat 디렉토리 감지됨)"
        return 0
    fi

    # 2. 자동 감지: Executable JAR 패키지(libs 디렉토리) 감지 시
    if [ -d "$PKG_ROOT/libs" ] || [ -d "$PKG_ROOT/lib" ]; then
        RUNTIME_ENGINE="jar"
        log_info "런타임 엔진 자동 감지: Spring Boot Executable JAR (libs 디렉토리 감지됨)"
        return 0
    fi

    # 3. 자동 감지가 불가능한 경우 사용자 대화형 선택
    log_step "애플리케이션 런타임 엔진 선택"
    echo ""
    echo -e "   ${BOLD}애플리케이션 런타임 엔진을 선택하세요:${NC}"
    echo -e "   ${CYAN}1) Spring Boot Executable JAR${NC}  - 내장 톰캣 구동"
    echo -e "   ${CYAN}2) Standalone Apache Tomcat${NC}    - 외장 톰캣 엔진 구동"
    echo ""

    while true; do
        read -p "   선택 [1/2] (기본값: 1): " ENGINE_INPUT
        ENGINE_INPUT="${ENGINE_INPUT:-1}"
        case "$ENGINE_INPUT" in
            1)
                RUNTIME_ENGINE="jar"
                log_info "Spring Boot Executable JAR 방식이 선택되었습니다."
                break
                ;;
            2)
                RUNTIME_ENGINE="tomcat"
                log_info "Standalone Apache Tomcat 방식이 선택되었습니다."
                break
                ;;
            *)
                log_warning "잘못된 입력입니다. 1 또는 2를 입력해주세요."
                ;;
        esac
    done
}

# @description 배포 방식 선택 (legacy / docker)
select_deploy_mode() {
    # 0. 기존 서비스 덮어쓰기인 경우 기존 배포 방식 자동 승계
    if [ "$OVERWRITE_EXISTING" = "Y" ] && [ -n "$PREVIOUS_INSTALL_LOC" ]; then
        if [ -f "$PREVIOUS_INSTALL_LOC/docker-compose.yml" ]; then
            DEPLOY_MODE="docker"
            echo -e "   🐳 배포 방식 : ${CYAN}기존 방식(Docker) 유지${NC}"
            return 0
        elif [ -d "$PREVIOUS_INSTALL_LOC/libs" ] || [ -d "$PREVIOUS_INSTALL_LOC/lib" ] || [ -f "$PREVIOUS_INSTALL_LOC/bin/start.sh" ]; then
            DEPLOY_MODE="legacy"
            echo -e "   ☕ 배포 방식 : ${CYAN}기존 방식(Legacy) 유지${NC}"
            return 0
        fi
    fi

    # 1. 자동 감지: PKG_ROOT 내에 .tar 파일이 존재하면 Docker Offline 모드로 자동 지정
    local TAR_FILES=("$PKG_ROOT"/*.tar)
    if [ -e "${TAR_FILES[0]}" ]; then
        DEPLOY_MODE="docker"
        log_info "로컬 Docker 아카이브(.tar)가 감지되어 Docker Offline 모드로 자동 진행합니다."
        return 0
    fi

    # 1-1. 자동 감지: docker-compose.yml이 있고 libs/webapps가 없으면 순수 Docker 배포로 자동 지정
    if [ -f "$PKG_ROOT/docker/docker-compose.yml" ] || [ -f "$PKG_ROOT/docker-compose.yml" ]; then
        if [ ! -d "$PKG_ROOT/libs" ] && [ ! -d "$PKG_ROOT/lib" ] && [ ! -d "$PKG_ROOT/webapps" ]; then
            DEPLOY_MODE="docker"
            log_info "Docker 배포 패키지가 감지되어 Docker 모드로 자동 진행합니다."
            return 0
        fi
    fi

    # 2. 이미 지정된 경우
    if [ "$DEPLOY_MODE" = "docker" ] || [ "$DEPLOY_MODE" = "legacy" ]; then
        log_info "지정된 배포 방식($DEPLOY_MODE)으로 진행합니다."
        return 0
    fi

    log_step "배포 방식 선택"
    echo ""
    echo -e "   ${BOLD}배포 방식을 선택하세요:${NC}"
    echo -e "   ${CYAN}1) Legacy${NC}  - Java(Jar) 직접 실행 방식"
    echo -e "   ${CYAN}2) Docker${NC}  - 배포 파일로 Docker 이미지 빌드 후 실행"
    echo ""

    while true; do
        read -p "   선택 [1/2] (기본값: 2): " MODE_INPUT
        MODE_INPUT="${MODE_INPUT:-2}"
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

# @description 기존 설치 감지 및 덮어쓰기 여부 확인
# 기존 서비스가 존재하면 덮어쓰기(Y/n)를 묻고,
# Y인 경우 기존 경로/설정을 그대로 유지하여 추가 질문을 생략함.
# n인 경우 기존 uninstall_service.sh를 실행하여 완전히 제거한 후 새로 설치 진행함.
check_and_handle_existing_service() {
    PREVIOUS_INSTALL_LOC=""
    PREVIOUS_LOG_PATH=""
    EXISTING_SERVICE_FOUND=0

    # 0. User Mode Systemd 감지 (IS_USER_MODE=1 이거나 사용자 서비스 파일이 존재하는 경우)
    if [ "$IS_USER_MODE" -eq 1 ] || [ -f "$USER_HOME/.config/systemd/user/$APP_NAME.service" ]; then
        local USER_SVC="$USER_HOME/.config/systemd/user/$APP_NAME.service"
        if [ -f "$USER_SVC" ]; then
            local WORK_DIR
            WORK_DIR=$(grep "WorkingDirectory=" "$USER_SVC" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
            if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
                PREVIOUS_INSTALL_LOC="$WORK_DIR"
            fi
            if [ -z "$PREVIOUS_INSTALL_LOC" ]; then
                local EXEC_START
                EXEC_START=$(grep "ExecStart=" "$USER_SVC" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
                if [ -n "$EXEC_START" ]; then
                    PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
                fi
            fi
            if [ -n "$PREVIOUS_INSTALL_LOC" ] && [ -d "$PREVIOUS_INSTALL_LOC" ]; then
                IS_USER_MODE=1
            fi
        fi
    fi

    # 1. Systemd 감지 (System Mode)
    if [ -z "$PREVIOUS_INSTALL_LOC" ] && command -v systemctl >/dev/null 2>&1; then
        local SERVICE_PATH
        SERVICE_PATH=$(systemctl show -p FragmentPath "$APP_NAME.service" 2>/dev/null | cut -d= -f2)
        if [ -n "$SERVICE_PATH" ] && [ -f "$SERVICE_PATH" ]; then
            # Legacy 모드: ExecStart 라인에서 추출
            local EXEC_START
            EXEC_START=$(grep "ExecStart=" "$SERVICE_PATH" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
            if [ -n "$EXEC_START" ]; then
                PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
            fi
            # Docker 모드: WorkingDirectory 라인에서 추출
            if [ -z "$PREVIOUS_INSTALL_LOC" ] || [ ! -d "$PREVIOUS_INSTALL_LOC" ]; then
                local WORK_DIR
                WORK_DIR=$(grep "WorkingDirectory=" "$SERVICE_PATH" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
                if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
                    PREVIOUS_INSTALL_LOC="$WORK_DIR"
                fi
            fi
        fi
    fi

    # 2. SysVinit 감지 (Systemd로 감지되지 않은 경우)
    if [ -z "$PREVIOUS_INSTALL_LOC" ] && [ -f "/etc/init.d/$APP_NAME" ]; then
        local EXEC_START
        EXEC_START=$(grep "su - $REAL_USER -c" "/etc/init.d/$APP_NAME" 2>/dev/null | head -n 1 | awk -F '"' '{print $2}')
        if [ -n "$EXEC_START" ]; then
            PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
        fi
    fi

    # 기존 설치가 확인된 경우
    if [ -n "$PREVIOUS_INSTALL_LOC" ] && [ -d "$PREVIOUS_INSTALL_LOC" ]; then
        EXISTING_SERVICE_FOUND=1

        # 기존 로그 경로 탐색 (.env 또는 bin/.env)
        local ENV_FILE=""
        if [ -f "$PREVIOUS_INSTALL_LOC/.env" ]; then
            ENV_FILE="$PREVIOUS_INSTALL_LOC/.env"
        elif [ -f "$PREVIOUS_INSTALL_LOC/bin/.env" ]; then
            ENV_FILE="$PREVIOUS_INSTALL_LOC/bin/.env"
        fi
        if [ -n "$ENV_FILE" ]; then
            local LOG_LINE
            LOG_LINE=$(grep "^LOG_PATH=" "$ENV_FILE" 2>/dev/null)
            if [ -n "$LOG_LINE" ]; then
                PREVIOUS_LOG_PATH=$(echo "$LOG_LINE" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
            fi
        fi

        echo ""
        log_warning "기존에 설치된 서비스가 감지되었습니다."
        echo -e "   📍 설치 위치 : ${CYAN}$PREVIOUS_INSTALL_LOC${NC}"
        if [ -n "$PREVIOUS_LOG_PATH" ]; then
            echo -e "   📝 로그 경로 : ${CYAN}$PREVIOUS_LOG_PATH${NC}"
        fi
        echo ""
        read -p "   ❓ 기존 서비스 정보를 덮어 씌우시겠습니까? (Y/n): " USER_OVERWRITE_CHOICE
        USER_OVERWRITE_CHOICE=${USER_OVERWRITE_CHOICE:-Y}

        if [[ "$USER_OVERWRITE_CHOICE" =~ ^[Yy]$ ]]; then
            OVERWRITE_EXISTING="Y"
            DEST_DIR="$PREVIOUS_INSTALL_LOC"
            LOG_PATH="$PREVIOUS_LOG_PATH"
            echo ""
            log_success "기존 설정을 유지하여 덮어쓰기 설치를 진행합니다."
        else
            OVERWRITE_EXISTING="N"
            echo ""
            log_info "기존 서비스를 삭제하고 새로 설치를 진행합니다..."

            # uninstall_service.sh 탐색 및 실행
            local UNINSTALL_SCRIPT=""
            if [ -f "$PREVIOUS_INSTALL_LOC/bin/uninstall_service.sh" ]; then
                UNINSTALL_SCRIPT="$PREVIOUS_INSTALL_LOC/bin/uninstall_service.sh"
            elif [ -f "$PREVIOUS_INSTALL_LOC/uninstall_service.sh" ]; then
                UNINSTALL_SCRIPT="$PREVIOUS_INSTALL_LOC/uninstall_service.sh"
            elif [ -f "$SCRIPT_DIR/uninstall_service.sh" ]; then
                UNINSTALL_SCRIPT="$SCRIPT_DIR/uninstall_service.sh"
            elif [ -f "$PKG_ROOT/scripts/deploy/uninstall_service.sh" ]; then
                UNINSTALL_SCRIPT="$PKG_ROOT/scripts/deploy/uninstall_service.sh"
            fi

            if [ -n "$UNINSTALL_SCRIPT" ] && [ -f "$UNINSTALL_SCRIPT" ]; then
                log_step "기존 서비스 삭제 실행 ($UNINSTALL_SCRIPT)..."
                local UNINSTALL_ARGS=()
                if [ "$IS_USER_MODE" -eq 1 ]; then
                    UNINSTALL_ARGS+=("--user")
                else
                    UNINSTALL_ARGS+=("--sudo")
                fi
                bash "$UNINSTALL_SCRIPT" "${UNINSTALL_ARGS[@]}"
                log_success "기존 서비스가 삭제되었습니다."
            else
                log_warning "uninstall_service.sh를 찾을 수 없어 기존 서비스 중지만 시도합니다."
                if [ "$IS_USER_MODE" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
                    systemctl --user stop "$APP_NAME" 2>/dev/null || true
                    systemctl --user disable "$APP_NAME" 2>/dev/null || true
                elif command -v systemctl >/dev/null 2>&1; then
                    systemctl stop "$APP_NAME" 2>/dev/null || true
                    systemctl disable "$APP_NAME" 2>/dev/null || true
                fi
            fi

            # 상태 초기화
            EXISTING_SERVICE_FOUND=0
            PREVIOUS_INSTALL_LOC=""
            PREVIOUS_LOG_PATH=""
            DEST_DIR=""
            LOG_PATH=""
        fi
    fi
}

# @description 서비스 설치 메인 함수
install_service() {
    log_header "서비스 설치 시작 ($APP_NAME)"

    # 0. 배포 모드 안내
    if [ "$IS_USER_MODE" -eq 1 ]; then
        echo -e "   👤 ${BOLD}배포 모드 : ${CYAN}일반 사용자 모드 (Non-root / User Mode)${NC}"
    else
        echo -e "   🛡️ ${BOLD}배포 모드 : ${CYAN}시스템 모드 (Root / System Mode)${NC}"
    fi

    # 1. 기존 설치 감지 및 덮어쓰기/삭제 분기 확인
    check_and_handle_existing_service

    # 2. 배포 방식 선택
    select_deploy_mode

    # 3. 런타임 엔진 선택 (JAR vs Tomcat)
    select_runtime_engine

    # 4. 일반 사용자 모드 사전 유효성 검증
    validate_user_mode_prerequisites

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

    # Tomcat 모드인 경우 호스트 톰캣 환경 확인 및 설정
    if [ "$RUNTIME_ENGINE" = "tomcat" ]; then
        configure_tomcat_env
    fi

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
        "$DEST_DIR/.env"
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

# @description 로그 경로 입력 프롬프트
prompt_log_path() {
    # 기존 서비스 덮어쓰기(OVERWRITE_EXISTING=Y)이고 이미 LOG_PATH가 설정된 경우 추가 질문 없이 유지
    if [ "$OVERWRITE_EXISTING" = "Y" ] && [ -n "$LOG_PATH" ]; then
        log_info "로그 경로: $LOG_PATH"
        return 0
    fi

    local DEST_PROP=""
    if [ "$DEPLOY_MODE" = "docker" ]; then
        DEST_PROP="$DEST_DIR/.env"
    else
        DEST_PROP="$DEST_DIR/bin/.env"
    fi

    LOG_PATH=""
    if [ -f "$DEST_PROP" ]; then
        local LOG_PATH_Line=$(grep "^LOG_PATH=" "$DEST_PROP" 2>/dev/null)
        if [ -n "$LOG_PATH_Line" ]; then
            LOG_PATH=$(echo "$LOG_PATH_Line" | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        fi
    fi

    local DEFAULT_LOG_PATH="${DEFAULT_LOG_BASE:-/log/$APP_NAME}"
    if [ -n "$LOG_PATH" ]; then
        DEFAULT_LOG_PATH="$LOG_PATH"
    fi

    log_info "기본 로그 경로: $DEFAULT_LOG_PATH"
    read -p "   📝 로그 경로를 입력하세요 (엔터 시 기본값 사용): " INPUT_LOG_PATH
    LOG_PATH="${INPUT_LOG_PATH:-$DEFAULT_LOG_PATH}"
}

# @description 설치 경로 결정 (기존 설치 감지 또는 사용자 입력)
determine_install_dir() {
    log_step "설치 위치 설정"

    # 기존 서비스 덮어쓰기(OVERWRITE_EXISTING=Y)인 경우 추가 입력 없이 기존 위치 유지
    if [ "$OVERWRITE_EXISTING" != "Y" ] || [ -z "$DEST_DIR" ]; then
        # 기존 설치 감지 (사전 감지가 안 되었을 경우의 Fallback)
        PREVIOUS_INSTALL_LOC=""

        # 0. User Mode Systemd 감지
        if [ -f "$USER_HOME/.config/systemd/user/$APP_NAME.service" ]; then
            EXEC_START=$(grep "ExecStart=" "$USER_HOME/.config/systemd/user/$APP_NAME.service" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
            if [ -n "$EXEC_START" ]; then
                PREVIOUS_INSTALL_LOC=$(dirname "$(dirname "$EXEC_START")")
            fi
        fi

        # 1. Systemd 감지 (System Mode)
        if [ -z "$PREVIOUS_INSTALL_LOC" ] && command -v systemctl >/dev/null 2>&1; then
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
    fi

    log_info "최종 설치 위치: $DEST_DIR"
    
    prompt_log_path
    
    log_info "서비스 실행 유저: $REAL_USER"

    # 경로 쓰기 권한 검증 (일반 사용자 모드 및 시스템 모드 공통 검증)
    validate_path_writable "$DEST_DIR" "설치 위치"
    validate_path_writable "$LOG_PATH" "로그 경로"

    # 디렉토리 생성 및 권한 설정
    mkdir -p "$DEST_DIR/bin"
    mkdir -p "$DEST_DIR/config"
    mkdir -p "$DEST_DIR/libs"
    mkdir -p "$DEST_DIR/run"

    # 실행 파일 디렉토리 소유권 설정 (현재 로그인 유저)
    chown $REAL_USER:$SERVICE_GROUP "$DEST_DIR" "$DEST_DIR/bin" "$DEST_DIR/config" "$DEST_DIR/libs" "$DEST_DIR/run"
    chmod 755 "$DEST_DIR" "$DEST_DIR/bin" "$DEST_DIR/config" "$DEST_DIR/libs" "$DEST_DIR/run"

    log_success "설치 디렉토리 준비 완료."
}

# @description 배포 파일 복사 (bin, libs, config)
copy_legacy_files() {
    log_step "파일 복사 및 배포 중..."

    # 1. Libs (Jar) - libs 및 lib 디렉토리 호환
    if [ -d "$PKG_ROOT/libs" ]; then
        cp -f "$PKG_ROOT/libs/"*.jar "$DEST_DIR/libs/" 2>/dev/null || true
    elif [ -d "$PKG_ROOT/lib" ]; then
        cp -f "$PKG_ROOT/lib/"*.jar "$DEST_DIR/libs/" 2>/dev/null || true
    fi

    # 1-1. Webapps / Tomcat (Tomcat 배포 시)
    if [ -d "$PKG_ROOT/webapps" ]; then
        mkdir -p "$DEST_DIR/webapps"
        cp -rf "$PKG_ROOT/webapps/"* "$DEST_DIR/webapps/" 2>/dev/null || true
    fi
    if [ -d "$PKG_ROOT/tomcat" ]; then
        mkdir -p "$DEST_DIR/tomcat"
        cp -rf "$PKG_ROOT/tomcat/"* "$DEST_DIR/tomcat/" 2>/dev/null || true
    fi

    # 2. Bin Scripts
    # 서비스 실행에 필요한 스크립트 복사 (start.sh, stop.sh, status.sh 등)
    local SERVICE_SRC=""
    if [ -d "$PKG_ROOT/bin" ]; then
        SERVICE_SRC="$PKG_ROOT/bin"
    elif [ -d "$PKG_ROOT/scripts/service" ]; then
        SERVICE_SRC="$PKG_ROOT/scripts/service"
    else
        SERVICE_SRC="$SCRIPT_DIR"
    fi

    local SERVICE_SCRIPTS=("start.sh" "stop.sh" "status.sh")
    for script in "${SERVICE_SCRIPTS[@]}"; do
        if [ -f "$SERVICE_SRC/$script" ]; then
            cp -f "$SERVICE_SRC/$script" "$DEST_DIR/bin/"
        elif [ -f "$SCRIPT_DIR/$script" ]; then
            cp -f "$SCRIPT_DIR/$script" "$DEST_DIR/bin/"
        fi
    done

    # cron 디렉토리 복사
    if [ -d "$SERVICE_SRC/cron" ]; then
        cp -rf "$SERVICE_SRC/cron" "$DEST_DIR/bin/"
    elif [ -d "$SCRIPT_DIR/cron" ]; then
        cp -rf "$SCRIPT_DIR/cron" "$DEST_DIR/bin/"
    fi

    # 관리 및 유틸리티 스크립트 복사 (uninstall_service.sh, utils.sh, bootstrap.sh)
    local MGMT_SCRIPTS=("uninstall_service.sh" "utils.sh" "bootstrap.sh")
    for script in "${MGMT_SCRIPTS[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            cp -f "$SCRIPT_DIR/$script" "$DEST_DIR/bin/"
        elif [ -f "$PKG_ROOT/deploy/$script" ]; then
            cp -f "$PKG_ROOT/deploy/$script" "$DEST_DIR/bin/"
        elif [ -f "$PKG_ROOT/bin/$script" ]; then
            cp -f "$PKG_ROOT/bin/$script" "$DEST_DIR/bin/"
        elif [ -f "$PKG_ROOT/scripts/common/$script" ]; then
            cp -f "$PKG_ROOT/scripts/common/$script" "$DEST_DIR/bin/"
        fi
    done

    # 4. Config (숨김 파일 .env 포함 복사)
    cp -rf "$PKG_ROOT/config/." "$DEST_DIR/config/"

    # 5. 추가 디렉토리 복사 (EXTRA_DIRS 설정 및 패키지 내 사용자 디렉토리 자동 감지)
    local CONFIGURED_EXTRA_DIRS="$EXTRA_DIRS"
    if [ -z "$CONFIGURED_EXTRA_DIRS" ] && [ -f "$PKG_ROOT/bin/.env" ]; then
        CONFIGURED_EXTRA_DIRS=$(grep "^EXTRA_DIRS=" "$PKG_ROOT/bin/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'")
    fi

    if [ -n "$CONFIGURED_EXTRA_DIRS" ]; then
        for extra_dir in $CONFIGURED_EXTRA_DIRS; do
            if [ -d "$PKG_ROOT/$extra_dir" ]; then
                log_info "추가 디렉토리 복사 중: $extra_dir"
                cp -rf "$PKG_ROOT/$extra_dir" "$DEST_DIR/"
                chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR/$extra_dir"
                chmod -R 755 "$DEST_DIR/$extra_dir"
            fi
        done
    fi

    # 패키지 루트의 비표준 사용자 정의 디렉토리 자동 복사 (flags 등)
    for item in "$PKG_ROOT"/*; do
        if [ -d "$item" ]; then
            local bname=$(basename "$item")
            case "$bname" in
                bin|libs|lib|config|docker|deploy|scripts) ;;
                *)
                    if [ ! -d "$DEST_DIR/$bname" ]; then
                        log_info "패키지 내 추가 디렉토리 자동 복사 중: $bname"
                        cp -rf "$item" "$DEST_DIR/"
                        chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR/$bname"
                        chmod -R 755 "$DEST_DIR/$bname"
                    fi
                    ;;
            esac
        fi
    done

    # 권한 설정
    chmod 755 "$DEST_DIR/bin/"*.sh
    chmod 644 "$DEST_DIR/libs/"*.jar
    find "$DEST_DIR/config" -type f -exec chmod 644 {} +
    find "$DEST_DIR/config" -type d -exec chmod 755 {} +

    # 배포된 파일 소유권 설정 (현재 로그인 유저)
    chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"

    # .env 보안 권한 (640, $REAL_USER:$SERVICE_GROUP)
    if [ -f "$DEST_DIR/bin/.env" ]; then
        chmod 640 "$DEST_DIR/bin/.env"
        chown "$REAL_USER:$SERVICE_GROUP" "$DEST_DIR/bin/.env"
    fi

    log_success "파일 복사 및 권한 설정 완료."
}


# @description 환경 변수 설정 및 로그 경로 확인 (Legacy 모드)
configure_legacy_env() {
    log_step "환경 설정 및 로그 경로 확인"

    DEST_PROP_FILE="$DEST_DIR/bin/.env"

    if [ ! -f "$DEST_PROP_FILE" ]; then
        mkdir -p "$(dirname "$DEST_PROP_FILE")"
        echo "# Application Deployment Configuration" > "$DEST_PROP_FILE"
        chmod 640 "$DEST_PROP_FILE"
        chown "$REAL_USER:$SERVICE_GROUP" "$DEST_PROP_FILE"
        log_info "새로운 환경 설정 파일 생성: $DEST_PROP_FILE"
    fi



    if grep -q "^LOG_PATH=" "$DEST_PROP_FILE"; then
        sed -i "/^LOG_PATH=/c\\LOG_PATH=\"$LOG_PATH\"" "$DEST_PROP_FILE"
    else
        echo "LOG_PATH=\"$LOG_PATH\"" >> "$DEST_PROP_FILE"
    fi
    chmod 640 "$DEST_PROP_FILE"
    chown "$REAL_USER:$SERVICE_GROUP" "$DEST_PROP_FILE"
    log_info "환경 설정 파일에 LOG_PATH 저장 완료."

    # PID_FILE 설정
    NEW_PID_FILE="$DEST_DIR/run/application.pid"
    if grep -q "^PID_FILE=" "$DEST_PROP_FILE"; then
        sed -i "/^PID_FILE=/c\\PID_FILE=\"$NEW_PID_FILE\"" "$DEST_PROP_FILE"
    else
        echo "PID_FILE=\"$NEW_PID_FILE\"" >> "$DEST_PROP_FILE"
    fi
    chmod 640 "$DEST_PROP_FILE"
    chown "$REAL_USER:$SERVICE_GROUP" "$DEST_PROP_FILE"
    log_info "환경 설정 파일에 PID_FILE 저장 완료."

    log_info "로그 경로: $LOG_PATH"

    # 호스트 로그 디렉토리 및 서브 디렉토리(app, tomcat) 사전 생성
    # Docker 데몬이 root 권한으로 하위 디렉토리를 자동 생성하는 것을 방지
    mkdir -p "$LOG_PATH" "$LOG_PATH/app" "$LOG_PATH/tomcat"
    chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"
    chmod -R 775 "$LOG_PATH"
    log_success "로그 디렉토리 준비 완료 ($LOG_PATH/app, tomcat)."

    create_tail_log_script
}

# @description Tomcat 호스트 환경 설정 및 CATALINA_HOME 검증
configure_tomcat_env() {
    log_header "Apache Tomcat 호스트 환경 설정 확인"

    # 1. 기존 지정값 유효성 확인
    if [ -n "$TARGET_CATALINA_HOME" ] && [ -f "$TARGET_CATALINA_HOME/bin/catalina.sh" ]; then
        log_info "지정된 CATALINA_HOME 사용: $TARGET_CATALINA_HOME"
    else
        # 2. 호스트 톰캣 자동 탐색
        local DETECTED_TOMCAT=""
        local SEARCH_PATHS=(
            "/usr/local/tomcat"
            "/opt/tomcat"
            "/opt/apache-tomcat"
            "/usr/share/tomcat"
        )
        for p in "${SEARCH_PATHS[@]}"; do
            if [ -d "$p" ] && [ -f "$p/bin/catalina.sh" ]; then
                DETECTED_TOMCAT="$p"
                break
            fi
        done
        if [ -z "$DETECTED_TOMCAT" ]; then
            for p in /opt/apache-tomcat-* /usr/local/apache-tomcat-*; do
                if [ -d "$p" ] && [ -f "$p/bin/catalina.sh" ]; then
                    DETECTED_TOMCAT="$p"
                    break
                fi
            done
        fi

        echo ""
        echo -e "   ${BOLD}호스트 서버의 Apache Tomcat 설치 경로(CATALINA_HOME)를 입력하세요:${NC}"
        if [ -n "$DETECTED_TOMCAT" ]; then
            echo -e "   (감지된 기본 경로: ${CYAN}$DETECTED_TOMCAT${NC})"
        fi

        while true; do
            read -p "   Tomcat 경로 (기본값: ${DETECTED_TOMCAT:-/opt/tomcat}): " USER_TOMCAT_INPUT
            USER_TOMCAT_INPUT="${USER_TOMCAT_INPUT:-${DETECTED_TOMCAT:-/opt/tomcat}}"

            if [ -f "$USER_TOMCAT_INPUT/bin/catalina.sh" ]; then
                TARGET_CATALINA_HOME="$USER_TOMCAT_INPUT"
                log_success "유효한 Tomcat 설치 경로 확인 완료: $TARGET_CATALINA_HOME"
                break
            else
                log_error "해당 경로에서 bin/catalina.sh 를 찾을 수 없습니다: $USER_TOMCAT_INPUT"
                echo -e "   ${YELLOW}Tomcat이 설치된 올바른 디렉터리 경로를 다시 입력해 주세요.${NC}"
            fi
        done
    fi

    # 3. .env 환경 파일에 CATALINA_HOME 영구 저장
    local ENV_FILE="$DEST_DIR/bin/.env"
    if [ -f "$ENV_FILE" ]; then
        if grep -q "^CATALINA_HOME=" "$ENV_FILE"; then
            sed -i "/^CATALINA_HOME=/c\CATALINA_HOME="$TARGET_CATALINA_HOME"" "$ENV_FILE"
        else
            echo "CATALINA_HOME="$TARGET_CATALINA_HOME"" >> "$ENV_FILE"
        fi
        if grep -q "^CATALINA_BASE=" "$ENV_FILE"; then
            sed -i "/^CATALINA_BASE=/c\CATALINA_BASE="$TARGET_CATALINA_HOME"" "$ENV_FILE"
        else
            echo "CATALINA_BASE="$TARGET_CATALINA_HOME"" >> "$ENV_FILE"
        fi
    fi

    # 4. Systemd 서비스 파일에 주입할 환경변수 등록
    SYSTEMD_EXTRA_ENV="Environment="CATALINA_HOME=$TARGET_CATALINA_HOME"
Environment="CATALINA_BASE=$TARGET_CATALINA_HOME""
    log_info "CATALINA_HOME 환경 설정이 완료되었습니다."
}

# @description Systemd 또는 SysVinit에 Legacy 서비스 등록
register_legacy_service() {
    log_step "서비스 등록 및 시작..."
    START_SCRIPT="$DEST_DIR/bin/start.sh"
    STOP_SCRIPT="$DEST_DIR/bin/stop.sh"

    # 1. 일반 사용자 모드 (--user)
    if [ "$IS_USER_MODE" -eq 1 ]; then
        if command -v systemctl >/dev/null 2>&1; then
            local USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
            mkdir -p "$USER_SYSTEMD_DIR"
            SERVICE_FILE="$USER_SYSTEMD_DIR/$APP_NAME.service"

            cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=$APP_NAME 서비스 (User Mode)
After=network.target

[Service]
Type=forking
WorkingDirectory=$DEST_DIR
$( [ -n "$SYSTEMD_EXTRA_ENV" ] && echo -e "$SYSTEMD_EXTRA_ENV" )
ExecStart=$START_SCRIPT
ExecStop=$STOP_SCRIPT
PIDFile=$DEST_DIR/run/application.pid
Restart=always

[Install]
WantedBy=default.target
EOF

            log_success "$SERVICE_FILE 파일이 갱신되었습니다 (User Mode)."
            systemctl --user daemon-reload
            systemctl --user enable $APP_NAME
            if systemctl --user is-active --quiet $APP_NAME 2>/dev/null; then
                log_info "서비스가 실행 중입니다. 재시작합니다..."
                systemctl --user restart $APP_NAME
            else
                systemctl --user start $APP_NAME
                log_success "서비스가 시작되었습니다 (User Mode)."
            fi

            register_cron
            check_legacy_service_status
            print_user_mode_post_instructions
            return 0
        else
            log_warning "systemctl 명령을 찾을 수 없어 직접 백그라운드로 실행합니다."
            "$START_SCRIPT"
            register_cron
            check_legacy_service_status
            print_user_mode_post_instructions
            return 0
        fi
    fi

    # 2. 시스템 모드 (Root Mode)
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
WorkingDirectory=$DEST_DIR
$( [ -n "$SYSTEMD_EXTRA_ENV" ] && echo -e "$SYSTEMD_EXTRA_ENV" )
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

    # docker-compose 및 관련 파일 복사
    copy_docker_files

    # 환경 설정 (LOG_PATH 등)
    configure_docker_env

    # Docker 이미지 준비 (Load 또는 Build)
    load_or_build_docker_image

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

    # 기존 서비스 덮어쓰기(OVERWRITE_EXISTING=Y)인 경우 추가 입력 없이 기존 위치 유지
    if [ "$OVERWRITE_EXISTING" != "Y" ] || [ -z "$DEST_DIR" ]; then
        # 기존 설치 위치 감지 (사전 감지가 안 되었을 경우의 Fallback)
        DEST_DIR=""

        # 0. User Mode Systemd 감지
        if [ -f "$USER_HOME/.config/systemd/user/$APP_NAME.service" ]; then
            local EXISTING_USER_DIR
            EXISTING_USER_DIR=$(grep "WorkingDirectory=" "$USER_HOME/.config/systemd/user/$APP_NAME.service" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
            if [ -n "$EXISTING_USER_DIR" ] && [ -d "$EXISTING_USER_DIR" ]; then
                log_info "기존 설치 위치 감지 (User Mode): $EXISTING_USER_DIR"
                read -p "   기존 위치에 덮어쓰시겠습니까? (Y/n): " REUSE_LOC
                REUSE_LOC=${REUSE_LOC:-Y}
                if [[ "$REUSE_LOC" =~ ^[Yy]$ ]]; then
                    DEST_DIR="$EXISTING_USER_DIR"
                fi
            fi
        fi

        # 1. System Mode Systemd 감지
        if [ -z "$DEST_DIR" ] && [ -f "/etc/systemd/system/$APP_NAME.service" ]; then
            EXISTING_DIR=$(grep "WorkingDirectory=" "/etc/systemd/system/$APP_NAME.service" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
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
    fi

    log_info "설치 위치: $DEST_DIR"

    prompt_log_path

    # 경로 쓰기 권한 검증 (일반 사용자 모드 및 시스템 모드 공통)
    validate_path_writable "$DEST_DIR" "설치 위치"
    validate_path_writable "$LOG_PATH" "로그 경로"

    mkdir -p "$DEST_DIR/bin"
    mkdir -p "$DEST_DIR/config"

    # 실행 파일 디렉토리 소유권 설정 (현재 로그인 유저)
    chown $REAL_USER:$SERVICE_GROUP "$DEST_DIR" "$DEST_DIR/bin" "$DEST_DIR/config"
    chmod 755 "$DEST_DIR" "$DEST_DIR/bin" "$DEST_DIR/config"

    chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"
    
    log_success "설치 디렉토리 준비 완료."
}

# @description dist 패키지 파일로 Docker 이미지를 준비 (Load 또는 Build)
# PKG_ROOT 내에 .tar 파일이 있으면 docker load, Dockerfile이 있으면 docker build
load_or_build_docker_image() {
    local TAR_FILE="$PKG_ROOT/${APP_NAME}.tar"
    local DOCKERFILE_PATH="$PKG_ROOT/docker/Dockerfile"
    local IMAGE_TAG="@dockerImage@"

    if [ -f "$TAR_FILE" ]; then
        log_step "Docker 이미지 로드 중 ($TAR_FILE)..."
        docker load -i "$TAR_FILE"
        if [ $? -ne 0 ]; then
            log_error "Docker 이미지 로드 실패"
            exit 1
        fi
        log_success "Docker 이미지 로드 완료."
    elif [ -f "$DOCKERFILE_PATH" ] && ([ -d "$PKG_ROOT/libs" ] || [ -d "$PKG_ROOT/lib" ] || [ -d "$PKG_ROOT/webapps" ]); then
        log_step "Docker 이미지 빌드 중 (Dockerfile 기반)..."
        log_info "빌드 컨텍스트: $PKG_ROOT"
        log_info "Dockerfile: $DOCKERFILE_PATH"
        log_info "이미지 태그: $IMAGE_TAG"

        docker build --build-arg APP_NAME="$APP_NAME" -t "$IMAGE_TAG" -f "$DOCKERFILE_PATH" "$PKG_ROOT"
        if [ $? -ne 0 ]; then
            log_error "Docker 이미지 빌드 실패"
            exit 1
        fi
    else
        log_step "원격 레지스트리에서 Docker 이미지 다운로드 중 (docker pull $IMAGE_TAG)..."
        docker pull "$IMAGE_TAG"
        if [ $? -ne 0 ]; then
            log_error "Docker 이미지 다운로드 실패: $IMAGE_TAG"
            log_warning "사설 레지스트리인 경우 'docker login' 및 Docker 데몬의 insecure-registries 설정을 확인해주세요."
            exit 1
        fi
        log_success "Docker 이미지 다운로드 완료: $IMAGE_TAG"
    fi
}

# @description Docker 관련 파일 복사 (docker-compose, uninstall 스크립트 등)
copy_docker_files() {
    log_step "Docker 배포 파일 복사 중..."

    # 1. docker 파일 복제
    local DOCKER_DIR="$PKG_ROOT/docker"
    local COMPOSE_SRC="$DOCKER_DIR/docker-compose.yml"

    if [ ! -f "$COMPOSE_SRC" ]; then
        log_error "docker-compose.yml을 찾을 수 없습니다: $COMPOSE_SRC"
        exit 1
    fi

    cp "$COMPOSE_SRC" "$DEST_DIR/"

    # 2. Bin Scripts
    # Docker 실행 및 관리에 필요한 스크립트 복사 (Legacy와 일관된 인터페이스 제공)
    local MGMT_SCRIPTS=("start.sh" "stop.sh" "status.sh" "uninstall_service.sh" "utils.sh" "bootstrap.sh")
    for script in "${MGMT_SCRIPTS[@]}"; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            cp -rf "$SCRIPT_DIR/$script" "$DEST_DIR/bin/"
        elif [ -f "$PKG_ROOT/bin/$script" ]; then
            cp -rf "$PKG_ROOT/bin/$script" "$DEST_DIR/bin/"
        elif [ -f "$PKG_ROOT/scripts/service/$script" ]; then
            cp -rf "$PKG_ROOT/scripts/service/$script" "$DEST_DIR/bin/"
        elif [ -f "$PKG_ROOT/deploy/$script" ]; then
            cp -rf "$PKG_ROOT/deploy/$script" "$DEST_DIR/bin/"
        elif [ -f "$PKG_ROOT/scripts/common/$script" ]; then
            cp -rf "$PKG_ROOT/scripts/common/$script" "$DEST_DIR/bin/"
        fi
    done

    # cron 디렉토리 복사
    local CRON_SRC=""
    if [ -d "$PKG_ROOT/bin/cron" ]; then
        CRON_SRC="$PKG_ROOT/bin/cron"
    elif [ -d "$PKG_ROOT/scripts/service/cron" ]; then
        CRON_SRC="$PKG_ROOT/scripts/service/cron"
    elif [ -d "$SCRIPT_DIR/cron" ]; then
        CRON_SRC="$SCRIPT_DIR/cron"
    fi
    if [ -n "$CRON_SRC" ]; then
        cp -rf "$CRON_SRC" "$DEST_DIR/bin/"
    fi

    # config 폴더 복사 (Host Mount용)
    local CONFIG_SRC="$PKG_ROOT/config"
    if [ -d "$CONFIG_SRC" ]; then
        cp -r "$CONFIG_SRC" "$DEST_DIR/"
        log_info "config 폴더 복사 완료 (Host Mount용)"
    fi

    # 추가 디렉토리 복사 (EXTRA_DIRS 설정 및 패키지 내 사용자 디렉토리 자동 감지)
    local CONFIGURED_EXTRA_DIRS="$EXTRA_DIRS"
    if [ -z "$CONFIGURED_EXTRA_DIRS" ] && [ -f "$DEST_DIR/.env" ]; then
        CONFIGURED_EXTRA_DIRS=$(grep "^EXTRA_DIRS=" "$DEST_DIR/.env" 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d "'")
    fi

    if [ -n "$CONFIGURED_EXTRA_DIRS" ]; then
        for extra_dir in $CONFIGURED_EXTRA_DIRS; do
            if [ -d "$PKG_ROOT/$extra_dir" ]; then
                log_info "추가 디렉토리 복사 중: $extra_dir"
                cp -rf "$PKG_ROOT/$extra_dir" "$DEST_DIR/"
                chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR/$extra_dir"
                chmod -R 755 "$DEST_DIR/$extra_dir"
            fi
        done
    fi

    # 패키지 루트의 비표준 사용자 정의 디렉토리 자동 복사 (flags 등)
    for item in "$PKG_ROOT"/*; do
        if [ -d "$item" ]; then
            local bname=$(basename "$item")
            case "$bname" in
                bin|libs|lib|config|docker|deploy|scripts) ;;
                *)
                    if [ ! -d "$DEST_DIR/$bname" ]; then
                        log_info "패키지 내 추가 디렉토리 자동 복사 중: $bname"
                        cp -rf "$item" "$DEST_DIR/"
                        chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR/$bname"
                        chmod -R 755 "$DEST_DIR/$bname"
                    fi
                    ;;
            esac
        fi
    done

    # 권한 설정
    chmod 755 "$DEST_DIR/bin/"*.sh
    find "$DEST_DIR/config" -type f -exec chmod 644 {} +
    find "$DEST_DIR/config" -type d -exec chmod 755 {} +

    # 배포된 파일 소유권 설정 (현재 로그인 유저)
    [ -f "$DEST_DIR/docker-compose.yml" ] && chmod 644 "$DEST_DIR/docker-compose.yml"
    chown -R $REAL_USER:$SERVICE_GROUP "$DEST_DIR"

    log_success "파일 복사 및 권한 설정 완료."
}

# @description 환경 변수 설정 (Docker 모드 - LOG_PATH 등)
configure_docker_env() {
    log_step "환경 설정 및 로그 경로 확인"

    log_info "로그 경로: $LOG_PATH"

    # 호스트 로그 디렉토리 및 서브 디렉토리(app, tomcat) 사전 생성
    # Docker 데몬이 root 권한으로 하위 디렉토리를 자동 생성하는 것을 방지
    mkdir -p "$LOG_PATH" "$LOG_PATH/app" "$LOG_PATH/tomcat"
    chown -R $REAL_USER:$SERVICE_GROUP "$LOG_PATH"
    chmod -R 775 "$LOG_PATH"
    log_success "로그 디렉토리 준비 완료 ($LOG_PATH/app, tomcat)."

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

    local REAL_UID=$(id -u "$REAL_USER")
    local REAL_GID=$(id -g "$REAL_USER")

    cat <<EOF > "$ENV_FILE"
# ==========================================================
# Docker Compose Environment Variables
# Generated by install_service.sh
# ==========================================================
APP_UID=$REAL_UID
APP_GID=$REAL_GID

APP_NAME=$APP_NAME
HTTP_PORT=${HTTP_PORT:-@httpPort@}

# [호스트 환경] 로그 및 설치 디렉토리 (Legacy 모드 로그 경로 겸용)
LOG_PATH=$LOG_PATH
DEST_DIR=$DEST_DIR

# [컨테이너 환경] 컨테이너 내부 서비스 로그 경로
CONTAINER_LOG_PATH=/log

DOCKER_IMAGE=@dockerImage@
EOF

    chown "$REAL_USER:$SERVICE_GROUP" "$ENV_FILE"
    log_success "환경 및 볼륨(.env) 설정 업데이트 완료"

    # 빈 config 폴더 마운트로 인한 컨테이너 내부 config 초기화 방지
    local CONFIG_DIR="$DEST_DIR/config"
    mkdir -p "$CONFIG_DIR"

    if [ -z "$(ls -A "$CONFIG_DIR")" ]; then
        log_step "초기 Host Config 파일 생성 중..."
        docker run --rm -v "$CONFIG_DIR:/tmp_config" "${APP_NAME}:latest" sh -c "cp -r /app/config/* /tmp_config/ 2>/dev/null || true"
        chown -R $REAL_USER:$SERVICE_GROUP "$CONFIG_DIR"
        log_success "Host Config 마운트 폴더 초기화 완료"
    fi
}

# @description Docker 서비스를 Systemd 또는 SysVinit에 등록
register_docker_service() {
    # Docker Compose 명령어 감지
    detect_docker_compose_cmd "true"
    log_info "Docker Compose 명령어: $DOCKER_COMPOSE_CMD"

    local COMPOSE_FILE="$DEST_DIR/docker-compose.yml"
    local START_SCRIPT="$DEST_DIR/bin/start.sh"
    local STOP_SCRIPT="$DEST_DIR/bin/stop.sh"
    local STATUS_SCRIPT="$DEST_DIR/bin/status.sh"

    log_step "서비스 등록 및 시작 (스크립트 래퍼 연동)..."

    # 1. 일반 사용자 모드 (--user)
    if [ "$IS_USER_MODE" -eq 1 ]; then
        if command -v systemctl >/dev/null 2>&1; then
            local USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
            mkdir -p "$USER_SYSTEMD_DIR"
            local SERVICE_FILE="$USER_SYSTEMD_DIR/$APP_NAME.service"

            cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=$APP_NAME Docker Container Service (User Mode)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DEST_DIR
ExecStart=$START_SCRIPT
ExecStop=$STOP_SCRIPT
Restart=always

[Install]
WantedBy=default.target
EOF

            log_success "$SERVICE_FILE 파일이 생성되었습니다 (User Mode)."
            systemctl --user daemon-reload
            systemctl --user enable $APP_NAME

            if systemctl --user is-active --quiet $APP_NAME 2>/dev/null; then
                log_info "서비스가 실행 중입니다. 재시작합니다..."
                systemctl --user restart $APP_NAME
            else
                systemctl --user start $APP_NAME
                log_success "서비스가 시작되었습니다 (User Mode)."
            fi

            register_cron

            sleep 2
            local CONTAINER_STATUS
            local CONTAINER_ID
            CONTAINER_STATUS=$(docker ps -f "name=${APP_NAME}" --format "{{.Status}}")
            CONTAINER_ID=$(docker ps -f "name=${APP_NAME}" --format "{{.ID}}")

            echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${BLUE}║                  🐳 DOCKER SERVICE STARTED                     ║${NC}"
            echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}SERVICE${NC}    : ${CYAN}$APP_NAME${NC} (User Mode)"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}CONTAINER${NC}  : ${GREEN}$CONTAINER_ID${NC}"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}STATUS${NC}     : ${GREEN}$CONTAINER_STATUS${NC}"
            echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}LOG${NC}        : ${YELLOW}$LOG_PATH/${NC}"
            echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"

            print_user_mode_post_instructions
            return 0
        else
            log_warning "systemctl 명령을 찾을 수 없어 Docker Compose를 직접 백그라운드로 실행합니다."
            "$START_SCRIPT" -d
            register_cron
            print_user_mode_post_instructions
            return 0
        fi
    fi

    # 2. 시스템 모드 (Root Mode)
    local INIT_SYSTEM="sysvinit"
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif [ -f /etc/init.d/cron ] || [ -f /etc/init.d/functions ]; then
        INIT_SYSTEM="sysvinit"
    else
        log_error "알 수 없는 Init 시스템입니다."
        exit 1
    fi

    if [ "$INIT_SYSTEM" = "systemd" ]; then
        local SERVICE_FILE="/etc/systemd/system/$APP_NAME.service"

        cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=$APP_NAME Docker Container Service
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
User=$REAL_USER
Group=$SERVICE_GROUP
Type=simple
WorkingDirectory=$DEST_DIR
ExecStart=$START_SCRIPT
ExecStop=$STOP_SCRIPT
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
        CONTAINER_STATUS=$(docker ps -f "name=${APP_NAME}" --format "{{.Status}}")
        CONTAINER_ID=$(docker ps -f "name=${APP_NAME}" --format "{{.ID}}")

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
        su - $REAL_USER -c "$START_SCRIPT -d"
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

        log_success "서비스가 등록되었습니다 (sysvinit)"
        service $APP_NAME restart
    fi
}

# ============================================================
# 공통 유틸리티 함수
# ============================================================

# @description Cron 작업 등록
register_cron() {
    log_step "Cron 작업 등록..."
    local SRC_CRON_FILE="$PKG_ROOT/bin/cron/crond"

    if [ "$IS_USER_MODE" -eq 1 ]; then
        if [ -f "$SRC_CRON_FILE" ] && command -v crontab >/dev/null 2>&1; then
            local CRON_LINE
            CRON_LINE=$(sed -e "s|@LOG_PATH@|$LOG_PATH|g" \
                            -e "s|@APP_NAME@|$APP_NAME|g" \
                            -e "s|@REAL_USER@ ||g" \
                            "$SRC_CRON_FILE" | grep -v "^#" | grep -v "^\s*$" | head -n 1)

            if [ -n "$CRON_LINE" ]; then
                local TMP_CRON=$(mktemp)
                (crontab -l 2>/dev/null | grep -v "$APP_NAME" || true) > "$TMP_CRON"
                echo "$CRON_LINE # $APP_NAME auto log cleanup" >> "$TMP_CRON"
                crontab "$TMP_CRON" 2>/dev/null || true
                rm -f "$TMP_CRON"
                log_success "사용자 Cron 작업이 등록되었습니다 (crontab)."
            fi
        else
            log_info "Cron 등록을 건너뜁니다."
        fi
        return 0
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
        cat <<'EOF' > "$TARGET_TAIL_SCRIPT"
#!/bin/bash
# Docker 로그 확인 스크립트

APP_NAME="APP_NAME_PLACEHOLDER"
DEST_DIR="DEST_DIR_PLACEHOLDER"

if [ -f "$DEST_DIR/.env" ]; then
    source "$DEST_DIR/.env"
fi

# 로그 파일 경로 탐색 (app 디렉토리 우선 -> 루트 디렉토리 순)
LOG_FILE=""
if [ -f "$LOG_PATH/app/${APP_NAME}.log" ]; then
    LOG_FILE="$LOG_PATH/app/${APP_NAME}.log"
elif [ -f "$LOG_PATH/${APP_NAME}.log" ]; then
    LOG_FILE="$LOG_PATH/${APP_NAME}.log"
fi

if [ -n "$LOG_FILE" ] && [ -f "$LOG_FILE" ]; then
    echo "로그 파일($LOG_FILE)을 추적합니다..."
    tail -F -n 1000 "$LOG_FILE"
else
    echo "로그 파일이 아직 생성되지 않았거나 경로가 다릅니다."
    echo "Docker 컨테이너 콘솔 로그를 확인합니다..."
    docker logs -f --tail 1000 ${APP_NAME}
fi
EOF
    else
        cat <<'EOF' > "$TARGET_TAIL_SCRIPT"
#!/bin/bash

APP_NAME="APP_NAME_PLACEHOLDER"
DEST_DIR="DEST_DIR_PLACEHOLDER"

if [ -f "$DEST_DIR/bin/.env" ]; then
    source "$DEST_DIR/bin/.env"
fi

LOG_FILE=""
if [ -f "$LOG_PATH/app/${APP_NAME}.log" ]; then
    LOG_FILE="$LOG_PATH/app/${APP_NAME}.log"
elif [ -f "$LOG_PATH/${APP_NAME}.log" ]; then
    LOG_FILE="$LOG_PATH/${APP_NAME}.log"
fi

if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
    echo "로그 파일을 찾을 수 없습니다: $LOG_PATH/${APP_NAME}.log 또는 $LOG_PATH/app/${APP_NAME}.log"
    echo "서비스가 실행 중인지 확인해주세요."
    exit 1
fi
echo "로그 파일($LOG_FILE)을 추적합니다..."
tail -F -n 1000 "$LOG_FILE"
EOF
    fi

    # Placeholder 치환
    sed -i "s|APP_NAME_PLACEHOLDER|$APP_NAME|g" "$TARGET_TAIL_SCRIPT"
    sed -i "s|DEST_DIR_PLACEHOLDER|$DEST_DIR|g" "$TARGET_TAIL_SCRIPT"

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
    local CURRENT_PID=""
    if [ "$IS_USER_MODE" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
        CURRENT_PID=$(systemctl --user show --property MainPID --value "$APP_NAME" 2>/dev/null)
    elif command -v systemctl >/dev/null 2>&1; then
        CURRENT_PID=$(systemctl show --property MainPID --value "$APP_NAME" 2>/dev/null)
    fi

    if [ -z "$CURRENT_PID" ] || [ "$CURRENT_PID" = "0" ]; then
        if [ -f "$DEST_DIR/run/application.pid" ]; then
            CURRENT_PID=$(cat "$DEST_DIR/run/application.pid" 2>/dev/null)
        fi
    fi
    CURRENT_PID="${CURRENT_PID:-Unknown}"

    local DETECTED_PORT="Unknown"
    if [ "$CURRENT_PID" != "Unknown" ] && command -v ss >/dev/null 2>&1; then
        local SS_OUT
        SS_OUT=$(ss -tlnp 2>/dev/null | grep "pid=$CURRENT_PID" || true)
        if [ -n "$SS_OUT" ]; then
            DETECTED_PORT=$(echo "$SS_OUT" | awk '{print $4}' | awk -F':' '{print $NF}')
        fi
    fi

    if [ "$DETECTED_PORT" = "Unknown" ] || [ -z "$DETECTED_PORT" ]; then
        local APP_YML="$DEST_DIR/config/application.yml"
        if [ -f "$APP_YML" ]; then
            local PARSED_PORT
            PARSED_PORT=$(grep -E "^\s*port:\s*[0-9]+" "$APP_YML" 2>/dev/null | awk '{print $2}')
            if [ -n "$PARSED_PORT" ]; then
                DETECTED_PORT="$PARSED_PORT (Configured)"
            fi
        fi
    fi

    local MODE_LABEL=""
    if [ "$IS_USER_MODE" -eq 1 ]; then
        MODE_LABEL=" (User Mode)"
    fi

    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║                  🚀 SERVICE STARTED                            ║${NC}"
    echo -e "${BOLD}${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}SERVICE${NC} : ${CYAN}$APP_NAME${MODE_LABEL}${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PID${NC}     : ${GREEN}$CURRENT_PID${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}PORT${NC}    : ${GREEN}$DETECTED_PORT${NC}"
    echo -e "${BOLD}${BLUE}║${NC} 🔹 ${BOLD}LOG${NC}     : ${YELLOW}$LOG_PATH/${APP_NAME}.log${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
}

# --- [Execution] ---

# 실행 권한 검사
if [ "$IS_USER_MODE" -eq 1 ]; then
    if [ "$EUID" -eq 0 ]; then
        log_warning "일반 사용자 모드(기본값)로 실행 중이나 root 계정으로 실행되었습니다."
        log_info "일반 사용자 권한($REAL_USER) 환경 기준으로 배포를 진행합니다."
    fi
else
    # 시스템 배포 모드(--sudo/--root)는 root 권한 필수
    if [ "$EUID" -ne 0 ]; then
        log_error "이 스크립트는 시스템 배포 모드(--sudo / --root)로 지정되어 root 권한(sudo)으로 실행해야 합니다."
        echo -e "   ${YELLOW}sudo 명령어로 실행해주세요:${NC}"
        echo -e "   👉 ${GREEN}sudo ./install_service.sh --sudo${NC}  또는  ${GREEN}SUDO_MODE=true sudo ./install_service.sh${NC}"
        echo -e "   ${CYAN}💡 일반 사용자 모드로 배포하려면 옵션 없이 단독 실행하세요:${NC}"
        echo -e "   👉 ${GREEN}./install_service.sh${NC}"
        exit 1
    fi
fi

install_service
