#!/bin/bash
# ==============================================================================
# File: rollback_service.sh
# Description: 이전 배포 스냅샷으로 서비스/설정/이미지를 안전하게 복원하는 롤백 스크립트
#              Legacy (JAR / Tomcat) 및 Docker 배포 방식 모두 지원
# Author: 윤명준 (MJ Yun)
# Since: 2026-11-27
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
APP_NAME="@appName@"
if [ "$(basename "$SCRIPT_DIR")" = "bin" ] || [ "$(basename "$SCRIPT_DIR")" = "deploy" ]; then
    PKG_ROOT="$(dirname "$SCRIPT_DIR")"
else
    PKG_ROOT="$SCRIPT_DIR"
fi

if [[ "$APP_NAME" == "@"*"@" ]] || [ -z "$APP_NAME" ]; then
    APP_NAME="$(basename "$PKG_ROOT")"
fi
export APP_NAME

INSTALL_DIR="$PKG_ROOT"
ACTION="rollback"
TARGET_REV=""
AUTO_YES=0
EXPLICIT_USER_MODE=""

# CLI 인자 파싱
for arg in "$@"; do
    case "$arg" in
        --list|-l)
            ACTION="list"
            ;;
        --rev=*)
            TARGET_REV="${arg#*=}"
            ;;
        --yes|-y)
            AUTO_YES=1
            ;;
        --sudo|--root|--system|--system-mode)
            EXPLICIT_USER_MODE=0
            ;;
        --user|--non-root|--user-mode)
            EXPLICIT_USER_MODE=1
            ;;
        --help|-h)
            echo "사용법: $0 [옵션]"
            echo "  --list, -l          보관 중인 롤백 스냅샷 목록 출력"
            echo "  --rev=<REV_ID>      지정한 리비전 스냅샷으로 롤백 (기본값: 직전 버전 latest)"
            echo "  --yes, -y           확인 프롬프트 없이 즉시 롤백 실행"
            echo "  --sudo / --user     권한 모드 명시"
            echo "  --help, -h          도움말 출력"
            exit 0
            ;;
    esac
done

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)
[ -z "$USER_HOME" ] && USER_HOME="$HOME"
SERVICE_GROUP=$(id -gn "$REAL_USER" 2>/dev/null || id -gn 2>/dev/null || echo "users")

# --- [Functions] ---

# @description 실제 서비스 설치 경로(INSTALL_DIR) 자동 감지
#              deploy/ 폴더에서 실행되어 .rollback 이 없는 경우 서비스 등록 정보에서 역추적
resolve_install_dir() {
    if [ -d "$INSTALL_DIR/.rollback" ]; then
        return 0
    fi

    local DETECTED_DIR=""
    local USER_SVC="$USER_HOME/.config/systemd/user/$APP_NAME.service"
    local SYS_SVC="/etc/systemd/system/$APP_NAME.service"
    local INIT_SVC="/etc/init.d/$APP_NAME"

    if [ -f "$USER_SVC" ]; then
        DETECTED_DIR=$(grep "WorkingDirectory=" "$USER_SVC" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
        if [ -z "$DETECTED_DIR" ]; then
            local EXEC_START
            EXEC_START=$(grep "ExecStart=" "$USER_SVC" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
            [ -n "$EXEC_START" ] && DETECTED_DIR=$(dirname "$(dirname "$EXEC_START")")
        fi
    fi

    if [ -z "$DETECTED_DIR" ] && [ -f "$SYS_SVC" ]; then
        DETECTED_DIR=$(grep "WorkingDirectory=" "$SYS_SVC" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
        if [ -z "$DETECTED_DIR" ]; then
            local EXEC_START
            EXEC_START=$(grep "ExecStart=" "$SYS_SVC" 2>/dev/null | cut -d= -f2 | sed 's/^"//;s/"$//')
            [ -n "$EXEC_START" ] && DETECTED_DIR=$(dirname "$(dirname "$EXEC_START")")
        fi
    fi

    if [ -z "$DETECTED_DIR" ] && [ -f "$INIT_SVC" ]; then
        local EXEC_START
        EXEC_START=$(grep "su - " "$INIT_SVC" 2>/dev/null | head -n 1 | awk -F '"' '{print $2}')
        [ -n "$EXEC_START" ] && DETECTED_DIR=$(dirname "$(dirname "$EXEC_START")")
    fi

    if [ -n "$DETECTED_DIR" ] && [ -d "$DETECTED_DIR" ]; then
        INSTALL_DIR="$DETECTED_DIR"
    fi
}

# @description 스냅샷 목록 출력
list_snapshots() {
    local ROLLBACK_BASE="$INSTALL_DIR/.rollback"
    log_header "롤백 가능 스냅샷 목록 ($APP_NAME)" "📋"
    log_info "설치 경로: $INSTALL_DIR"

    if [ ! -d "$ROLLBACK_BASE" ]; then
        log_warning "초기 배포 상태이거나 롤백 스냅샷(.rollback)이 존재하지 않습니다."
        return 1
    fi

    local REVS=()
    while IFS= read -r d; do
        [ -n "$d" ] && REVS+=("$d")
    done < <(find "$ROLLBACK_BASE" -maxdepth 1 -mindepth 1 -type d -name "rev_*" -exec basename {} \; | sort -r)

    if [ ${#REVS[@]} -eq 0 ]; then
        log_warning "보관 중인 롤백 스냅샷이 없습니다."
        return 1
    fi

    local LATEST_REV=""
    if [ -L "$ROLLBACK_BASE/latest" ]; then
        LATEST_REV=$(basename "$(readlink "$ROLLBACK_BASE/latest")")
    fi

    echo ""
    printf "   %-24s %-20s %-10s %-10s %-10s\n" "REVISION" "CREATED_AT" "DEPLOY" "ENGINE" "MODE"
    echo "   --------------------------------------------------------------------------------"
    for rev in "${REVS[@]}"; do
        local META="$ROLLBACK_BASE/$rev/meta.env"
        if [ -f "$META" ]; then
            local CREATED_AT="" DEPLOY_MODE="" RUNTIME_ENGINE="" IS_USER_MODE=""
            source "$META"
            local MODE_STR="system"
            [ "${IS_USER_MODE:-1}" -eq 1 ] && MODE_STR="user"
            local MARK=""
            [ "$rev" = "$LATEST_REV" ] && MARK=" (latest)"
            printf "   %-24s %-20s %-10s %-10s %-10s%s\n" "$rev" "${CREATED_AT:-unknown}" "${DEPLOY_MODE:-unknown}" "${RUNTIME_ENGINE:-unknown}" "$MODE_STR" "$MARK"
        fi
    done
    echo ""
    return 0
}

# @description 롤백할 스냅샷 디렉토리 결정 및 검증
resolve_target_snapshot() {
    local ROLLBACK_BASE="$INSTALL_DIR/.rollback"

    if [ ! -d "$ROLLBACK_BASE" ]; then
        log_error "초기 배포 상태이거나 롤백 스냅샷이 존재하지 않아 롤백할 수 없습니다."
        log_info "확인된 설치 경로: $INSTALL_DIR"
        exit 1
    fi

    if [ -z "$TARGET_REV" ]; then
        if [ -L "$ROLLBACK_BASE/latest" ] && [ -d "$ROLLBACK_BASE/latest" ]; then
            TARGET_REV=$(basename "$(readlink "$ROLLBACK_BASE/latest")")
        else
            TARGET_REV=$(find "$ROLLBACK_BASE" -maxdepth 1 -mindepth 1 -type d -name "rev_*" -exec basename {} \; | sort -r | head -n 1)
        fi
    fi

    if [ -z "$TARGET_REV" ]; then
        log_error "초기 배포 상태이므로 롤백할 이전 버전이 없습니다."
        exit 1
    fi

    SNAP_DIR="$ROLLBACK_BASE/$TARGET_REV"
    if [ ! -d "$SNAP_DIR" ] || [ ! -f "$SNAP_DIR/meta.env" ] || [ ! -f "$SNAP_DIR/app_files.tar.gz" ]; then
        log_error "유효한 롤백 스냅샷을 찾을 수 없습니다: $TARGET_REV"
        exit 1
    fi
}

# @description 현재 실행 중인 서비스 안전 중지
stop_current_service() {
    log_step "현재 서비스 중지 중..."

    # Docker 모드 잔재가 있는 경우 컨테이너 정리
    if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        if detect_docker_compose_cmd false; then
            log_info "Docker 컨테이너 정리 중 (docker-compose down)..."
            $DOCKER_COMPOSE_CMD -f "$INSTALL_DIR/docker-compose.yml" down 2>/dev/null || true
        fi
    fi

    if command -v systemctl >/dev/null 2>&1; then
        local USER_UID
        USER_UID=$(id -u "$REAL_USER" 2>/dev/null || id -u)
        [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$USER_UID" ] && export XDG_RUNTIME_DIR="/run/user/$USER_UID"
        [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -S "/run/user/$USER_UID/bus" ] && export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"

        if systemctl --user is-active --quiet "$APP_NAME" 2>/dev/null; then
            systemctl --user stop "$APP_NAME" 2>/dev/null || true
        fi
        if systemctl is-active --quiet "$APP_NAME" 2>/dev/null; then
            systemctl stop "$APP_NAME" 2>/dev/null || true
        fi
    fi

    if [ -f "/etc/init.d/$APP_NAME" ]; then
        service "$APP_NAME" stop 2>/dev/null || true
    fi

    if [ -x "$INSTALL_DIR/bin/stop.sh" ]; then
        "$INSTALL_DIR/bin/stop.sh" >/dev/null 2>&1 || true
    fi

    log_success "현재 서비스 중지 완료."
}

# @description 현재 설치 디렉토리 내 운영 파일 정리 (.rollback, run, logs 보존)
clean_current_app_files() {
    local item
    for item in "$INSTALL_DIR"/* "$INSTALL_DIR"/.[!.]* "$INSTALL_DIR"/..?*; do
        [ ! -e "$item" ] && [ ! -L "$item" ] && continue
        local bname
        bname=$(basename "$item")
        case "$bname" in
            .|..|.rollback|run|logs)
                ;;
            *)
                rm -rf "$item"
                ;;
        esac
    done
}

# @description 시스템 서비스 Unit / Init / Cron / tail-log 복원
restore_system_configs() {
    log_step "시스템 설정(서비스 등록, Cron, 유틸리티) 복원 중..."

    local SYS_DIR="$SNAP_DIR/system"

    # 1. 기존과 다른 모드의 서비스 파일이 남아있다면 정리
    local USER_SVC="$USER_HOME/.config/systemd/user/$APP_NAME.service"
    local SYS_SVC="/etc/systemd/system/$APP_NAME.service"
    local INIT_SVC="/etc/init.d/$APP_NAME"

    if [ -f "$SYS_DIR/service.unit" ]; then
        case "$INIT_SYSTEM" in
            systemd-user)
                mkdir -p "$(dirname "$USER_SVC")"
                cp -f "$SYS_DIR/service.unit" "$USER_SVC"
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl --user daemon-reload 2>/dev/null || true
                    systemctl --user enable "$APP_NAME" 2>/dev/null || true
                fi
                log_success "User Mode Systemd 서비스 파일 복원 완료: $USER_SVC"
                ;;
            systemd-system)
                cp -f "$SYS_DIR/service.unit" "$SYS_SVC"
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl daemon-reload 2>/dev/null || true
                    systemctl enable "$APP_NAME" 2>/dev/null || true
                fi
                log_success "System Mode Systemd 서비스 파일 복원 완료: $SYS_SVC"
                ;;
            sysvinit)
                cp -f "$SYS_DIR/service.unit" "$INIT_SVC"
                chmod +x "$INIT_SVC"
                if command -v chkconfig >/dev/null 2>&1; then
                    chkconfig --add "$APP_NAME" 2>/dev/null || true
                    chkconfig "$APP_NAME" on 2>/dev/null || true
                elif command -v update-rc.d >/dev/null 2>&1; then
                    update-rc.d "$APP_NAME" defaults 2>/dev/null || true
                fi
                log_success "SysVinit 서비스 스크립트 복원 완료: $INIT_SVC"
                ;;
        esac
    fi

    # 2. Cron 복원
    if [ -f "$SYS_DIR/cron.entry" ] && [ -f "$SYS_DIR/cron.type" ]; then
        local CRON_TYPE
        CRON_TYPE=$(cat "$SYS_DIR/cron.type")
        if [ "$CRON_TYPE" = "user" ] && command -v crontab >/dev/null 2>&1; then
            local TMP_CRON
            TMP_CRON=$(mktemp)
            (crontab -l 2>/dev/null | grep -v "$APP_NAME" || true) > "$TMP_CRON"
            cat "$SYS_DIR/cron.entry" >> "$TMP_CRON"
            crontab "$TMP_CRON" 2>/dev/null || true
            rm -f "$TMP_CRON"
            log_success "사용자 Cron 작업 복원 완료."
        elif [ "$CRON_TYPE" = "system" ] && [ -d "/etc/cron.d" ]; then
            cp -f "$SYS_DIR/cron.entry" "/etc/cron.d/$APP_NAME"
            chmod 644 "/etc/cron.d/$APP_NAME"
            log_success "시스템 Cron 작업 복원 완료: /etc/cron.d/$APP_NAME"
        fi
    fi

    # 3. tail-log 유틸리티 복원
    if [ -f "$SYS_DIR/tail-log.sh" ]; then
        local TAIL_TARGET="$USER_HOME/bin/tail-log-${APP_NAME}.sh"
        mkdir -p "$(dirname "$TAIL_TARGET")"
        cp -f "$SYS_DIR/tail-log.sh" "$TAIL_TARGET"
        chmod +x "$TAIL_TARGET"
        [ "$IS_USER_MODE" -eq 0 ] && chown "$REAL_USER:$SERVICE_GROUP" "$TAIL_TARGET" 2>/dev/null || true
        log_success "로그 확인 스크립트 복원 완료: $TAIL_TARGET"
    fi
}

# @description Tomcat 호스트 설정 및 webapps/ROOT 복원
restore_tomcat_host() {
    if [ "$RUNTIME_ENGINE" != "tomcat" ] || [ -z "${CATALINA_HOME:-}" ] || [ ! -d "$CATALINA_HOME" ]; then
        return 0
    fi
    if [ "$CATALINA_HOME" = "$INSTALL_DIR/tomcat" ]; then
        return 0
    fi

    log_step "Tomcat 호스트 설정 복원 중 ($CATALINA_HOME)..."
    local TOMCAT_BAK="$SNAP_DIR/system/tomcat_host"
    if [ -f "$TOMCAT_BAK/setenv.sh" ]; then
        cp -f "$TOMCAT_BAK/setenv.sh" "$CATALINA_HOME/bin/setenv.sh"
        chmod +x "$CATALINA_HOME/bin/setenv.sh"
    fi
    if [ -d "$TOMCAT_BAK/conf" ]; then
        cp -rf "$TOMCAT_BAK/conf/." "$CATALINA_HOME/conf/" 2>/dev/null || true
    fi

    if [ -d "$INSTALL_DIR/webapps/ROOT" ]; then
        mkdir -p "$CATALINA_HOME/webapps"
        rm -rf "$CATALINA_HOME/webapps/ROOT"
        ln -s "$INSTALL_DIR/webapps/ROOT" "$CATALINA_HOME/webapps/ROOT" 2>/dev/null || \
        cp -r "$INSTALL_DIR/webapps/ROOT" "$CATALINA_HOME/webapps/"
    fi
    log_success "Tomcat 호스트 동기화 복원 완료."
}

# @description Docker 이미지 태그 복원
restore_docker_image() {
    if [ "$DEPLOY_MODE" != "docker" ]; then
        return 0
    fi
    if [ -z "${ROLLBACK_DOCKER_TAG:-}" ]; then
        return 0
    fi
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "docker 명령을 찾을 수 없어 이미지 태그 복원을 건너뜁니다."
        return 0
    fi

    local TARGET_IMG="${DOCKER_IMAGE:-${APP_NAME}:latest}"
    if docker image inspect "$ROLLBACK_DOCKER_TAG" >/dev/null 2>&1; then
        log_step "Docker 이미지 태그 복원 중 ($ROLLBACK_DOCKER_TAG -> $TARGET_IMG)..."
        if docker tag "$ROLLBACK_DOCKER_TAG" "$TARGET_IMG"; then
            log_success "Docker 이미지 태그 복원 완료: $TARGET_IMG"
        else
            log_error "Docker 이미지 태그 복원에 실패했습니다."
            return 1
        fi
    else
        log_warning "보존된 Docker 롤백 이미지($ROLLBACK_DOCKER_TAG)를 찾을 수 없습니다. 기존 로컬 이미지로 진행합니다."
    fi
}

# @description 복원된 서비스 시작 및 상태 확인
start_restored_service() {
    log_step "복원된 서비스 시작 중..."

    if [ "$IS_USER_MODE" -eq 1 ]; then
        if command -v systemctl >/dev/null 2>&1 && [ -f "$USER_HOME/.config/systemd/user/$APP_NAME.service" ]; then
            systemctl --user start "$APP_NAME"
        elif [ -x "$INSTALL_DIR/bin/start.sh" ]; then
            if [ "$DEPLOY_MODE" = "docker" ]; then
                "$INSTALL_DIR/bin/start.sh" -d
            else
                "$INSTALL_DIR/bin/start.sh"
            fi
        fi
    else
        if command -v systemctl >/dev/null 2>&1 && [ -f "/etc/systemd/system/$APP_NAME.service" ]; then
            systemctl start "$APP_NAME"
        elif [ -f "/etc/init.d/$APP_NAME" ]; then
            service "$APP_NAME" start
        elif [ -x "$INSTALL_DIR/bin/start.sh" ]; then
            if [ "$DEPLOY_MODE" = "docker" ]; then
                "$INSTALL_DIR/bin/start.sh" -d
            else
                "$INSTALL_DIR/bin/start.sh"
            fi
        fi
    fi

    log_success "서비스가 시작되었습니다."
}

# @description 사용한 스냅샷 정리 및 latest 심볼릭 링크 갱신
consume_applied_snapshot() {
    local ROLLBACK_BASE="$INSTALL_DIR/.rollback"

    if [ "$DEPLOY_MODE" = "docker" ] && [ -n "${ROLLBACK_DOCKER_TAG:-}" ] && command -v docker >/dev/null 2>&1; then
        docker rmi "$ROLLBACK_DOCKER_TAG" >/dev/null 2>&1 || true
    fi

    rm -rf "$SNAP_DIR"

    local NEXT_LATEST
    NEXT_LATEST=$(find "$ROLLBACK_BASE" -maxdepth 1 -mindepth 1 -type d -name "rev_*" -exec basename {} \; | sort -r | head -n 1)
    if [ -n "$NEXT_LATEST" ]; then
        ln -sfn "$NEXT_LATEST" "$ROLLBACK_BASE/latest"
    else
        rm -f "$ROLLBACK_BASE/latest"
    fi
}

# @description 메인 롤백 실행 함수
rollback_service() {
    resolve_install_dir

    if [ "$ACTION" = "list" ]; then
        list_snapshots
        exit $?
    fi

    log_header "서비스 롤백 시작 ($APP_NAME)" "⏪"
    log_info "대상 설치 경로: $INSTALL_DIR"

    resolve_target_snapshot
    source "$SNAP_DIR/meta.env"

    # 권한 모드 검증
    if [ -n "$EXPLICIT_USER_MODE" ] && [ "$EXPLICIT_USER_MODE" -ne "${IS_USER_MODE:-1}" ]; then
        log_warning "명시한 권한 옵션과 스냅샷의 권한 모드(IS_USER_MODE=$IS_USER_MODE)가 다릅니다. 스냅샷 기준으로 진행합니다."
    fi

    if [ "${IS_USER_MODE:-1}" -eq 0 ] && [ "$EUID" -ne 0 ]; then
        log_error "이전 배포가 시스템 모드(root)로 설치되어 root 권한(sudo)으로 롤백해야 합니다."
        echo -e "   👉 ${GREEN}sudo $0 --sudo${NC}"
        exit 1
    fi

    echo ""
    echo -e "   📌 ${BOLD}롤백 대상 스냅샷${NC} : ${CYAN}$REV_ID${NC}"
    echo -e "   🕒 ${BOLD}스냅샷 생성 시각${NC} : ${CYAN}$CREATED_AT${NC}"
    echo -e "   📦 ${BOLD}배포 방식 / 엔진${NC} : ${CYAN}$DEPLOY_MODE / $RUNTIME_ENGINE${NC}"
    echo -e "   👤 ${BOLD}권한 모드${NC}        : ${CYAN}$([ "${IS_USER_MODE:-1}" -eq 1 ] && echo "User Mode" || echo "System Mode (sudo)")${NC}"
    echo ""

    if [ "$AUTO_YES" -ne 1 ]; then
        read -p "   ❓ 위 스냅샷 상태로 롤백하시겠습니까? (y/N): " CONFIRM
        CONFIRM=${CONFIRM:-N}
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log_info "롤백이 취소되었습니다."
            exit 0
        fi
    fi

    # 1. 현재 서비스 중지
    stop_current_service

    # 2. 실패 대비 현재 상태 임시 백업 (원자성 확보)
    local TMP_BACKUP="$INSTALL_DIR/.rollback/.pre_rollback_tmp.tar.gz"
    log_step "롤백 안전을 위해 현재 상태 임시 백업 중..."
    tar --exclude='.rollback' --exclude='./.rollback' --exclude='run' --exclude='./run' --exclude='logs' --exclude='./logs' \
        -czf "$TMP_BACKUP" -C "$INSTALL_DIR" . 2>/dev/null || true

    # 3. 현재 운영 파일 정리 및 스냅샷 복원
    log_step "이전 애플리케이션 및 설정 파일 복원 중..."
    clean_current_app_files

    if ! tar -xzf "$SNAP_DIR/app_files.tar.gz" -C "$INSTALL_DIR"; then
        log_error "스냅샷 압축 해제 실패! 임시 백업으로 긴급 복구를 시도합니다."
        clean_current_app_files
        [ -f "$TMP_BACKUP" ] && tar -xzf "$TMP_BACKUP" -C "$INSTALL_DIR" 2>/dev/null || true
        rm -f "$TMP_BACKUP"
        exit 1
    fi

    if [ "${IS_USER_MODE:-1}" -eq 0 ]; then
        chown -R "$REAL_USER:$SERVICE_GROUP" "$INSTALL_DIR" 2>/dev/null || true
    fi

    # 4. Docker 이미지 / Tomcat 호스트 / 시스템 설정 복원
    if ! restore_docker_image; then
        log_error "Docker 이미지 복원 실패! 임시 백업으로 긴급 복구합니다."
        clean_current_app_files
        [ -f "$TMP_BACKUP" ] && tar -xzf "$TMP_BACKUP" -C "$INSTALL_DIR" 2>/dev/null || true
        rm -f "$TMP_BACKUP"
        exit 1
    fi
    restore_tomcat_host
    restore_system_configs

    # 5. 서비스 시작
    start_restored_service

    # 6. 임시 백업 및 사용한 스냅샷 정리
    rm -f "$TMP_BACKUP"
    consume_applied_snapshot

    log_header "롤백 완료" "🎉"
    echo -e "   ${GREEN}이전 배포 상태($REV_ID)로 성공적으로 복원되었습니다.${NC}"
}

# --- [Execution] ---
rollback_service
