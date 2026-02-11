#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PID_FILE="$SCRIPT_DIR/application.pid"

# --- [Color & Style Definition] ---
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "   ℹ️  $1"; }
log_step() { echo -e "${BOLD}${CYAN}➡️  $1${NC}"; }
log_success() { echo -e "${BOLD}${GREEN}✅  $1${NC}"; }
log_warning() { echo -e "${BOLD}${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${BOLD}${RED}❌  $1${NC}"; }

log_step "애플리케이션 중지 프로세스 시작..."

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  log_info "PID 파일 확인됨: $PID"
  log_info "프로세스 종료 신호 전송 중..."
  kill "$PID"
  rm "$PID_FILE"
  log_success "애플리케이션이 안전하게 중지되었습니다."
else
  log_warning "PID 파일을 찾을 수 없습니다 ($PID_FILE)."
  log_info "프로세스 이름으로 강제 종료를 시도합니다..."
  # PID 파일이 없을 경우 pkill을 사용하여 종료 시도 (여러 인스턴스가 있을 경우 주의 필요)
  if pkill -f "build_test"; then
      log_success "실행 중인 프로세스를 찾아 종료했습니다."
  else
      log_warning "실행 중인 프로세스를 찾을 수 없습니다."
  fi
fi
