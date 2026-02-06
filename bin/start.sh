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
# nohup을 사용하여 쉘이 닫혀도 실행이 유지되도록 함
# 수동으로 실행할 경우 백그라운드에서 실행됨
# -Dlog.path 옵션으로 로그 경로 전달
# -Dapp.name 옵션으로 앱 이름 전달 (Log4j2 등에서 사용)
nohup java -jar -Dspring.config.location="$CONFIG_LOC" -Dlog.path="$LOG_PATH" -Dapp.name="$APP_NAME" "$JAR_FILE" > /dev/null 2>&1 &

PID=$!
echo "애플리케이션이 시작되었습니다. PID: $PID"
echo $PID > "$SCRIPT_DIR/application.pid"
