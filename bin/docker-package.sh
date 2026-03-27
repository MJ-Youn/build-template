#!/bin/bash
# ==============================================================================
# File: bin/docker-package.sh
# Description: Docker 이미지를 tar로 추출하고 배포용 Zip으로 패키징합니다.
#              Gradle 'dockerBuild' 태스크(Strategy 1)를 대체합니다.
#
# 사용법: ./bin/docker-package.sh [env]
#   env: 환경 (dev, prod 등, 기본값: dev)
#
# 전제 조건: ./bin/docker-build.sh 실행 완료 (레지스트리 없이 로컬 빌드)
#
# 실행 순서:
#   1. docker build.sh 실행 (로컬 이미지 빌드)
#   2. docker save → tar 파일 추출
#   3. tar + docker-dist 파일 → 최종 Zip 패키징
#
# 결과물: target/dist/{APP_NAME}-docker-{env}.zip
#
# @author 윤명준 (MJ Yune)
# @since  2026-03-27
# ==============================================================================

set -e

# --- [Script Init] ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# --- [파라미터 처리] ---
ENV_VALUE="${1:-dev}"

# --- [프로젝트 정보 파싱] ---
POM_FILE="$PROJECT_ROOT/pom.xml"
APP_NAME=$(grep -m1 '<artifactId>' "$POM_FILE" | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | tr -d '[:space:]')
APP_VERSION=$(grep -m1 '<version>' "$POM_FILE" | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d '[:space:]')

# Strategy 1: 레지스트리 없이 로컬 태그로 빌드
TAG_NAME="${APP_NAME}:latest"
TAR_NAME="${APP_NAME}.tar"

DOCKER_DIST_DIR="$PROJECT_ROOT/target/docker-dist"
DIST_DIR="$PROJECT_ROOT/target/dist"
DOCKER_DIST_ZIP="${APP_NAME}-docker-${ENV_VALUE}.zip"

echo "📦 === Docker 배포 패키지 생성 시작 (Strategy 1) ==="

# --- [Step 1] Docker 이미지 빌드 (레지스트리 없이) ---
echo "🔨 [1/3] Docker 이미지 빌드 중..."
"$SCRIPT_DIR/docker-build.sh" "$ENV_VALUE" "" "latest"

# --- [Step 2] Docker 이미지 추출 (docker save) ---
echo "💾 [2/3] Docker 이미지 추출 중 (docker save) → $DOCKER_DIST_DIR/$TAR_NAME"
docker save -o "$DOCKER_DIST_DIR/$TAR_NAME" "$TAG_NAME"

echo "   ✅ Docker 이미지 추출 완료"

# --- [Step 3] 최종 Zip 패키징 ---
mkdir -p "$DIST_DIR"
echo "🗜️ [3/3] 최종 배포용 Zip 생성 중: $DIST_DIR/$DOCKER_DIST_ZIP"

cd "$DOCKER_DIST_DIR"
zip -r "$DIST_DIR/$DOCKER_DIST_ZIP" .

echo ""
echo "✅ === Docker 배포 패키지 생성 완료 ==="
echo "   📦 결과물: $DIST_DIR/$DOCKER_DIST_ZIP"
echo ""
echo "💡 서버 배포 방법:"
echo "   scp $DIST_DIR/$DOCKER_DIST_ZIP user@server:/home/user/"
echo "   unzip $DOCKER_DIST_ZIP -d deploy && cd deploy"
echo "   sudo ./install_docker_service.sh"
