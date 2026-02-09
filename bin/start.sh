#!/bin/bash

# 스크립트가 위치한 디렉토리 찾기
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# @appName@은 Gradle 빌드 시 실제 프로젝트 이름으로 치환됨
APP_NAME="@appName@"

# 기본 설정 파일 위치 (config 폴더)
CONFIG_LOC="file:$PROJECT_ROOT/config/"

# 환경 설정 파일 로드 (존재 시)
# bin/.app-env.properties 위치 (스크립트와 동일 위치, 숨김 파일)
ENV_FILE="$SCRIPT_DIR/.app-env.properties"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# 로그 경로 설정 (환경 변수 > 기본값)
# install_service.sh에 의해 구축된 구조: ROOT/bin, ROOT/log, ROOT/config
LOG_PATH="${LOG_PATH:-$PROJECT_ROOT/log}"

# 로그 폴더가 없으면 생성 (권한 문제 없다고 가정)
if [ ! -d "$LOG_PATH" ]; then
    mkdir -p "$LOG_PATH"
fi

# 실행 가능한 JAR 파일 찾기
JAR_FILE=$(find "$PROJECT_ROOT/libs" -name "*.jar" | head -n 1)

if [ -z "$JAR_FILE" ]; then
  echo "오류: $PROJECT_ROOT/libs 경로에서 애플리케이션 JAR 파일을 찾을 수 없습니다."
  exit 1
fi

echo "애플리케이션 시작 중 ($APP_NAME)..."
echo "JAR 파일: $JAR_FILE"
echo "설정 경로: $CONFIG_LOC"
echo "로그 경로: $LOG_PATH"

# 애플리케이션 실행
# Docker 환경에서는 exec를 사용하여 프로세스를 PID 1로 포그라운드 실행
# (Docker 컨테이너가 즉시 종료되는 것을 방지하고 시그널 전달을 원활하게 함)
if [ -f /.dockerenv ] || [ "$$" -eq 1 ]; then
    echo "Docker 환경 감지: 포그라운드 모드로 실행합니다."
    exec java -jar -Dspring.config.location="$CONFIG_LOC" -Dlog.path="$LOG_PATH" -Dapp.name="$APP_NAME" "$JAR_FILE"
else
    # 일반 환경: nohup을 사용하여 백그라운드에서 실행 유지
    nohup java -jar -Dspring.config.location="$CONFIG_LOC" -Dlog.path="$LOG_PATH" -Dapp.name="$APP_NAME" "$JAR_FILE" > /dev/null 2>&1 &
    PID=$!
    echo "애플리케이션이 시작되었습니다. PID: $PID"
    echo $PID > "$SCRIPT_DIR/application.pid"
fi
