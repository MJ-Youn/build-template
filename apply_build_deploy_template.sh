#!/usr/bin/env bash
# =============================================================================
# 타겟 프로젝트에 build_test의 빌드 및 배포 스크립트 템플릿을 복사하고,
# pom.xml을 알맞게 수정하는 자동화 스크립트.
#
# 사용법: ./apply_build_deploy_template.sh <타겟_프로젝트_경로>
# 예시:   ./apply_build_deploy_template.sh ../ymtech-gitlab/nccat-web
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ -z "$1" ]; then
    echo -e "${RED}❌ 타겟 프로젝트 경로를 입력해주세요.${NC}"
    echo -e "${YELLOW}사용법: ./apply_build_deploy_template.sh <타겟_프로젝트_경로>${NC}"
    exit 1
fi

export TARGET_DIR="$1"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

# 타겟 디렉토리가 유효한지 확인
if [ ! -d "${TARGET_DIR}" ]; then
    echo -e "${RED}❌ 타겟 프로젝트 경로가 존재하지 않습니다: ${TARGET_DIR}${NC}"
    exit 1
fi

if [ ! -f "${TARGET_DIR}/pom.xml" ]; then
    echo -e "${RED}❌ 타겟 프로젝트에 pom.xml이 존재하지 않습니다 (Maven 프로젝트 아님): ${TARGET_DIR}${NC}"
    exit 1
fi

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}🚀 배포 템플릿 적용 시작 (타겟: ${TARGET_DIR})${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

# 1. 파일 및 디렉토리 복사
echo -e "${CYAN}[1/3] 📂 템플릿 파일 및 디렉토리 복사 중...${NC}"

# scripts/
if [ -d "${SOURCE_DIR}/scripts" ]; then
    echo -e "   - scripts/ 디렉토리 복사"
    cp -r "${SOURCE_DIR}/scripts" "${TARGET_DIR}/"
fi

# assembly/
if [ -d "${SOURCE_DIR}/assembly" ]; then
    echo -e "   - assembly/ 디렉토리 복사"
    mkdir -p "${TARGET_DIR}/assembly"
    cp -r "${SOURCE_DIR}/assembly/"* "${TARGET_DIR}/assembly/"
fi

# build_deploy.sh, mvnw 등
echo -e "   - 메인 스크립트 및 Maven Wrapper 파일 복사"
cp "${SOURCE_DIR}/build_deploy.sh" "${TARGET_DIR}/"
cp "${SOURCE_DIR}/mvnw" "${TARGET_DIR}/"
cp "${SOURCE_DIR}/mvnw.cmd" "${TARGET_DIR}/"
if [ -d "${SOURCE_DIR}/.mvn" ]; then
    cp -r "${SOURCE_DIR}/.mvn" "${TARGET_DIR}/"
fi

# 권한 설정
chmod +x "${TARGET_DIR}/build_deploy.sh" "${TARGET_DIR}/mvnw"
echo -e "${GREEN}✅ 복사 완료${NC}"
echo ""

# 기존 빌드/배포 관련 레거시 디렉토리 및 파일 삭제
echo -e "${CYAN}[1.5/3] 🧹 기존 레거시 빌드/배포 디렉토리 정리 중...${NC}"
LEGACY_DIRS=("shell" "workdir" "deploy" "config.profiles")
for DIR in "${LEGACY_DIRS[@]}"; do
    if [ -d "${TARGET_DIR}/${DIR}" ]; then
        echo -e "   - 레거시 디렉토리 삭제: ${DIR}/"
        rm -rf "${TARGET_DIR}/${DIR}"
    fi
done
echo -e "${GREEN}✅ 정리 완료${NC}"
echo ""

# 2. pom.xml 자동 수정 (파이썬 스크립트 활용)
echo -e "${CYAN}[2/3] 📝 타겟 프로젝트의 pom.xml 수정 중...${NC}"

python3 - << 'EOF'
import sys
import re
import os

pom_path = os.path.join(os.environ.get('TARGET_DIR'), 'pom.xml')

with open(pom_path, 'r', encoding='utf-8') as f:
    content = f.read()

changed = False

# 1. properties 추가 (env, dist.dir)
if '<env>dev</env>' not in content:
    prop_add = """
    <!-- 환경 기본값 (Maven Profile로 재정의 가능) -->
    <env>dev</env>
    <!-- 패키지 결과물 경로 -->
    <dist.dir>${project.build.directory}/dist</dist.dir>
"""
    content = re.sub(r'(<properties>)', r'\1' + prop_add, content, count=1)
    changed = True
    print("   - <properties> 에 <env> 및 <dist.dir> 속성 추가 완료.")

# 2. maven-assembly-plugin 덮어쓰기
assembly_old_pattern = r"<!--\s*begin:\s*make\s*'deploy'\s*-->\s*<plugin>\s*<groupId>org\.apache\.maven\.plugins</groupId>\s*<artifactId>maven-assembly-plugin</artifactId>\s*</plugin>\s*<!--\s*end:\s*make\s*'deploy'\s*-->"

assembly_new = """<!-- begin: make 'deploy' -->
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-assembly-plugin</artifactId>
        <version>3.7.1</version>
        <configuration>
          <!-- 파일명: {artifactId}-{version}-{env}.dist -->
          <finalName>${project.artifactId}-${project.version}-${env}.dist</finalName>
          <appendAssemblyId>false</appendAssemblyId>
          <outputDirectory>${dist.dir}</outputDirectory>
          <descriptors>
            <descriptor>assembly/dist.xml</descriptor>
          </descriptors>
          <!-- @appName@ 토큰 치환 (scripts/ 내 Shell Script용) -->
          <filters>
            <filter>assembly/filter.properties</filter>
          </filters>
        </configuration>
        <executions>
          <!-- 부모 POM에서 상속된 기본 Assembly 실행 비활성화 -->
          <execution>
            <id>Package '${build.profile}'</id>
            <phase>none</phase>
          </execution>
          <execution>
            <id>Install '${build.profile}'</id>
            <phase>none</phase>
          </execution>
          
          <execution>
            <id>make-dist-zip</id>
            <phase>package</phase>
            <goals>
              <goal>single</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
      <!-- end: make 'deploy' -->"""

if '<descriptors>' not in content and '<descriptor>assembly/dist.xml</descriptor>' not in content:
    content, count = re.subn(assembly_old_pattern, assembly_new, content)
    if count > 0:
        changed = True
        print("   - maven-assembly-plugin 설정 주입 완료.")
    else:
        print("   - (경고) 기존 maven-assembly-plugin 블록을 찾지 못하여 설정을 주입할 수 없습니다. 수동 추가가 필요할 수 있습니다.")
else:
    print("   - maven-assembly-plugin 이 이미 설정되어 있는 것으로 보입니다.")

# 3. profiles 추가
if '<profiles>' not in content:
    profiles_block = """
  <!-- ========== 환경별 Maven Profile ========== -->
  <profiles>
    <profile>
      <id>dev</id>
      <activation><activeByDefault>true</activeByDefault></activation>
      <properties><env>dev</env></properties>
    </profile>
    <profile>
      <id>prod</id>
      <properties><env>prod</env></properties>
    </profile>
    <profile>
      <id>local</id>
      <properties><env>local</env></properties>
    </profile>
    <profile>
      <id>test</id>
      <properties><env>test</env></properties>
    </profile>
    <profile>
      <id>stage</id>
      <properties><env>stage</env></properties>
    </profile>
  </profiles>
"""
    content = re.sub(r'</project>', profiles_block + '\n</project>', content)
    changed = True
    print("   - <profiles> 블록 추가 완료.")

if changed:
    with open(pom_path, 'w', encoding='utf-8') as f:
        f.write(content)
else:
    print("   - pom.xml 파일이 이미 적용되어 있거나, 변경할 내역이 없습니다.")

EOF

echo -e "${GREEN}✅ pom.xml 수정 완료${NC}"
echo ""

echo -e "${CYAN}[3/3] 마무리 안내${NC}"
echo -e "   타겟 프로젝트(${TARGET_DIR})에 빌드/배포 스크립트 적용이 완료되었습니다."
echo -e "   적용 여부를 확인하기 위해 타겟 프로젝트로 이동 후 아래 명령을 실행해 보세요:"
echo -e "   ${YELLOW}cd ${TARGET_DIR} && ./build_deploy.sh -Penv=dev${NC}"
echo ""
echo -e "${CYAN}======================================================${NC}"
echo -e "${GREEN}🎉 모든 작업이 완료되었습니다!${NC}"
echo -e "${CYAN}======================================================${NC}"
