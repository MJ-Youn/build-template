#!/usr/bin/env bash
# =============================================================================
# 빌드 및 배포 자동화 스크립트 (build_deploy.sh)
#
# 사용법: ./build_deploy.sh -Penv=<환경명>
# 예시:   ./build_deploy.sh -Penv=dev
#         ./build_deploy.sh -Penv=prod
#
# 실행 순서:
#   1. Git pull (현재 디렉토리가 Git 저장소인 경우)
#   2. Maven package 빌드 (-P<환경명>)
#   3. 빌드 결과물(ZIP) 압축 해제 후 bin/install_service.sh 실행
#
# @author 윤명준 (MJ Yune)
# @since  2026-03-19
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

# -----------------------------------------------------------------------------
# 스크립트 실행 위치를 기준으로 프로젝트 루트 디렉토리 설정
# (스크립트가 어느 위치에서 실행되든 동일하게 동작하도록 절대 경로 사용)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# -----------------------------------------------------------------------------
# 파라미터 파싱 (-Penv=<값> 형식)
# -----------------------------------------------------------------------------
ENV_VALUE=""

for ARG in "$@"; do
    case "${ARG}" in
        -Penv=*)
            ENV_VALUE="${ARG#-Penv=}"
            ;;
        *)
            echo -e "${RED}❌ 알 수 없는 옵션: ${ARG}${NC}"
            echo -e "${YELLOW}사용법: ./build_deploy.sh -Penv=<환경명>${NC}"
            echo -e "${YELLOW}예시:   ./build_deploy.sh -Penv=dev${NC}"
            exit 1
            ;;
    esac
done

# env 파라미터 필수 확인
if [ -z "${ENV_VALUE}" ]; then
    echo -e "${RED}❌ -Penv 파라미터가 필요합니다.${NC}"
    echo -e "${YELLOW}사용법: ./build_deploy.sh -Penv=<환경명>${NC}"
    echo -e "${YELLOW}예시:   ./build_deploy.sh -Penv=dev${NC}"
    exit 1
fi

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🚀 빌드 및 배포 자동화 시작 (환경: ${ENV_VALUE})${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# STEP 1. Git Pull
# 현재 디렉토리가 Git 저장소인 경우에만 실행
# -----------------------------------------------------------------------------
echo -e "${CYAN}[1/3] 📥 Git 최신 코드 Pull 시도 중...${NC}"

if [ -d "${SCRIPT_DIR}/.git" ]; then
    git -C "${SCRIPT_DIR}" pull
    echo -e "${GREEN}✅ Git pull 완료${NC}"
else
    echo -e "${YELLOW}⚠️  Git 저장소가 아니므로 Git pull을 건너뜁니다.${NC}"
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 2. Maven 빌드
# ./mvnw package -P<env> 실행
# -----------------------------------------------------------------------------
echo -e "${CYAN}[2/3] 🔨 Maven 빌드 시작 (./mvnw package -P${ENV_VALUE})${NC}"

MVNW="${SCRIPT_DIR}/mvnw"

if [ ! -f "${MVNW}" ]; then
    echo -e "${RED}❌ mvnw 파일을 찾을 수 없습니다: ${MVNW}${NC}"
    exit 1
fi

# mvnw 실행 권한 확인 및 부여
if [ ! -x "${MVNW}" ]; then
    echo -e "${YELLOW}⚠️  mvnw에 실행 권한이 없어 권한을 부여합니다.${NC}"
    chmod +x "${MVNW}"
fi

"${MVNW}" -f "${SCRIPT_DIR}/pom.xml" package "-P${ENV_VALUE}" -DskipTests
echo -e "${GREEN}✅ Maven 빌드 완료${NC}"
echo ""

# -----------------------------------------------------------------------------
# STEP 3. 빌드 결과물(ZIP) 압축 해제 및 install_service.sh 실행
# 빌드 결과물: ./target/dist/<appName>-<version>-<env>.dist.zip
# -----------------------------------------------------------------------------
echo -e "${CYAN}[3/3] 📦 빌드 결과물 압축 해제 및 설치 스크립트 실행${NC}"

DIST_DIR="${SCRIPT_DIR}/target/dist"

# build/dist 디렉토리 존재 여부 확인
if [ ! -d "${DIST_DIR}" ]; then
    echo -e "${RED}❌ 빌드 결과 디렉토리를 찾을 수 없습니다: ${DIST_DIR}${NC}"
    exit 1
fi

# <env>.dist.zip 패턴으로 결과물 파일 탐색 (가장 최근 파일 사용)
ZIP_FILE=$(find "${DIST_DIR}" -maxdepth 1 -name "*-${ENV_VALUE}.dist.zip" | sort | tail -n 1)

if [ -z "${ZIP_FILE}" ]; then
    echo -e "${RED}❌ 빌드 결과물 ZIP 파일을 찾을 수 없습니다.${NC}"
    echo -e "${RED}   탐색 위치: ${DIST_DIR}/*-${ENV_VALUE}.dist.zip${NC}"
    exit 1
fi

echo -e "   📄 발견된 ZIP 파일: ${ZIP_FILE}"

# 압축 해제 대상 디렉토리 설정 (ZIP 파일명에서 .zip 제거)
ZIP_BASENAME=$(basename "${ZIP_FILE}" .zip)
EXTRACT_DIR="${DIST_DIR}/${ZIP_BASENAME}"

# 기존 압축 해제 디렉토리가 있으면 삭제 후 재생성
if [ -d "${EXTRACT_DIR}" ]; then
    echo -e "${YELLOW}   ⚠️  기존 압축 해제 디렉토리를 삭제합니다: ${EXTRACT_DIR}${NC}"
    rm -rf "${EXTRACT_DIR}"
fi

mkdir -p "${EXTRACT_DIR}"
echo -e "   📂 압축 해제 위치: ${EXTRACT_DIR}"

# ZIP 압축 해제
unzip -q "${ZIP_FILE}" -d "${EXTRACT_DIR}"
echo -e "${GREEN}   ✅ 압축 해제 완료${NC}"

# bin/install_service.sh 존재 여부 확인
INSTALL_SCRIPT="${EXTRACT_DIR}/bin/install_service.sh"

if [ ! -f "${INSTALL_SCRIPT}" ]; then
    echo -e "${RED}❌ 설치 스크립트를 찾을 수 없습니다: ${INSTALL_SCRIPT}${NC}"
    exit 1
fi

# 실행 권한 부여 및 설치 스크립트 실행
chmod +x "${INSTALL_SCRIPT}"
echo -e "   🛠️  설치 스크립트 실행 중: ${INSTALL_SCRIPT}"
echo ""

"${INSTALL_SCRIPT}"

echo ""
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}✅ 빌드 및 배포 완료! (환경: ${ENV_VALUE})${NC}"
echo -e "${CYAN}======================================================${NC}"
