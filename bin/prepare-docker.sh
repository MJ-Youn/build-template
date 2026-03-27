#!/bin/bash
# ==============================================================================
# File: bin/prepare-docker.sh
# Description: Docker 빌드 컨텍스트 및 배포 파일 준비 스크립트
#              Gradle 'prepareDockerContext' 태스크를 대체합니다.
#
# 사용법: ./bin/prepare-docker.sh [env] [dockerRegistry] [dockerImageTag]
#   env           : 환경 (dev, prod 등, 기본값: dev)
#   dockerRegistry: Docker 레지스트리 주소 (비어있으면 로컬 태그 사용)
#   dockerImageTag: Docker 이미지 태그 (기본값: pom.xml의 version)
#
# 결과:
#   target/docker-build/  : docker build 컨텍스트 (Dockerfile + libs + config + bin)
#   target/docker-dist/   : 서버 배포에 필요한 파일 (docker-compose, scripts, config, DEPLOY-GUIDE.md)
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

if [ ! -f "$POM_FILE" ]; then
    echo "❌ pom.xml을 찾을 수 없습니다: $POM_FILE"
    exit 1
fi

# pom.xml에서 artifactId, version 추출
APP_NAME=$(grep -m1 '<artifactId>' "$POM_FILE" | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | tr -d '[:space:]')
APP_VERSION=$(grep -m1 '<version>' "$POM_FILE" | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | tr -d '[:space:]')

if [ -z "$DOCKER_TAG" ]; then
    DOCKER_TAG="$APP_VERSION"
fi

# --- [이미지 이름 결정] ---
if [ -n "$DOCKER_REGISTRY" ]; then
    # 슬래시 후행 제거 후 조합
    DOCKER_REGISTRY="${DOCKER_REGISTRY%/}"
    FULL_IMAGE_NAME="${DOCKER_REGISTRY}/${APP_NAME}:${DOCKER_TAG}"
else
    FULL_IMAGE_NAME="${APP_NAME}:${DOCKER_TAG}"
fi

# --- [경로 설정] ---
TARGET_DIR="$PROJECT_ROOT/target"
DIST_DIR="$TARGET_DIR/dist"
DIST_ZIP_NAME="${APP_NAME}-${APP_VERSION}-${ENV_VALUE}.dist.zip"
DIST_ZIP_FILE="$DIST_DIR/$DIST_ZIP_NAME"
DOCKER_BUILD_DIR="$TARGET_DIR/docker-build"
DOCKER_DIST_DIR="$TARGET_DIR/docker-dist"

echo "🐳 === Docker 빌드 컨텍스트 준비 시작 ==="
echo "   APP_NAME   : $APP_NAME"
echo "   VERSION    : $APP_VERSION"
echo "   ENV        : $ENV_VALUE"
echo "   IMAGE      : $FULL_IMAGE_NAME"

# --- [사전 확인] ---
if [ ! -f "$DIST_ZIP_FILE" ]; then
    echo "❌ 배포 ZIP 파일을 찾을 수 없습니다: $DIST_ZIP_FILE"
    echo "   먼저 './mvnw package -P${ENV_VALUE}' 를 실행하세요."
    exit 1
fi

DOCKERFILE="$PROJECT_ROOT/docker/Dockerfile"
if [ ! -f "$DOCKERFILE" ]; then
    echo "❌ Dockerfile을 찾을 수 없습니다: $DOCKERFILE"
    exit 1
fi

# --- [초기화] ---
rm -rf "$DOCKER_BUILD_DIR" "$DOCKER_DIST_DIR"
mkdir -p "$DOCKER_BUILD_DIR" "$DOCKER_DIST_DIR"

# --- [Docker Build 컨텍스트 구성] ---
echo "📂 Docker 빌드 컨텍스트 구성 중... ($DOCKER_BUILD_DIR)"
unzip -q "$DIST_ZIP_FILE" -d "$DOCKER_BUILD_DIR"
cp "$DOCKERFILE" "$DOCKER_BUILD_DIR/"

# --- [Docker Dist 파일 구성] ---
echo "📂 Docker 배포 파일 구성 중... ($DOCKER_DIST_DIR)"

# 1. 환경별 docker-compose.yml 복사
ENV_COMPOSE="$PROJECT_ROOT/docker/${ENV_VALUE}/docker-compose-${ENV_VALUE}.yml"
BASE_COMPOSE="$PROJECT_ROOT/docker/docker-compose.yml"

if [ -f "$ENV_COMPOSE" ]; then
    COMPOSE_SRC="$ENV_COMPOSE"
elif [ -f "$BASE_COMPOSE" ]; then
    COMPOSE_SRC="$BASE_COMPOSE"
else
    echo "❌ docker-compose.yml 파일을 찾을 수 없습니다."
    echo "   확인 위치: $ENV_COMPOSE, $BASE_COMPOSE"
    exit 1
fi
echo "   📄 사용된 docker-compose: $COMPOSE_SRC"
# @appName@ 토큰 치환 후 복사
sed "s/@appName@/$APP_NAME/g" "$COMPOSE_SRC" > "$DOCKER_DIST_DIR/docker-compose.yml"

# 2. 스크립트 복사 (install_docker_service.sh, utils.sh)
for SRC_FILE in "docker/install_docker_service.sh" "scripts/utils.sh"; do
    FULL_SRC="$PROJECT_ROOT/$SRC_FILE"
    if [ -f "$FULL_SRC" ]; then
        sed "s/@appName@/$APP_NAME/g" "$FULL_SRC" > "$DOCKER_DIST_DIR/$(basename "$FULL_SRC")"
        chmod +x "$DOCKER_DIST_DIR/$(basename "$FULL_SRC")"
    fi
done

# 3. config 폴더 복사 (Host Mount용)
CONFIG_DIR="$DOCKER_BUILD_DIR/config"
if [ -d "$CONFIG_DIR" ]; then
    cp -r "$CONFIG_DIR" "$DOCKER_DIST_DIR/config"
    echo "   📂 config 폴더 복사 완료 (Host Mount용)"
fi

# 4. cron 폴더 복사
CRON_DIR="$PROJECT_ROOT/scripts/cron"
if [ -d "$CRON_DIR" ]; then
    cp -r "$CRON_DIR" "$DOCKER_DIST_DIR/cron"
fi

# 5. .app-env.properties 복사
ENV_PROPS="$PROJECT_ROOT/scripts/${ENV_VALUE}/.app-env-${ENV_VALUE}.properties"
BASE_PROPS="$PROJECT_ROOT/scripts/.app-env.properties"
if [ -f "$ENV_PROPS" ]; then
    cp "$ENV_PROPS" "$DOCKER_DIST_DIR/.app-env.properties"
elif [ -f "$BASE_PROPS" ]; then
    cp "$BASE_PROPS" "$DOCKER_DIST_DIR/.app-env.properties"
fi

# --- [DEPLOY-GUIDE.md 생성] ---
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
cat > "$DOCKER_DIST_DIR/DEPLOY-GUIDE.md" << EOF
# 🐳 ${APP_NAME} — Docker 배포 가이드 (Strategy 3: Registry)

> **이 파일은 \`./mvnw package -P${ENV_VALUE} && ./bin/docker-push.sh\` 빌드 시 자동 생성되었습니다.**
> 서버 담당자는 이 파일의 안내에 따라 서비스를 배포·실행하세요.

- **빌드 환경**: \`${ENV_VALUE}\`
- **이미지**: \`${FULL_IMAGE_NAME}\`
- **생성 일시**: ${TIMESTAMP}

---

## 📋 이 폴더(docker-dist)에 포함된 파일

| 파일 | 설명 |
|------|------|
| \`docker-compose.yml\` | 컨테이너 실행 설정 (\`.env\` 파일과 함께 사용) |
| \`install_docker_service.sh\` | 서비스 자동 설치 스크립트 (Systemd/SysVinit 등록 포함) |
| \`utils.sh\` | 공통 유틸리티 스크립트 |
| \`config/\` | 애플리케이션 설정 파일 (Host Mount용 — 수정 가능) |
| \`.app-env.properties\` | 로그 경로 등 배포 환경 기본값 |
| \`DEPLOY-GUIDE.md\` | 이 파일 |

---

## 🚀 배포 순서

### 1. 이 폴더를 서버로 전송

\`\`\`bash
scp -r target/docker-dist/ user@your-server:/home/user/
\`\`\`

### 2. 서버 접속 후 Docker 로그인 (Private Registry인 경우)

\`\`\`bash
docker login ${DOCKER_REGISTRY:-your-registry}
\`\`\`

### 3. Docker 이미지 Pull

\`\`\`bash
docker pull ${FULL_IMAGE_NAME}
\`\`\`

### 4-a. 자동 설치 (서비스 등록 포함, 권장)

\`\`\`bash
cd /home/user/docker-dist
sudo ./install_docker_service.sh
\`\`\`

### 4-b. 수동 실행 (docker compose 직접)

\`\`\`bash
cd /home/user/docker-dist

cat > .env <<ENVEOF
APP_NAME=${APP_NAME}
DOCKER_IMAGE=${FULL_IMAGE_NAME}
LOG_PATH=/var/log/${APP_NAME}
DEST_DIR=\$(pwd)
ENVEOF

mkdir -p /var/log/${APP_NAME}
docker compose up -d
\`\`\`

---

## 🔍 운영 명령어

\`\`\`bash
# 컨테이너 상태 확인
docker ps | grep ${APP_NAME}

# 실시간 로그 확인
docker logs -f --tail 200 ${APP_NAME}-app

# 서비스 재시작 (Systemd인 경우)
sudo systemctl restart ${APP_NAME}

# 컨테이너 직접 재시작
docker compose restart

# 서비스 중지
docker compose down
\`\`\`

---

## ⚙️ 설정 파일 변경 방법

\`config/\` 폴더의 파일(예: \`application.yml\`, \`log4j2.yml\`)은 컨테이너에 **Host Mount** 되어 있습니다.
파일을 수정한 뒤 컨테이너를 재시작하면 **이미지 재빌드 없이** 즉시 반영됩니다.

\`\`\`bash
docker compose restart
# 또는
sudo systemctl restart ${APP_NAME}
\`\`\`
EOF

echo "📄 DEPLOY-GUIDE.md 생성 완료: $DOCKER_DIST_DIR/DEPLOY-GUIDE.md"
echo "✅ Docker 컨텍스트 준비 완료"
echo "   🐳 빌드 컨텍스트: $DOCKER_BUILD_DIR"
echo "   📦 배포 디렉토리: $DOCKER_DIST_DIR"
