#!/bin/bash

# 설정 파일 경로
SETTINGS_FILE="settings.gradle"
BUILD_FILE="build.gradle"
APP_CONFIG="config/application.yml"

# OS 확인 및 sed 명령 설정 (Mac/Linux 호환성)
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_CMD=(sed -i '')
else
  SED_CMD=(sed -i)
fi

# 1. 현재 설정값 확인
if [ -f "$SETTINGS_FILE" ]; then
    CURRENT_PROJECT_NAME=$(grep "rootProject.name" "$SETTINGS_FILE" | cut -d"'" -f2)
else
    echo "❌ $SETTINGS_FILE 을 찾을 수 없습니다."
    exit 1
fi

if [ -f "$BUILD_FILE" ]; then
    CURRENT_GROUP=$(grep "group =" "$BUILD_FILE" | cut -d"'" -f2)
else
    echo "❌ $BUILD_FILE 을 찾을 수 없습니다."
    exit 1
fi

CURRENT_PORT="8080" # 기본값
if [ -f "$APP_CONFIG" ]; then
    # 간단한 파싱 (정교한 YAML 파싱은 아님)
    DETECTED_PORT=$(grep "port:" "$APP_CONFIG" | head -n 1 | awk '{print $2}' | tr -d ' ')
    if [ -n "$DETECTED_PORT" ]; then
        CURRENT_PORT=$DETECTED_PORT
    fi
fi

echo "========================================="
echo "🚀 프로젝트 초기화 스크립트 (init.sh)"
echo "========================================="
echo "현재 설정:"
echo "- Project Name: $CURRENT_PROJECT_NAME"
echo "- Group Name:   $CURRENT_GROUP"
echo "- Server Port:  $CURRENT_PORT"
echo "-----------------------------------------"

# 2. 사용자 입력 받기
read -p "새로운 Project Name을 입력하세요 [$CURRENT_PROJECT_NAME]: " NEW_PROJECT_NAME
NEW_PROJECT_NAME=${NEW_PROJECT_NAME:-$CURRENT_PROJECT_NAME}

read -p "새로운 Group Name을 입력하세요 [$CURRENT_GROUP]: " NEW_GROUP_NAME
NEW_GROUP_NAME=${NEW_GROUP_NAME:-$CURRENT_GROUP}

read -p "새로운 Server Port를 입력하세요 [$CURRENT_PORT]: " NEW_PORT
NEW_PORT=${NEW_PORT:-$CURRENT_PORT}

echo "-----------------------------------------"
echo "변경할 설정:"
echo "- Project Name: $NEW_PROJECT_NAME"
echo "- Group Name:   $NEW_GROUP_NAME"
echo "- Server Port:  $NEW_PORT"
echo "========================================="

read -p "위 설정으로 적용하시겠습니까? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "⛔ 취소되었습니다."
    exit 0
fi

# 3. 설정 적용

# 3-1. settings.gradle 수정
"${SED_CMD[@]}" "s/rootProject.name = .*/rootProject.name = '$NEW_PROJECT_NAME'/" "$SETTINGS_FILE"
echo "✅ settings.gradle 수정 완료"

# 3-2. build.gradle 수정
"${SED_CMD[@]}" "s/group = .*/group = '$NEW_GROUP_NAME'/" "$BUILD_FILE"
echo "✅ build.gradle 수정 완료"

# 3-3. config/application.yml 수정
if [ -f "$APP_CONFIG" ]; then
    # Server Port 수정
    if grep -q "port:" "$APP_CONFIG"; then
        "${SED_CMD[@]}" "s/port: .*/port: $NEW_PORT/" "$APP_CONFIG"
    else
        # server: port: 구조가 없을 경우 추가 (간단히 append)
        # 이미 server: 블록이 있는지 확인 등 복잡한 로직보다는, 기본 템플릿에 port가 있다고 가정하거나 Append
        # 여기서는 파일 맨 끝에 간단히 추가하지 않고, server: 블록을 찾거나 새로 만듭니다.
        # 기존 파일에 server: 블록이 없다고 가정하고 추가
         if ! grep -q "server:" "$APP_CONFIG"; then
            echo -e "\nserver:\n  port: $NEW_PORT" >> "$APP_CONFIG"
         fi
    fi

    # Spring Application Name 수정
    if grep -q "name: $CURRENT_PROJECT_NAME" "$APP_CONFIG"; then
        "${SED_CMD[@]}" "s/name: $CURRENT_PROJECT_NAME/name: $NEW_PROJECT_NAME/" "$APP_CONFIG"
    elif grep -q "name:" "$APP_CONFIG"; then
        "${SED_CMD[@]}" "s/name: .*/name: $NEW_PROJECT_NAME/" "$APP_CONFIG"
    fi
    echo "✅ config/application.yml 수정 완료"
fi

# 3-4. 패키지 구조 변경 및 파일 내용 수정 (Group Name 변경 시)
if [ "$CURRENT_GROUP" != "$NEW_GROUP_NAME" ]; then
    echo "📦 패키지 구조 변경 작업을 시작합니다..."
    
    # 점(.)을 슬래시(/)로 변환
    OLD_PATH=${CURRENT_GROUP//./\/}
    NEW_PATH=${NEW_GROUP_NAME//./\/}
    
    SRC_DIRS=("src/main/java" "src/test/java")
    
    for DIR in "${SRC_DIRS[@]}"; do
        FULL_OLD_PATH="$DIR/$OLD_PATH"
        FULL_NEW_PATH="$DIR/$NEW_PATH"
        
        if [ -d "$FULL_OLD_PATH" ]; then
            echo "   ➡️ $DIR 패키지 이동 중..."
            mkdir -p "$FULL_NEW_PATH"
            
            # 파일 이동
            mv "$FULL_OLD_PATH"/* "$FULL_NEW_PATH/" 2>/dev/null
            
            # 빈 디렉토리 정리 (이전 패키지 경로 삭제)
            # 예: io/github/mjyoun -> io/github (mjyoun 삭제) -> io (github 삭제)
            # find -depth 사용하여 하위 디렉토리부터 삭제 시도
            find "$DIR" -type d -empty -delete
        else
            echo "   ⚠️ 경고: $FULL_OLD_PATH 디렉토리를 찾을 수 없습니다."
        fi
    done
    
    # 3-5. Java 파일 내 package 및 import 문 수정
    echo "📝 Java 파일 내 package/import 문 수정 중..."
    
    # package 구문 수정
    find src -name "*.java" -exec "${SED_CMD[@]}" "s/package ${CURRENT_GROUP}/package ${NEW_GROUP_NAME}/g" {} +
    
    # import 구문 수정 (현재 그룹을 참조하는 import만 수정)
    find src -name "*.java" -exec "${SED_CMD[@]}" "s/import ${CURRENT_GROUP}/import ${NEW_GROUP_NAME}/g" {} +
    
    echo "✅ 패키지 구조 변경 완료"
fi

echo "========================================="
echo "🎉 초기화가 성공적으로 완료되었습니다!"
echo "변경된 설정을 확인해주세요."
echo "-----------------------------------------"
echo "이 스크립트($0)는 보안을 위해 삭제됩니다."
rm -- "$0"
