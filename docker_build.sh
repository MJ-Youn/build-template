#!/bin/bash

# 프로젝트 루트 찾기
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

echo "=== Docker 이미지 빌드 시작 ==="

# 환경 설정 (기본값: prod)
TARGET_ENV="${1:-prod}"
echo "타겟 환경: $TARGET_ENV"

# 1. Gradle 패키지 빌드
echo "1. Gradle 배포 패키지 빌드 중..."
./gradlew clean package -Penv="$TARGET_ENV"

if [ $? -ne 0 ]; then
    echo "오류: Gradle 빌드 실패"
    exit 1
fi

# 2. Docker 빌드 컨텍스트 준비
DOCKER_CONTEXT="build/docker"
echo "2. 빌드 컨텍스트 준비 중 ($DOCKER_CONTEXT)..."

# 기존 컨텍스트 정리
rm -rf "$DOCKER_CONTEXT"
mkdir -p "$DOCKER_CONTEXT"

# 배포 패키지 압축 해제
DIST_ZIP=$(find build/dist -name "*-$TARGET_ENV.dist.zip" | head -n 1)
if [ -z "$DIST_ZIP" ]; then
    echo "오류: 배포 zip 파일을 찾을 수 없습니다."
    exit 1
fi

echo "배포 파일 압축 해제: $DIST_ZIP"
unzip -q "$DIST_ZIP" -d "$DOCKER_CONTEXT"

# Dockerfile 복사
echo "Dockerfile 복사..."
cp Dockerfile "$DOCKER_CONTEXT/"

# 3. Docker 이미지 빌드
IMAGE_NAME="build_test"
TAG="latest"

echo "3. Docker 이미지 빌드 중 ($IMAGE_NAME:$TAG)..."
docker build -t "$IMAGE_NAME:$TAG" "$DOCKER_CONTEXT"

if [ $? -eq 0 ]; then
    echo "=== Docker 빌드 성공: $IMAGE_NAME:$TAG ==="
    echo "실행 방법: docker-compose up 또는 docker run ..."
else
    echo "오류: Docker 이미지 빌드 실패"
    exit 1
fi
