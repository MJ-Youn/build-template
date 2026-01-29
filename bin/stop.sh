#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PID_FILE="$SCRIPT_DIR/application.pid"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  echo "애플리케이션 중지 중 (PID: $PID)..."
  kill "$PID"
  rm "$PID_FILE"
  echo "애플리케이션이 중지되었습니다."
else
  echo "PID 파일을 찾을 수 없습니다. 프로세스 이름으로 종료를 시도합니다..."
  # PID 파일이 없을 경우 pkill을 사용하여 종료 시도 (여러 인스턴스가 있을 경우 주의 필요)
  pkill -f "build_test" || echo "실행 중인 프로세스를 찾을 수 없습니다."
fi
