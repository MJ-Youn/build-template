#!/usr/bin/env bash
# =============================================================================
# 빌드 및 배포 자동화 스크립트 (build_deploy.sh)
#
# 사용법: ./build_deploy.sh -Penv=<환경명> [-Ptype=jar|tomcat] [-Pport=포트]
#         또는 ./build_deploy.sh <환경명> [옵션...] (예: ./build_deploy.sh dev -Ptype=tomcat)
#         도움말: ./build_deploy.sh --help
#
# 실행 순서:
#   1. Git pull (현재 디렉토리가 Git 저장소인 경우, --no-pull 로 생략 가능)
#   2. 빌드 도구 감지 (Gradle / Maven) 및 플러그인 패키징 실행
#      - Gradle: ./gradlew clean package -Penv=<환경> -Ptype=<유형> -Pport=<포트> ...
#      - Maven:  ./mvnw clean package -Denv=<환경> -Dtype=<유형> -DhttpPort=<포트> ...
#   3. 배포 패키지 ZIP 압축 해제 및 install_service.sh 실행 (서비스 등록 및 구동)
#
# @author 윤명준 (MJ Yun)
# @since  2026-03-19 (Updated: 2026-09-15)
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# 색상 출력 정의
# -----------------------------------------------------------------------------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# -----------------------------------------------------------------------------
# 도움말 출력 함수
# -----------------------------------------------------------------------------
show_help() {
    cat << EOF

${BOLD}================================================================================${NC}
🚀 ${CYAN}${BOLD}[build_deploy.sh] 빌드 및 원스탑 배포 자동화 스크립트${NC}
${BOLD}================================================================================${NC}

${YELLOW}${BOLD}사용법:${NC}
  ./build_deploy.sh <환경명> [옵션...]
  ./build_deploy.sh -Penv=<환경명> [옵션...]

${YELLOW}${BOLD}주요 배포 환경 (필수):${NC}
  dev | prod | local | test | stage | qa

${YELLOW}${BOLD}주요 지원 파라미터 (Gradle -P / Maven -D 호환):${NC}
  ${GREEN}-Penv=<환경>${NC}           : 활성화할 배포 환경 프로파일 (기본값: 위치인자)
  ${GREEN}-Ptype=jar|tomcat${NC}     : 배포 유형 오버라이드 (기본값: jar)
                           - jar    : Spring Boot Executable JAR 기반 배포
                           - tomcat : Standalone Apache Tomcat 11 기반 배포
  ${GREEN}-Pport=<포트>${NC}          : HTTP 서비스 포트 오버라이드 (기본값: 8080)
  ${GREEN}-PtomcatVersion=<버전>${NC} : Tomcat 버전 지정 (기본값: 11.0.15)
  ${GREEN}-PappName=<앱이름>${NC}     : 배포 서비스명 오버라이드 (기본값: 프로젝트명)
  ${GREEN}--no-pull${NC}             : 배포 전 Git pull 건너뛰기
  ${GREEN}-h, --help${NC}            : 이 도움말 출력

${YELLOW}${BOLD}실행 예시:${NC}
  ${CYAN}# 1. 개발 환경 표준 JAR 배포${NC}
  ./build_deploy.sh dev

  ${CYAN}# 2. 운영 환경 외장 Tomcat 배포 (포트 8080)${NC}
  ./build_deploy.sh prod -Ptype=tomcat

  ${CYAN}# 3. 개발 환경 포트 8443 변경 배포${NC}
  ./build_deploy.sh dev -Pport=8443

  ${CYAN}# 4. Git pull 없이 즉시 톰캣 8081 배포${NC}
  ./build_deploy.sh prod -Ptype=tomcat -Pport=8081 --no-pull

${BOLD}================================================================================${NC}
EOF
}

# -----------------------------------------------------------------------------
# 파라미터 파싱
# -----------------------------------------------------------------------------
ENV_VALUE=""
TYPE_VALUE=""
PORT_VALUE=""
SKIP_GIT_PULL=false

GRADLE_EXTRA_ARGS=()
MAVEN_EXTRA_ARGS=()

for ARG in "$@"; do
    case "${ARG}" in
        -h|--help|help)
            show_help
            exit 0
            ;;
        --no-pull)
            SKIP_GIT_PULL=true
            ;;
        -Penv=*)
            ENV_VALUE="${ARG#-Penv=}"
            ;;
        -Denv=*)
            ENV_VALUE="${ARG#-Denv=}"
            ;;
        --env=*)
            ENV_VALUE="${ARG#--env=}"
            ;;
        -Ptype=*|-Dtype=*)
            TYPE_VALUE="${ARG#*=}"
            GRADLE_EXTRA_ARGS+=("-Ptype=${TYPE_VALUE}")
            MAVEN_EXTRA_ARGS+=("-Dtype=${TYPE_VALUE}")
            ;;
        -PpackageType=*|-DpackageType=*)
            TYPE_VALUE="${ARG#*=}"
            GRADLE_EXTRA_ARGS+=("-PpackageType=${TYPE_VALUE}")
            MAVEN_EXTRA_ARGS+=("-DpackageType=${TYPE_VALUE}")
            ;;
        -Pport=*|-Dport=*)
            PORT_VALUE="${ARG#*=}"
            GRADLE_EXTRA_ARGS+=("-Pport=${PORT_VALUE}")
            MAVEN_EXTRA_ARGS+=("-DhttpPort=${PORT_VALUE}")
            ;;
        -PhttpPort=*|-DhttpPort=*)
            PORT_VALUE="${ARG#*=}"
            GRADLE_EXTRA_ARGS+=("-PhttpPort=${PORT_VALUE}")
            MAVEN_EXTRA_ARGS+=("-DhttpPort=${PORT_VALUE}")
            ;;
        dev|prod|local|test|stage|qa)
            if [ -z "${ENV_VALUE}" ]; then
                ENV_VALUE="${ARG}"
            fi
            ;;
        -P*)
            GRADLE_EXTRA_ARGS+=("${ARG}")
            # Maven 호환을 위해 -P를 -D로 변환하여 전달
            MAVEN_EXTRA_ARGS+=("-D${ARG#-P}")
            ;;
        -D*)
            MAVEN_EXTRA_ARGS+=("${ARG}")
            # Gradle 호환을 위해 -D를 -P로 변환하여 전달
            GRADLE_EXTRA_ARGS+=("-P${ARG#-D}")
            ;;
    esac
done

# 위치 인자로 지정된 경우 지원 (예: ./build_deploy.sh dev)
if [ -z "${ENV_VALUE}" ] && [ -n "$1" ] && [[ "$1" != -* ]]; then
    ENV_VALUE="$1"
fi

if [ -z "${ENV_VALUE}" ]; then
    echo -e "${RED}❌ 환경 파라미터가 필요합니다.${NC}"
    echo -e "${YELLOW}사용법: ./build_deploy.sh <환경명> [옵션...]  또는  ./build_deploy.sh --help${NC}"
    echo -e "${YELLOW}예시:   ./build_deploy.sh dev -Ptype=tomcat -Pport=8443${NC}"
    exit 1
fi

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🚀 빌드 및 배포 자동화 시작 (build_deploy.sh)${NC}"
echo -e "   - ${BOLD}배포 환경${NC}    : ${GREEN}${ENV_VALUE}${NC}"
if [ -n "${TYPE_VALUE}" ]; then
    TYPE_UPPER=$(echo "${TYPE_VALUE}" | tr '[:lower:]' '[:upper:]')
    echo -e "   - ${BOLD}배포 유형${NC}    : ${MAGENTA}${TYPE_UPPER}${NC}"
fi
if [ -n "${PORT_VALUE}" ]; then
    echo -e "   - ${BOLD}서비스 포트${NC}  : ${YELLOW}${PORT_VALUE}${NC}"
fi
echo -e "${CYAN}======================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# STEP 1. Git Pull
# -----------------------------------------------------------------------------
echo -e "${CYAN}[1/2] 📥 Git 최신 코드 Pull 시도 중...${NC}"

if [ "${SKIP_GIT_PULL}" = true ]; then
    echo -e "${YELLOW}⚠️  --no-pull 옵션에 따라 Git pull을 건너뜁니다.${NC}"
elif [ -d "${SCRIPT_DIR}/.git" ]; then
    git -C "${SCRIPT_DIR}" pull
    echo -e "${GREEN}✅ Git pull 완료${NC}"
else
    echo -e "${YELLOW}⚠️  Git 저장소가 아니므로 Git pull을 건너뜁니다.${NC}"
fi
echo ""

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
    echo -e "${CYAN}   실행 명령: ${GRADLEW} clean package -Penv=${ENV_VALUE} ${GRADLE_EXTRA_ARGS[*]}${NC}"
    "${GRADLEW}" -p "${SCRIPT_DIR}" clean package "-Penv=${ENV_VALUE}" "${GRADLE_EXTRA_ARGS[@]}"

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
    echo -e "${CYAN}   실행 명령: ${MVNW} clean package -Denv=${ENV_VALUE} ${MAVEN_EXTRA_ARGS[*]}${NC}"
    "${MVNW}" -f "${SCRIPT_DIR}/pom.xml" clean package "-Denv=${ENV_VALUE}" "${MAVEN_EXTRA_ARGS[@]}"

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
