#!/bin/bash

# 설정 파일 경로
SETTINGS_FILE="settings.gradle"
BUILD_FILE="build.gradle"
APP_CONFIG="config/application.yml"

# OS 확인 및 sed 명령 설정 (Mac/Linux 호환성)
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_CMD=("sed" "-i" "")
else
  SED_CMD=("sed" "-i")
fi

# 1. 현재 설정값 확인 (파싱 로직 강화)
if [ -f "$SETTINGS_FILE" ]; then
    # rootProject.name = '...' 형태에서 값 추출. 공백 및 작은따옴표 제거.
    CURRENT_PROJECT_NAME=$(grep "rootProject.name" "$SETTINGS_FILE" | head -n 1 | cut -d"=" -f2 | tr -d "[:space:]'")
else
    echo "❌ $SETTINGS_FILE 을 찾을 수 없습니다."
    exit 1
fi

if [ -f "$BUILD_FILE" ]; then
    # group = '...' 형태에서 값 추출. 맨 앞줄(들여쓰기 없는) group만 추출.
    CURRENT_GROUP=$(grep "^group =" "$BUILD_FILE" | head -n 1 | cut -d"=" -f2 | tr -d "[:space:]'")
else
    echo "❌ $BUILD_FILE 을 찾을 수 없습니다."
    exit 1
fi

CURRENT_PORT="8080" # 기본값
if [ -f "$APP_CONFIG" ]; then
    # port: 8080 형태 추출. 첫 번째 매칭되는 포트만.
    DETECTED_PORT=$(grep "port:" "$APP_CONFIG" | head -n 1 | cut -d":" -f2 | tr -d "[:space:]")
    if [ -n "$DETECTED_PORT" ]; then
        CURRENT_PORT=$DETECTED_PORT
    fi
fi

# 디버깅: 파싱된 값 확인
echo "========================================="
echo "🚀 프로젝트 초기화 스크립트 (init.sh) - Path Fix"
echo "========================================="
echo "현재 설정 (파싱 결과):"
echo "- Project Name: [$CURRENT_PROJECT_NAME]"
echo "- Group Name:   [$CURRENT_GROUP]"
echo "- Server Port:  [$CURRENT_PORT]"
echo "-----------------------------------------"

if [ -z "$CURRENT_PROJECT_NAME" ] || [ -z "$CURRENT_GROUP" ]; then
    echo "❌ 설정 파일을 파싱하는데 실패했습니다. 파일 내용을 확인해주세요."
    exit 1
fi

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
"${SED_CMD[@]}" "s/^group = .*/group = '$NEW_GROUP_NAME'/" "$BUILD_FILE"
echo "✅ build.gradle 수정 완료"

# 3-3. config/application.yml 수정
if [ -f "$APP_CONFIG" ]; then
    # Server Port 수정
    if grep -q "port:" "$APP_CONFIG"; then
        "${SED_CMD[@]}" "s/port: .*/port: $NEW_PORT/" "$APP_CONFIG"
    else
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

# 3-4. 패키지 구조 변경 (Group Name + Project Name)
echo "📦 패키지 구조 변경 작업을 시작합니다..."

# Java 패키지명 규칙: 소문자, 하이픈(-)은 언더스코어(_)로 변환
to_package_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr '-' '_'
}

OLD_PKG_GROUP=$(to_package_name "$CURRENT_GROUP")
NEW_PKG_GROUP=$(to_package_name "$NEW_GROUP_NAME")

OLD_PKG_PROJECT=$(to_package_name "$CURRENT_PROJECT_NAME")
NEW_PKG_PROJECT=$(to_package_name "$NEW_PROJECT_NAME")

# 전체 패키지 경로 계산 (Group + ProjectName)
# 예: io.github.mjyoun.build_test -> io/github/mjyoun/build_test
OLD_FULL_PKG="${OLD_PKG_GROUP}.${OLD_PKG_PROJECT}"
NEW_FULL_PKG="${NEW_PKG_GROUP}.${NEW_PKG_PROJECT}"

# OLD_PATH와 NEW_PATH 생성 (tr 사용)
OLD_PATH=$(echo "$OLD_PKG_GROUP" | tr '.' '/')
if [ -n "$OLD_PKG_PROJECT" ]; then
    OLD_PATH="${OLD_PATH}/${OLD_PKG_PROJECT}"
fi

NEW_PATH=$(echo "$NEW_PKG_GROUP" | tr '.' '/')
if [ -n "$NEW_PKG_PROJECT" ]; then
    NEW_PATH="${NEW_PATH}/${NEW_PKG_PROJECT}"
fi

echo "   - Old Package: $OLD_FULL_PKG (Path: $OLD_PATH)"
echo "   - New Package: $NEW_FULL_PKG (Path: $NEW_PATH)"

SRC_DIRS=("src/main/java" "src/test/java")

for DIR in "${SRC_DIRS[@]}"; do
    FULL_OLD_PATH="$DIR/$OLD_PATH"
    FULL_NEW_PATH="$DIR/$NEW_PATH"
    
    # 1. Standard 구조 확인 (group/project)
    if [ -d "$FULL_OLD_PATH" ]; then
        echo "   ➡️ $DIR: $OLD_FULL_PKG -> $NEW_FULL_PKG 이동 중..."
        mkdir -p "$FULL_NEW_PATH"
        mv "$FULL_OLD_PATH"/* "$FULL_NEW_PATH/" 2>/dev/null
        
        # 빈 디렉토리 정리 (역순 삭제)
        find "$DIR" -type d -empty -delete 2>/dev/null
        
    # 2. Simple 구조 확인 (group only)
    elif [ -d "$DIR/$(echo "$OLD_PKG_GROUP" | tr '.' '/')" ]; then
        SIMPLE_OLD_PATH="$DIR/$(echo "$OLD_PKG_GROUP" | tr '.' '/')"
        echo "   ℹ️ Simple 구조 감지 ($SIMPLE_OLD_PATH)"
        
        # Simple 구조에서는 Group만 변경하는 것이 아니라 Project 구조로 확장하거나 Group만 변경
        # 여기서는 Group만 변경되는 것으로 가정하고 이동
        FULL_OLD_PATH="$SIMPLE_OLD_PATH"
        # 새로 생성될 경로는 Group + Project 구조를 따를 것인지, Group만 따를 것인지 결정해야 함.
        # 기존: Simple -> Simple 유지 또는 Simple -> Standard 변환?
        # 보통 init 스크립트는 Standard 구조를 지향하므로 Standard로 변환 시도
        
        echo "   ➡️ $DIR: $OLD_PKG_GROUP -> $NEW_FULL_PKG (Standard 구조로 변환)"
        mkdir -p "$FULL_NEW_PATH"
        mv "$FULL_OLD_PATH"/* "$FULL_NEW_PATH/" 2>/dev/null
        find "$DIR" -type d -empty -delete 2>/dev/null
        
        # 패키지명 변수 재설정 (Sed 용)
        # 중요: 원본 코드가 Simple 구조였다면 package io.github.mjyoun; 이었을 것임.
        # 이를 package kr.co.lguplus.hdrms_web; 으로 변경
        OLD_FULL_PKG="$OLD_PKG_GROUP"
        NEW_FULL_PKG="$NEW_FULL_PKG"
    else
        echo "   ⚠️ 경고: $FULL_OLD_PATH 디렉토리를 찾을 수 없습니다."
    fi
done

# 3-5. Java 파일 내 package 및 import 문 수정
echo "📝 Java 파일 내 package/import 문 수정 중..."

# package 구문 수정 (구분자 | 사용)
# 기존 패키지명이 포함된 모든 구문을 새 패키지명으로 변경
# 예: package io.github.mjyoun.build_test; -> package kr.co.lguplus.hdrms_web;
find src -name "*.java" -exec "${SED_CMD[@]}" "s|package ${OLD_FULL_PKG}|package ${NEW_FULL_PKG}|g" {} +

# import 구문 수정 (구분자 | 사용)
find src -name "*.java" -exec "${SED_CMD[@]}" "s|import ${OLD_FULL_PKG}|import ${NEW_FULL_PKG}|g" {} +

echo "✅ 패키지 구조 및 내용 변경 완료"

echo "========================================="
echo "🎉 초기화가 성공적으로 완료되었습니다!"
echo "변경된 설정을 확인해주세요."
echo "-----------------------------------------"
echo "이 스크립트($0)는 보안을 위해 삭제됩니다."
rm -- "$0"
