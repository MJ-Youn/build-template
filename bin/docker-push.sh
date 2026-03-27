#!/bin/bash
# ==============================================================================
# File: bin/docker-push.sh
# Description: Docker 이미지를 빌드하고 레지스트리에 Push합니다.
#              Gradle 'dockerPushImage' 태스크(Strategy 3)를 대체합니다.
#
# 사용법: ./bin/docker-push.sh <dockerRegistry> [env] [dockerImageTag]
#   dockerRegistry: (필수) Docker 레지스트리 주소 (예: my-registry.com/repo)
#   env           : 환경 (dev, prod 등, 기본값: dev)
#   dockerImageTag: Docker 이미지 태그 (기본값: pom.xml의 version)
#
# 전제 조건: ./mvnw package -P${env} 빌드 완료 상태
#
# @author 윤명준 (MJ Yune)
# @since  2026-03-27
# ==============================================================================

set -e

# --- [Script Init] ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- [파라미터 처리] ---
DOCKER_REGISTRY="${1:-}"
ENV_VALUE="${2:-dev}"
DOCKER_TAG="${3:-}"

# Registry 필수 확인
if [ -z "$DOCKER_REGISTRY" ]; then
    echo "❌ dockerRegistry 파라미터가 필요합니다."
    echo "   사용법: ./bin/docker-push.sh <dockerRegistry> [env] [dockerImageTag]"
    echo "   예시:   ./bin/docker-push.sh my-registry.com/repo prod"
    exit 1
fi

# --- [프로젝트 정보 파싱] ---
POM_FILE="$PROJECT_ROOT/pom.xml"
APP_NAME=$(grep -m1 '<artifactId>' "$POM_FILE" | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | tr -d '[:space:]')
APP_VERSION=$(grep -m1 '<version>' "$POM_FILE" | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d '[:space:]')

if [ -z "$DOCKER_TAG" ]; then
    DOCKER_TAG="$APP_VERSION"
fi

DOCKER_REGISTRY="${DOCKER_REGISTRY%/}"
FULL_IMAGE_NAME="${DOCKER_REGISTRY}/${APP_NAME}:${DOCKER_TAG}"
DOCKER_DIST_DIR="$PROJECT_ROOT/target/docker-dist"

# --- [Step 1] Docker 이미지 빌드 ---
echo "☁️ === Docker 이미지 Push 시작 ==="
echo "🔨 [1/2] Docker 이미지 빌드 중..."
"$SCRIPT_DIR/docker-build.sh" "$ENV_VALUE" "$DOCKER_REGISTRY" "$DOCKER_TAG"

# --- [Step 2] Docker Push ---
echo ""
echo "📤 [2/2] 이미지 Push 중: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

# --- [완료 안내 메시지] ---
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ✅  Docker 이미지 Push 완료                                     ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  🖼️   이미지  : ${FULL_IMAGE_NAME}"
echo "║  📂  배포파일  : ${DOCKER_DIST_DIR}"
echo "║  📄  가이드   : ${DOCKER_DIST_DIR}/DEPLOY-GUIDE.md"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  🚀 서버 배포 순서 (아래 명령어를 순서대로 실행하세요)             ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║"
echo "║  [1] 배포 파일 서버 전송"
echo "║      scp -r ${DOCKER_DIST_DIR}/ user@your-server:/home/user/"
echo "║"
echo "║  [2] Registry 로그인 (Private Registry인 경우)"
echo "║      docker login ${DOCKER_REGISTRY}"
echo "║"
echo "║  [3] 이미지 Pull"
echo "║      docker pull ${FULL_IMAGE_NAME}"
echo "║"
echo "║  [4-a] 자동 설치 (Systemd 서비스 등록 포함 — 권장)"
echo "║      cd /home/user/docker-dist"
echo "║      sudo ./install_docker_service.sh"
echo "║"
echo "║  [4-b] 수동 실행 (docker compose 직접)"
echo "║      cd /home/user/docker-dist"
echo "║      echo 'DOCKER_IMAGE=${FULL_IMAGE_NAME}' >> .env"
echo "║      docker compose up -d"
echo "║"
echo "║  💡 상세 가이드: ${DOCKER_DIST_DIR}/DEPLOY-GUIDE.md"
echo "║"
echo "╚══════════════════════════════════════════════════════════════════╝"
