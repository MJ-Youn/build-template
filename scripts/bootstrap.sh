#!/bin/bash
# ==============================================================================
# File: bootstrap.sh
# Description: 유틸리티 로드 및 폴백 정의를 위한 부트스트랩 스크립트
# Author: Jules (Code Health Agent)
# Since: 2026-02-11
# ==============================================================================

BOOTSTRAP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# utils.sh 로드 시도
UTILS_PATH="$BOOTSTRAP_DIR/utils.sh"
if [ -f "$UTILS_PATH" ]; then
    source "$UTILS_PATH"
else
    # utils.sh를 찾을 수 없는 경우 기본 함수 정의 (Fallback)
    echo "Warning: utils.sh not found at $UTILS_PATH. Using basic logging."

    # ANSI color codes
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color

    log_header() {
        local message="$1"
        local icon="${2:-🚀}"
        echo -e "\n${BOLD}${BLUE}=== $icon $message ===${NC}"
    }
    log_step() { echo -e "\n${BOLD}${CYAN}➡️  $1${NC}"; }
    log_info() { echo -e "   ℹ️  $1"; }
    log_success() { echo -e "${BOLD}${GREEN}✅  $1${NC}"; }
    log_warning() { echo -e "${BOLD}${YELLOW}⚠️  $1${NC}"; }
    log_error() { echo -e "${BOLD}${RED}❌  $1${NC}"; }

    # 기본 유틸리티 함수 폴백
    add_path_to_profile() { return 1; }
    is_safe_path() { return 0; }
fi
