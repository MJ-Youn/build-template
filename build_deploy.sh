#!/usr/bin/env bash
# =============================================================================
# 빌드 및 배포 자동화 스크립트 (build_deploy.sh)
#
# 사용법: ./build_deploy.sh -Penv=<환경명>
#         또는 ./build_deploy.sh <환경명> (예: ./build_deploy.sh dev)
#
# 실행 순서:
#   1. Git pull (현재 디렉토리가 Git 저장소인 경우)
#   2. 빌드 도구 감지 (Gradle / Maven) 및 플러그인 원스탑 배포 실행
#      - Gradle: ./gradlew clean deployService -Penv=<환경명>
#      - Maven:  ./mvnw clean distribution:deploy -Denv=<환경명>
#   3. 플러그인 미적용 프로젝트에 대한 Fallback (ZIP 탐색 및 수동 설치)
#
# @author 윤명준 (MJ Yun)
# @since  2026-03-19 (Updated: 2026-09-07)
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# 색상 출력 정의
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# -----------------------------------------------------------------------------
# 파라미터 파싱 (-Penv=..., -Denv=..., --env=..., 또는 첫 번째 인자)
# -----------------------------------------------------------------------------
ENV_VALUE=""

for ARG in "$@"; do
    case "${ARG}" in
        -Penv=*)
            ENV_VALUE="${ARG#-Penv=}"
            ;;
        -Denv=*)
            ENV_VALUE="${ARG#-Denv=}"
            ;;
        --env=*)
            ENV_VALUE="${ARG#--env=}"
            ;;
        dev|prod|local|test|stage|qa)
            ENV_VALUE="${ARG}"
            ;;
    esac
done

# 위치 인자로 지정된 경우 지원 (예: ./build_deploy.sh dev)
if [ -z "${ENV_VALUE}" ] && [ -n "$1" ] && [[ "$1" != -* ]]; then
    ENV_VALUE="$1"
fi

if [ -z "${ENV_VALUE}" ]; then
    echo -e "${RED}❌ 환경 파라미터가 필요합니다.${NC}"
    echo -e "${YELLOW}사용법: ./build_deploy.sh -Penv=<환경명> 또는 ./build_deploy.sh <환경명>${NC}"
    echo -e "${YELLOW}예시:   ./build_deploy.sh -Penv=dev  (또는 ./build_deploy.sh dev)${NC}"
    exit 1
fi

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🚀 빌드 및 배포 자동화 시작 (환경: ${ENV_VALUE})${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# STEP 1. Git Pull
# -----------------------------------------------------------------------------
echo -e "${CYAN}[1/2] 📥 Git 최신 코드 Pull 시도 중...${NC}"

if [ -d "${SCRIPT_DIR}/.git" ]; then
    git -C "${SCRIPT_DIR}" pull
    echo -e "${GREEN}✅ Git pull 완료${NC}"
else
    echo -e "${YELLOW}⚠️  Git 저장소가 아니므로 Git pull을 건너뜁니다.${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# STEP 2. 빌드 도구 감지 및 배포 실행
# -----------------------------------------------------------------------------
echo -e "${CYAN}[2/2] 🔨 배포 빌드 및 서비스 설치 시작...${NC}"

# A. Gradle 프로젝트인 경우
if [ -f "${SCRIPT_DIR}/gradlew" ] || [ -f "${SCRIPT_DIR}/build.gradle" ] || [ -f "${SCRIPT_DIR}/build.gradle.kts" ]; then
    GRADLEW="${SCRIPT_DIR}/gradlew"
    if [ ! -f "${GRADLEW}" ]; then
        GRADLEW="gradle"
    elif [ ! -x "${GRADLEW}" ]; then
        chmod +x "${GRADLEW}"
    fi

    echo -e "${GREEN}📦 Gradle 배포 패키지 빌드 시작 (clean package)...${NC}"
    "${GRADLEW}" -p "${SCRIPT_DIR}" clean package "-Penv=${ENV_VALUE}"

    # ZIP 탐색 (build/distributions 우선, build/dist 차선)
    ZIP_FILE=$(find "${SCRIPT_DIR}/build/distributions" "${SCRIPT_DIR}/build/dist" -maxdepth 2 -name "*.zip" 2>/dev/null | sort | tail -n 1)
    if [ -z "${ZIP_FILE}" ]; then
        echo -e "${RED}❌ 빌드 결과물 ZIP 파일을 찾을 수 없습니다.${NC}"
        exit 1
    fi

    EXTRACT_DIR="${SCRIPT_DIR}/build/distributions/unpacked"
    rm -rf "${EXTRACT_DIR}"
    mkdir -p "${EXTRACT_DIR}"
    echo -e "${CYAN}📂 배포 패키지 압축 해제 중: $(basename "${ZIP_FILE}")${NC}"
    unzip -q "${ZIP_FILE}" -d "${EXTRACT_DIR}"

    INSTALL_SCRIPT=$(find "${EXTRACT_DIR}" -name "install_service.sh" 2>/dev/null | head -n 1)
    if [ -f "${INSTALL_SCRIPT}" ]; then
        chmod +x "${INSTALL_SCRIPT}"
        echo -e "${GREEN}🚀 서비스 설치 및 실행을 시작합니다...${NC}"
        if [ "$EUID" -eq 0 ]; then
            "${INSTALL_SCRIPT}"
        else
            sudo "${INSTALL_SCRIPT}"
        fi
    else
        echo -e "${RED}❌ install_service.sh 를 찾을 수 없습니다.${NC}"
        exit 1
    fi

# B. Maven 프로젝트인 경우
elif [ -f "${SCRIPT_DIR}/mvnw" ] || [ -f "${SCRIPT_DIR}/pom.xml" ]; then
    MVNW="${SCRIPT_DIR}/mvnw"
    if [ ! -f "${MVNW}" ]; then
        MVNW="mvn"
    elif [ ! -x "${MVNW}" ]; then
        chmod +x "${MVNW}"
    fi

    echo -e "${GREEN}📦 Maven 배포 패키지 빌드 시작 (clean package)...${NC}"
    "${MVNW}" -f "${SCRIPT_DIR}/pom.xml" clean package "-Denv=${ENV_VALUE}"

    # ZIP 탐색 (target 우선)
    ZIP_FILE=$(find "${SCRIPT_DIR}/target" -maxdepth 2 -name "*.zip" 2>/dev/null | sort | tail -n 1)
    if [ -z "${ZIP_FILE}" ]; then
        echo -e "${RED}❌ 빌드 결과물 ZIP 파일을 찾을 수 없습니다.${NC}"
        exit 1
    fi

    EXTRACT_DIR="${SCRIPT_DIR}/target/unpacked"
    rm -rf "${EXTRACT_DIR}"
    mkdir -p "${EXTRACT_DIR}"
    echo -e "${CYAN}📂 배포 패키지 압축 해제 중: $(basename "${ZIP_FILE}")${NC}"
    unzip -q "${ZIP_FILE}" -d "${EXTRACT_DIR}"

    INSTALL_SCRIPT=$(find "${EXTRACT_DIR}" -name "install_service.sh" 2>/dev/null | head -n 1)
    if [ -f "${INSTALL_SCRIPT}" ]; then
        chmod +x "${INSTALL_SCRIPT}"
        echo -e "${GREEN}🚀 서비스 설치 및 실행을 시작합니다...${NC}"
        if [ "$EUID" -eq 0 ]; then
            "${INSTALL_SCRIPT}"
        else
            sudo "${INSTALL_SCRIPT}"
        fi
    else
        echo -e "${RED}❌ install_service.sh 를 찾을 수 없습니다.${NC}"
        exit 1
    fi

else
    echo -e "${RED}❌ Gradle(gradlew) 또는 Maven(pom.xml) 프로젝트를 찾을 수 없습니다.${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}✅ 빌드 및 배포 완료! (환경: ${ENV_VALUE})${NC}"
echo -e "${CYAN}======================================================${NC}"
