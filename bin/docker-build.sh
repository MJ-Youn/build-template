#!/bin/bash
# ==============================================================================
# File: bin/docker-build.sh
# Description: Docker 이미지를 로컬 데몬에 빌드합니다.
#              Gradle 'dockerBuildImage' 태스크(Strategy 2)를 대체합니다.
#
# 사용법: ./bin/docker-build.sh [env] [dockerRegistry] [dockerImageTag]
#   env           : 환경 (dev, prod 등, 기본값: dev)
#   dockerRegistry: Docker 레지스트리 주소 (비어있으면 로컬 태그 사용)
#   dockerImageTag: Docker 이미지 태그 (기본값: pom.xml의 version)
#
# 전제 조건: ./mvnw package -P${env} 빌드 완료 상태
#
# 실행 순서:
#   1. prepare-docker.sh 실행 (빌드 컨텍스트 구성)
#   2. docker build --platform linux/amd64 실행
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
DOCKER_REGISTRY="${2:-}"
DOCKER_TAG="${3:-}"

# --- [프로젝트 정보 파싱] ---
POM_FILE="$PROJECT_ROOT/pom.xml"
APP_NAME=$(grep -m1 '<artifactId>' "$POM_FILE" | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | tr -d '[:space:]')
APP_VERSION=$(grep -m1 '<version>' "$POM_FILE" | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d '[:space:]')

if [ -z "$DOCKER_TAG" ]; then
    DOCKER_TAG="$APP_VERSION"
fi

# --- [이미지 이름 결정] ---
if [ -n "$DOCKER_REGISTRY" ]; then
    DOCKER_REGISTRY="${DOCKER_REGISTRY%/}"
    FULL_IMAGE_NAME="${DOCKER_REGISTRY}/${APP_NAME}:${DOCKER_TAG}"
else
    FULL_IMAGE_NAME="${APP_NAME}:${DOCKER_TAG}"
fi

DOCKER_BUILD_DIR="$PROJECT_ROOT/target/docker-build"

# --- [Step 1] Docker 컨텍스트 준비 ---
echo "🐳 [1/2] Docker 컨텍스트 준비 중..."
"$SCRIPT_DIR/prepare-docker.sh" "$ENV_VALUE" "$DOCKER_REGISTRY" "$DOCKER_TAG"

# --- [Step 2] Docker 이미지 빌드 ---
echo ""
echo "🔨 [2/2] === Docker 이미지 빌드 시작 ==="
echo "   🔖 이미지 태그: $FULL_IMAGE_NAME"
echo "   📂 빌드 컨텍스트: $DOCKER_BUILD_DIR"

# 리눅스 배포를 위해 amd64 플랫폼 명시 (필요시 수정 가능)
docker build --platform linux/amd64 -t "$FULL_IMAGE_NAME" "$DOCKER_BUILD_DIR"

echo ""
echo "✨ === Docker 이미지 빌드 성공: $FULL_IMAGE_NAME ==="
echo "   📦 배포 파일 경로: $PROJECT_ROOT/target/docker-dist"

if [ -z "$DOCKER_REGISTRY" ]; then
    echo "   💡 실행 방법 (Strategy 2): cd target/docker-dist && docker compose up -d"
fi
