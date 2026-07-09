FROM eclipse-temurin:25-jdk-alpine

WORKDIR /app

# Alpine 이미지는 기본적으로 bash가 없으므로 설치, 권한 전환을 위한 패키지 추가
RUN apk add --no-cache bash su-exec shadow

ARG APP_NAME="app"
# APP_NAME 기반 계정 생성 (기본 UID/GID: 1000)
RUN CLEAN_APP_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g') && \
    APP_USER="${CLEAN_APP_NAME}user" && \
    addgroup -g 1000 ${APP_USER} && adduser -u 1000 -G ${APP_USER} -S ${APP_USER}

# 배포 패키지 내용 복사
# libs, config, bin 폴더가 빌드 컨텍스트 루트에 있다고 가정
# gradle zipDist 실행 후 추출하거나 프로젝트 루트에서 복사

COPY libs/ /app/libs/
COPY config/ /app/config/
COPY bin/start.sh /app/bin/start.sh
COPY bin/utils.sh /app/bin/utils.sh
COPY bin/bootstrap.sh /app/bin/bootstrap.sh

# 스크립트 실행 권한 부여 및 /app 소유권 변경
RUN CLEAN_APP_NAME=$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g') && \
    APP_USER="${CLEAN_APP_NAME}user" && \
    chmod +x /app/bin/*.sh && chown -R ${APP_USER}:${APP_USER} /app

# 애플리케이션 실행
ENTRYPOINT ["/app/bin/start.sh"]
