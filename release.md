# 📦 Release Notes

`io.github.mj-youn.distribution` (Gradle) & `distribution-maven-plugin` (Maven) 빌드/배포 플러그인의 버전별 릴리즈 노트입니다. ✨

## 🎯 [3.5.0] - 2026-10-29

> 🚀 **Minor Release** — Docker 인프라 환경변수(`.env`)와 Spring Boot 애플리케이션 런타임 환경설정(`application.env`)의 완전한 분리 및 전용 생성 명령어(`initEnv`, `initApplicationEnv` / `mvn distribution:initEnv`, `mvn distribution:initApplicationEnv`) 신규 탑재, 프로젝트 및 환경 프로파일별 스마트 타겟팅, 기존 파일 보존 안심 스킵 및 강제 덮어쓰기(`-Pforce` / `-Dforce=true`) 지원, 전 소스 코드 품질 및 Javadoc 표준화 전면 리팩토링 완료.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. ⚙️ 환경설정 파일 분리 및 전용 생성 명령어 신규 추가 (`initEnv` & `initApplicationEnv`)

- **Docker 인프라(`.env`) vs Spring Boot 런타임(`application.env`) 역할 분리**:
    - 기존에 단일 `.env` 파일에 섞여 있던 Docker 인프라 설정과 Java 애플리케이션 런타임 옵션을 목적에 맞게 완전히 분리했습니다.
    - **`initEnv` (Docker Compose 전용)**:
        - 컨테이너 실행 UID/GID(`APP_UID`, `APP_GID`), 포트(`HTTP_PORT`), 이미지명(`DOCKER_IMAGE`), 호스트 로그 경로(`LOG_PATH`)를 관리하는 `.env` 파일을 생성합니다.
        - 프로파일 지정 시 `docker.profiles/{profile}/.env-{profile}`에 생성되며, 패키징 시 배포 루트의 `.env`로 적재됩니다.
    - **`initApplicationEnv` (Spring Boot 런타임 전용)**:
        - JVM 힙 메모리(`JVM_XMS`, `JVM_XMX`), 추가 JVM 옵션(`EXTRA_JAVA_OPTS`), 프로그램 인수(`APP_ARGS`)를 관리하는 `application.env` 파일을 생성합니다.
        - 프로파일 지정 시 `config.profiles/{profile}/application-{profile}.env`에 생성되며, 패키징 시 `config/application.env`로 정규화 적재됩니다.
- **`initDocker`, `initDeployScript`와 동일한 원클릭 개발자 경험 제공**:
    - Gradle 및 Maven 플러그인 100% 동일 사양 구현 (`./gradlew initEnv`, `./gradlew initApplicationEnv` / `mvn distribution:initEnv`, `mvn distribution:initApplicationEnv`).
    - 로컬 템플릿 우선 사용 및 플러그인 내장 템플릿 자동 폴백 지원.
- **안전한 덮어쓰기 방지 메커니즘**:
    - 이미 대상 파일이 존재하는 경우 개발자의 기존 설정을 보호하기 위해 기본적으로 건너뛰며(`[SKIP]`), 강제 덮어쓰기가 필요한 경우 `-Pforce` (`-Dforce=true`) 또는 `-Poverwrite` 옵션으로 덮어쓰기 가능.

#### 2. 🚀 배포 패키징 및 실행 스크립트(`start.sh`) 런타임 연동 강화

- **패키징 시 프로파일 접미사 자동 정규화**:
    - `config.profiles/{env}/application-{env}.env` 파일이 패키징 시 `config/application.env`로 자동 변환되어 컨테이너의 `/app/config/application.env`로 마운트됩니다.
- **`start.sh` 실행 스크립트 로드 우선순위**:
    - `start.sh`가 기동 시 `config/application.env`를 로드하여 JVM 힙 메모리 및 `APP_ARGS`를 Java 프로세스에 동적 주입합니다.
    - 기존 프로젝트 호환을 위해 `config/.env` 및 루트 `.env` 폴백도 정상 지원합니다.

#### 3. 🛠️ 소스 코드 품질 및 Javadoc 표준화 전면 리팩토링

- **`code_quality_and_review.md` 표준 가이드라인 100% 준수**:
    - **`@Override` 메소드 주석 규격화**: 부가 설명이나 `@param`, `@return` 중복 작성을 배제하고, 반드시 `@see`, `@author`, `@since` 3개 태그만 규격화하여 작성.
    - **Javadoc 전수 문서화**: 모든 클래스, public/protected/private 메소드에 한글 Javadoc 설명 및 파라미터/반환값 문서화 완료.
    - **제어문 Block 구문 준수**: 단일 라인 `if`, `for`, `while` 제어문에 빠짐없이 중괄호 `{}` 블록 적용.
    - **Import 최적화**: 와일드카드(`*`) import 전면 제거 및 미사용 import 정리.

#### 4. 📦 전체 플러그인 메타데이터 및 문서 버전 동기화

- `distribution-gradle-plugin` (Gradle) & `distribution-maven-plugin` (Maven) 버전 `3.5.0` 갱신.
- 사용자 및 개발자 가이드(`README.md`, `README_EN.md`, `DEVELOPER_GUIDE.md`) 내 플러그인 의존성 설정 버전 `3.5.0` 반영.

---

## 🎯 [3.4.2] - 2026-10-27

> 🚀 **Patch Release** — 템플릿 치환기(`ReplaceTokens`)에 의한 스크립트 비교 조건문 오염 결함 긴급 패치(`(unpacked)` 서비스명 오염 해결), 와일드카드 패턴 매칭(`[[ "$APP_NAME" == "@"*"@" ]]`)을 통한 토큰 미치환 감지 안전화, 플러그인 콘솔 출력 내 잔류 구버전(`3.3.1`) 하드코딩 문자열 일괄 동기화.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. 🐛 배포 스크립트 토큰 치환 비교 구문 오염 및 서비스명 `(unpacked)` 둔갑 결함 긴급 수정

- **`ReplaceTokens`에 의한 조건문 오염 원천 차단**:
    - 기존 `start.sh`, `install_service.sh`, `status.sh`의 `if [ "$BUILTIN_APP_NAME" != "@appName@" ]` 조건식이 빌드 시점에 `@appName@`이 프로젝트명(예: `mo-service`)으로 일괄 치환되면서 `if [ "mo-service" != "mo-service" ]`(무조건 거짓)로 변조되던 결함을 수정했습니다.
    - 이로 인해 `APP_NAME="$(basename "$PKG_ROOT")"` 폴백 로직을 타서 `build_deploy.sh`가 임시 압축 해제한 디렉토리명인 **`unpacked`**가 앱 이름으로 등록되던 문제를 완벽하게 해결했습니다.
    - Windows `start.bat`과 동일하게 **와일드카드 패턴 매칭(`[[ "$APP_NAME" == "@"*"@" ]]`)** 방식을 적용하여, 빌드 치환기가 비교 구문을 오염시키지 못하도록 차단하고 실제 치환된 고유 프로젝트명을 안전하게 확정하도록 개편했습니다.

#### 2. 🏷️ 플러그인 빌드 완료 및 안내 콘솔 로그 버전 문자열 동기화

- Gradle 및 Maven 플러그인 소스코드(`DistributionPlugin.java`, `DistributionMojo.java`, `ShowDockerMojo.java`) 내 패키징 완료 로그 및 아키텍처 비교 가이드에 남아있던 구버전(`3.3.1`) 하드코딩 문자열을 `3.4.2`로 전면 동기화했습니다.

#### 3. 📦 전체 플러그인 메타데이터 및 문서 버전 동기화

- `distribution-gradle-plugin` (Gradle) & `distribution-maven-plugin` (Maven) 버전 `3.4.2` 갱신.
- 사용자 및 개발자 가이드(`README.md`, `README_EN.md`, `DEVELOPER_GUIDE.md`) 내 플러그인 의존성 설정 버전 `3.4.2` 반영.

---

## 🎯 [3.4.1] - 2026-10-26

> 🚀 **Patch Release** — 동일 서버/빌드 환경 다중 서비스 배포 시 Docker 빌드 캐시로 인한 실행 스크립트 오염 방지(`docker build --no-cache`), Docker Compose 템플릿 내 `APP_NAME` 환경변수 명시적 주입, 서비스 시작 스크립트(`start.sh`)의 서비스명 결정 우선순위 개선 및 Standalone Tomcat 기동 시 프로젝트 자체 내장 `tomcat` 최우선 탐색 처리.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. 🐳 Docker 이미지 빌드 시 레이어 캐시 무효화(`--no-cache`) 및 다중 태깅 강화

- **`COPY bin/` 레이어 캐시로 인한 이전 서비스 스크립트 오염 원천 차단**:
    - 동일 서버나 동일 쉘 세션에서 여러 서비스를 연속으로 배포(`build_deploy.sh` 등)할 때, Dockerfile의 `COPY bin/ /app/bin/` 단계가 이전 서비스의 레이어 캐시(BuildKit Cache)를 타서 직전 서비스의 `start.sh`(이전 서비스명이 치환된 파일)가 새 이미지에 탑재되던 결함을 수정했습니다.
    - `install_service.sh`, `install_service.bat` 및 Gradle/Maven 플러그인의 `docker build` 명령어에 **`--no-cache` 옵션을 강제 적용**하여 항상 현재 배포 패키지의 최신 스크립트와 아티팩트가 새로 패키징되도록 개선했습니다.
    - 리눅스 `install_service.sh`의 이미지 빌드 시에도 `${IMAGE_TAG}`와 `${APP_NAME}:latest`가 동시에 태깅되도록 동기화했습니다.

#### 2. 📦 Docker Compose 환경설정 내 `APP_NAME` 환경변수 명시적 주입

- **`docker-compose-jar.yml` 및 `docker-compose-tomcat.yml` 환경변수 보강**:
    - 기존 템플릿의 `environment:` 섹션에 `APP_NAME` 환경변수 전달이 누락되어 있던 점을 개선하여, `- APP_NAME=${APP_NAME:-@appName@}`를 명시적으로 주입했습니다.
    - 호스트 배포 디렉토리의 `.env` 파일에 정의된 실제 서비스명이 컨테이너 내부 환경으로 정확하게 상속됩니다.

#### 3. 🚀 서비스 제어 스크립트(`start.sh`, `install_service.sh`, `status.sh`) `APP_NAME` SSOT 보장 및 톰캣 경로 탐색 개선

- **빌드 치환값(SSOT) 최우선 보장 및 쉘 환경변수 오염 방지 (`export APP_NAME`)**:
    - 동일한 터미널/쉘 세션에서 여러 서비스를 연속 배포할 때, 부모 쉘 세션에 잔류된 이전 서비스의 `APP_NAME` 환경변수로 인해 새로 배포된 서비스의 JVM 프로퍼티(`-Dapp.name`) 및 로그 파일명이 직전 서비스명으로 오염되던 문제를 근본적으로 해결했습니다.
    - 빌드 시 치환된 `@appName@`(`$BUILTIN_APP_NAME`)이 존재하는 경우 이를 **단일 진실 공급원(SSOT)으로 최우선 확정**하고, `export APP_NAME`을 통해 `docker compose` 및 하위 프로세스에 올바른 서비스명이 강제 전달되도록 개편했습니다. (템플릿 미치환 원본 실행 시에만 `.env` / 환경변수 / 디렉토리명 순으로 안전하게 폴백)
- **Standalone Tomcat 경로 탐색 버그 수정**:
    - 기존에는 `if [ -z "$CATALINA_HOME" ]; then` 조건으로 인해 이전 세션에서 `export CATALINA_HOME`이 잔류되어 있을 경우 다른 서비스의 톰캣 디렉토리를 바라보던 문제가 있었습니다.
    - 프로젝트 루트 내 `$PROJECT_ROOT/tomcat` 디렉토리가 존재하는 경우, 환경변수 잔류 여부와 상관없이 **해당 프로젝트 자체 내장 Tomcat을 항상 최우선으로 사용**하도록 탐색 순서를 개편했습니다.

#### 4. 📦 전체 플러그인 메타데이터 및 문서 버전 동기화

- `distribution-gradle-plugin` (Gradle) & `distribution-maven-plugin` (Maven) 버전 `3.4.1` 갱신.
- 사용자 및 개발자 가이드(`README.md`, `README_EN.md`, `DEVELOPER_GUIDE.md`) 내 플러그인 의존성 설정 버전 `3.4.1` 반영.

---

## 🎯 [3.4.0] - 2026-10-13

> 🚀 **Minor Release** — Windows 배포 스크립트(`install_service.bat`) 구문 분석 오류(`... was unexpected at this time.`) 근본 해결, Windows 호스트 + Linux 컨테이너 하이브리드 스크립트 패키징(`*.bat` + `*.sh`) 지원, Docker 이미지 빌드 시 배치 파일 배제 3중 방어막 구축, 프로파일별 설정 파일(`application-{env}.yml`) 포트 자동 감지 버그 수정, 배포 루트 `.env` 단일 진실 공급원(SSOT) 확립 및 Windows 서비스 제어 스크립트(`start.bat`, `stop.bat`, `status.bat`) 환경 연동 강화.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. 🪟 Windows 환경 `install_service.bat` 구문 분석 오류 및 토큰 치환 안전성 개선

- **`cmd.exe` 괄호 파싱 충돌 원천 차단 (`goto :LABEL` 리팩토링)**:
    - 안내 메시지 내 `(docker pull ...)...`의 닫는 소괄호 `)`와 `if (...) else (...)` 복합 괄호 블록 간의 파싱 충돌로 인해 발생하던 `... was unexpected at this time.` 오류를 근본적으로 해결했습니다.
    - 고질적인 중첩 괄호 구조를 완전히 제거하고, `:DO_LOAD_TAR`, `:DO_BUILD_IMAGE`, `:DO_PULL_IMAGE`, `:PREPARE_COMPOSE` 등 **명확한 `goto` 라벨 분기 방식**으로 전면 리팩토링했습니다.
    - 배치 스크립트 내 모든 안내 메시지의 소괄호 `(...)`를 대괄호 `[...]`로 변경하고, `.env` 생성 시 `( ... ) > .env` 괄호 블록 대신 라인별 직접 출력(`>`, `>>`) 방식을 적용했습니다.
- **미치환 원본 템플릿 직접 실행 시 자동 복구 폴백(Fallback)**:
    - 사용자가 템플릿 토큰이 치환되지 않은 원본 파일(`@dockerImage@`, `@appName@`)을 직접 복사해 실행하더라도 Docker 태그 형식 오류(`invalid reference format`)가 발생하지 않도록, 최상단 `.env` 파일에서 `APP_NAME`, `DOCKER_IMAGE`, `HTTP_PORT`를 자동 탐색하여 로드하는 안전 폴백 메커니즘을 추가했습니다.

#### 2. 🪟 Windows 배포 환경(-Dos=windows,all) 스크립트 패키징 및 Docker 이미지 최적화

- **Windows 호스트 + Linux Docker 컨테이너 하이브리드 환경 지원**:
    - `-Dos=windows,all` (또는 `-Pos=windows,all`) 설정 시, Windows 호스트 제어용 `*.bat` 스크립트뿐만 아니라 **Docker 컨테이너(Linux 기반) 내부 구동에 필수적인 `*.sh` 스크립트도 함께 패키지에 포함**되도록 필터링 로직을 개선했습니다.
    - Linux 배포 모드(`-Dos=linux`)에서는 기존과 동일하게 불필요한 `*.bat`, `*.cmd` 파일이 자동으로 배제됩니다.
- **Docker 이미지 빌드 시 Windows 배치 파일(`.bat`, `.cmd`) 원천 배제 3중 방어막 구축**:
    1. `docker/.dockerignore` 및 루트 `.dockerignore` 템플릿 신규 추가 및 `initDocker` 실행 시 자동 생성 (`**/*.bat`, `**/*.cmd`, `deploy/` 배제).
    2. Maven/Gradle 플러그인의 Docker 이미지 빌드 컨텍스트 디렉토리(`tmp/docker-build`)에서 `*.bat`, `*.cmd` 파일 사전 자동 삭제 로직 추가.
    3. `docker/Dockerfile-jar`, `docker/Dockerfile-tomcat`에 `RUN rm -f /app/bin/*.bat /app/bin/*.cmd 2>/dev/null || true` 추가하여 최종 이미지 내 순수 Linux 셸 스크립트(`*.sh`)만 탑재 보장.

#### 3. 🔍 프로파일별 설정 파일(`application-{env}.yml`) HTTP 서비스 포트 자동 감지 버그 수정

- **포트 감지 후보 경로에 접미사 패턴(`application-{env}.yml`) 추가**:
    - 기존 포트 감지 로직에 `config.profiles/{env}/application.yml`만 포함되어 있어, `application-dev.yml` 또는 `application-window.yml`처럼 환경 접미사가 붙은 파일을 사용하는 프로젝트의 경우 포트를 읽지 못하고 기본 `config/application.yml`(8080)로 폴백되던 문제를 수정했습니다.
    - `config.profiles/{env}/application-{env}.yml` (yaml/properties 포함) 및 `config/{env}/application-{env}.yml`을 1순위 후보로 등록하여 프로젝트의 환경별 서비스 포트(예: 8082)를 정확하게 자동 추출하도록 개선했습니다 (Gradle & Maven 공통).

#### 4. 🌱 배포 패키지 내 `.env` 단일 진실 공급원(SSOT) 확립 및 Windows 서비스 제어 스크립트 강화

- **루트 `/.env` 단일 파일 관리**:
    - 설정 파일 중복으로 인한 운영 혼란(`docker/.env`와 `/.env` 간의 불일치)을 방지하기 위해 배포 패키지 루트에 **단 하나의 `.env` 파일만 생성 및 유지**하도록 정리했습니다.
- **Windows 서비스 제어 스크립트(`start.bat`, `stop.bat`, `status.bat`) 환경 연동**:
    - `bin/start.bat` 실행 시 루트의 `.env` 파일에서 `HTTP_PORT`를 최우선으로 로드하고, `docker compose --env-file "%ENV_FILE%"`로 명시 전달하여 실제 구동 포트(`http://localhost:8082`)가 콘솔 안내 메시지에 정확히 출력되도록 보정했습니다.
    - `stop.bat`, `status.bat` 역시 `--env-file` 옵션을 명시하여 환경 변수 누락 없이 안정적으로 Docker 컨테이너를 제어하도록 개선했습니다.

#### 5. 📦 전체 플러그인 메타데이터 및 문서 버전 동기화

- `distribution-gradle-plugin` (Gradle) & `distribution-maven-plugin` (Maven) 버전 `3.4.0` 갱신.
- 사용자 및 개발자 가이드(`README.md`, `README_EN.md`, `DEVELOPER_GUIDE.md`) 내 플러그인 의존성 설정 버전 `3.4.0` 반영.

---

## 🎯 [3.3.0] - 2026-10-12

> 🚀 **Minor Release** — 환경별 Docker 프로파일(`docker.profiles/{profile}/`) 디렉토리 감지 및 파일 오버레이 지원, `.env` 런타임 설정 4단계 우선순위 오버레이 및 누락 시 자동 생성 체계 확립, `initDocker` 실행 시 `.env.example` 및 환경별 샘플 동시 생성 지원, 배포 도움말(`distHelp` / `mvn distribution:help`) 가이드 개선, Windows 배치 스크립트(`.bat`) CRLF 줄바꿈 규격 및 다중 이미지 태깅 보강, Gradle과 Maven 플러그인 100% 동일 동작 완벽 동기화.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. 🐳 환경별 Docker 프로파일(`docker.profiles/{profile}/`) 디렉토리 자동 감지 및 패키징 오버레이 지원

- **환경별 Docker 설정 분리 지원**:
    - `docker.profiles/{profile}/` 디렉토리에 환경별 `Dockerfile-{profile}`, `docker-compose-{profile}.yml`, `.env-{profile}` 파일을 배치하면, 빌드 프로파일(`-Penv={env}` 또는 `-Denv={env}`)에 따라 파일명 접미사(`-{env}`)를 자동으로 제거하여 최종 패키지의 `docker/` 및 루트 경로에 오버레이 배포합니다.
- **`.env` 파일 4단계 우선순위 오버레이 및 누락 시 자동 생성 체계 동기화 (Gradle & Maven)**:
    - **1순위**: `docker.profiles/{env}/.env-{env}` (또는 `docker.profiles/{env}/.env`) [Docker 전용 1순위]
    - **2순위**: `config.profiles/{env}/.env-{env}` (또는 `config.profiles/{env}/.env`) [공통 프로파일 2순위]
    - **3순위**: 프로젝트 루트의 `.env` [기본 fallback 3순위]
    - **4순위**: 소스 상에 `.env`가 전혀 없는 경우, 플러그인이 `APP_UID`, `APP_GID`, `APP_NAME`, `HTTP_PORT`, `LOG_PATH`, `DOCKER_IMAGE`를 포함한 **표준 기본 `.env`를 배포 패키지 루트에 자동 생성**하여 포함.

#### 2. 🛠️ `initDocker` 유틸리티 기능 강화 (원클릭 환경 설정 샘플 생성)

- `initDeployScript`와 동일한 방식으로, `./gradlew initDocker` 또는 `mvn distribution:initDocker` 실행 시 다음 파일들이 함께 자동 생성됩니다:
    - `docker/Dockerfile` 및 `docker/docker-compose.yml` (배포 유형 맞춤형)
    - `docker/.env.example` (호스트 포트 토큰 치환 `@httpPort@` 적용된 환경변수 템플릿)
    - `docker.profiles/dev/.env-dev` 및 `docker.profiles/prod/.env-prod` (환경별 프로파일 디렉토리 및 기본 샘플 파일 자동 초기화, 기존 파일 보존)

#### 3. 📖 배포 도움말(`distHelp` & `mvn distribution:help`) 환경 설정 가이드 추가

- 콘솔 도움말에 **`[🌱 환경 설정 (.env) 파일 위치 및 우선순위 안내]`** 전용 섹션을 신설하여 개발자가 프로파일 디렉토리 구조 및 우선순위를 즉시 확인하고 구성할 수 있도록 개선.

#### 4. 🪟 Windows 환경 배치 스크립트(`.bat`) 안정성 및 호환성 강화

- **CRLF 줄바꿈 보장**:
    - Windows `cmd.exe`에서 다중 행 괄호 블록 파싱 오류를 원천 방지하도록 `.gitattributes` 및 패키징 시 CRLF(`\r\n`) 자동 정규화 적용.
- **다중 이미지 태깅 및 환경 파일 안전 전달 (`install_service.bat`)**:
    - `docker build` 시 `-t "%IMAGE_TAG%" -t "%APP_NAME%:latest"` 다중 태깅 적용.
    - `docker compose --env-file "%ENV_FILE%"` 플래그를 명시하여 `.env` 설정 안전 로드.

#### 5. 📦 전체 플러그인 메타데이터 및 문서 버전 동기화

- `distribution-gradle-plugin` (Gradle) & `distribution-maven-plugin` (Maven) 버전 `3.3.0` 갱신.
- 사용자 및 개발자 가이드(`README.md`, `README_EN.md`, `DEVELOPER_GUIDE.md`) 내 플러그인 의존성 설정 버전 `3.3.0` 반영.

---

## 🎯 [3.2.1] - 2026-10-08

> 🚀 **Patch Release** — 기존 서비스 감지 시 대화형 프롬프트(덮어쓰기 여부 확인 질의) 제거 및 동일 위치 자동 덮어쓰기 배포 지원, 런타임 엔진/로그 경로 자동 승계 강화, Windows 환경 기존 컨테이너 감지 및 자동 배포 안내 보강.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. ⚡ 기존 서비스 감지 시 대화형 프롬프트 제거 및 동일 위치 자동 배포 (`install_service.sh`)

- **원클릭 자동 덮어쓰기 배포 (Zero-Prompt Auto Redeploy)**:
    - 기존에 설치된 서비스(`systemd` 유닛 또는 `sysvinit`) 및 로그 경로(`.env`)가 감지되었을 때 표시되던 `read -p "❓ 기존 서비스 정보를 덮어 씌우시겠습니까? (Y/n): "` 대화형 질의를 제거했습니다.
    - 서비스가 이미 설치되어 있는 경우 사용자의 수동 입력 대기 없이 감지된 기존 설치 위치(`$PREVIOUS_INSTALL_LOC`)와 로그 경로(`$PREVIOUS_LOG_PATH`)를 즉시 승계(`OVERWRITE_EXISTING="Y"`)하여 동일한 위치에 바로 덮어쓰기 배포를 진행합니다.
- **배포 설정 및 런타임 엔진 스마트 자동 승계**:
    - **런타임 엔진(`select_runtime_engine`)**: 기존 배포 디렉토리의 구조(`webapps/`/`tomcat` vs `libs/`)를 분석하여 Standalone Apache Tomcat 또는 Spring Boot Executable JAR 방식을 자동으로 승계합니다.
    - **배포 방식(`select_deploy_mode`)**: 기존 설치 경로에 `docker-compose.yml`이 있으면 Docker 방식을, 실행 스크립트/JAR가 있으면 Legacy 방식을 자동 유지합니다.
    - **로그 경로(`prompt_log_path`)**: 기존 로그 경로를 그대로 유지하며, 누락 시에도 기본 로그 경로를 즉시 적용하여 사용자 입력을 요구하지 않습니다.
    - **Fallback 감지 분기 간소화**: `determine_install_dir` 및 `determine_docker_install_dir`의 보조 감지 로직에서도 재배포 확인 질의(`[Y/n]`)를 제거하고 감지된 위치를 즉시 적용합니다.

#### 2. 🪟 Windows 환경 기존 서비스 컨테이너 자동 감지 및 안내 보강 (`install_service.bat`)

- 기존에 실행 중이거나 생성된 Docker 서비스 컨테이너가 감지될 경우, 사용자 확인 대기 없이 기존 패키지 루트 위치에 자동으로 갱신(덮어쓰기) 배포가 진행되도록 안내 메시지 및 상태 점검을 보강했습니다.

#### 3. 📦 전체 플러그인 메타데이터 및 문서 버전 동기화

- `distribution-gradle-plugin` (Gradle) & `distribution-maven-plugin` (Maven) 버전 `3.2.1` 갱신.
- 사용자 및 개발자 가이드(`README.md`, `README_EN.md`, `DEVELOPER_GUIDE.md`) 내 플러그인 의존성 설정 버전 `3.2.1` 반영.

---

## 🎯 [3.2.0] - 2026-09-22

> 🚀 **Minor Release** — 일반 사용자 배포 모드(Non-root / User Mode) 기본화 및 시스템 모드 옵션(`--sudo`, `--root`, `-Psudo`, `-Dsudo`) 공식 지원, 기본 서비스 포트 `8443` 변경 및 Spring Boot 설정 스마트 포트 자동 감지, Maven 플러그인 파라미터 메타데이터 복구 및 `.env` 포트 방어 로직 강화. 보안 요구사항(최소 권한의 원칙: Least Privilege)에 맞추어 `sudo` 권한이 전혀 없는 일반 계정에서도 기본으로 안전하게 서비스를 배포·운영할 수 있도록 systemd 사용자 모드(`systemctl --user`) 데몬 등록, 엄격한 사전 유효성 검증(1024 미만 특권 포트 차단, 디렉토리 쓰기 권한 및 Docker 그룹 권한 검증), 사용자 crontab 등록, 재부팅 시 백그라운드 구동 유지를 위한 Linger 설정 점검 기능 탑재.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. 👤 일반 사용자 배포 모드(Non-root / User Mode) 기본화 & 시스템 모드 옵션화

- **최소 권한의 원칙(PoLP) 기본 적용**:
    - 별도 옵션 없이 실행 시 기본적으로 일반 사용자 권한(`$HOME/apps`, `$HOME/logs`, `~/.config/systemd/user/`)으로 안전하게 배포.
    - OS 전역 데몬 등록 및 `/opt` 배포가 필요한 경우 `--sudo`, `--root`, `-Psudo`, `-Dsudo` 옵션을 부여하여 시스템 모드로 전환 가능.
    - 기존 옵션(`--user`, `-Puser`, `-Duser`) 역시 호환성을 위해 유저 모드로 정상 처리.

#### 2. 🔌 기본 서비스 포트 8443 변경 및 설정 파일 스마트 자동 감지

- **기본 HTTP 서비스 포트 8443 통일**:
    - Linux 일반 사용자 모드의 비특권 포트(1024 이상) 바인딩 정책에 부합하도록 플러그인 기본 포트를 `8443`으로 표준화.
- **Spring Boot `server.port` 스마트 감지 (Fallback)**:
    - 사용자가 CLI 파라미터(`-Pport` / `-DhttpPort`)나 빌드 스크립트 설정을 생략한 경우, 플러그인이 프로젝트의 설정 파일(`config.profiles/${env}/application.yml`, `src/main/resources/application.yml` 등)에서 `server.port`를 자동으로 파싱하여 패키지 배너 및 토큰에 반영.
    - 설정 파일에 포트 지정이 없는 경우 기본값 `8443` 적용.

#### 3. 🐛 Maven 플러그인 메타데이터(`plugin.xml`) 파라미터 복구 및 0번 포트 버그 해결

- `distribution-maven-plugin`의 `package`, `packageJar`, `packageTomcat` 골(Goal)에서 누락되었던 `httpPort`(기본값: 8443), `os`, `tomcatVersion`, `type`, `dockerRegistry`, `dockerImageTag` 파라미터 매핑을 완벽히 복구.
- 파라미터 주입 누락으로 인해 `httpPort`가 primitive int 기본값 `0`으로 초기화되던 문제를 원천 해결.

#### 4. 🛡️ `install_service.sh` 환경변수(`.env`) 포트 생성 방어 로직 보강

- 배포 스크립트 실행 시 `.env` 파일의 `HTTP_PORT`가 `0` 또는 빈 값으로 기록되지 않도록, 호스트의 `config/application.yml` 파싱 및 8443 fallback 이중 안전장치 추가.

#### 5. 🔍 엄격한 사전 유효성 검증 (배포 전 안전 차단)

- **특권 포트(Privileged Port: 1~1023) 바인딩 차단**:
    - 1024 미만 포트 바인딩 시도 시 배포를 즉시 중단하고 1024 이상 포트 변경 또는 리버스 프록시 연동 가이드 제공.
- **설치 및 로그 경로 쓰기 권한 검증**:
    - 일반 사용자 기본 경로(`~/apps/<appName>`, `~/logs/<appName>`)를 지원하며, 대상 경로에 현재 사용자의 쓰기 권한이 없으면 즉시 중단.
- **Docker 데몬 제어 권한 검증**:
    - Docker 배포 모드 구동 시 현재 사용자가 sudo 없이 docker 명령어 실행 가능한지 검증하고, 권한 부족 시 `sudo usermod -aG docker $USER` 요청 가이드 출력.

#### 6. ⚙️ `systemd` 사용자 모드(`systemctl --user`) 기반 데몬 등록

- `~/.config/systemd/user/<appName>.service`에 서비스 유닛을 생성하고 `systemctl --user`로 데몬 제어.
- `chown` 명령어 호출을 안전하게 bypass 처리하여 불필요한 권한 오류 완전 방지.
- 시스템 전역 크론 대신 사용자 크론탭(`crontab`)에 자동 로그 정리 작업 등록.

#### 7. 💡 배포 완료 후 Linger 및 서비스 제어 안내 가이드 자동 출력

- 재부팅 후에도 백그라운드 구동 유지를 위한 `sudo loginctl enable-linger $USER` 설정 여부 자동 확인 및 미설정 시 가이드 카드 출력.
- `systemctl --user status|start|stop|restart` 및 로그 모니터링 명령어 가이드 제공.

#### 8. 🖥️ `initDeployScript` 현재 시스템 OS 자동 감지 및 필요 스크립트만 생성

- `initDeployScript` (Gradle / Maven 공통) 실행 시 현재 호스트 OS를 자동 감지하여 불필요한 스크립트 생성을 방지:
    - **Linux / macOS 환경**: `build_deploy.sh`만 생성하고 실행 권한(`0755`) 자동 부여 (`build_deploy.bat` 생성 방지)
    - **Windows 환경**: `build_deploy.bat`만 생성
    - **수동 오버라이드 지원**: 필요 시 `-Pos=all` (또는 `-Dos=all`) 옵션으로 두 스크립트 모두 생성 가능

---

## 🎯 [3.1.0] - 2026-09-21

> 🚀 **Minor Release** — Docker 배포 전략 2종(`packageDocker`, `packageDockerRemote`) 정식 플러그인 탑재 (Gradle & Maven 동시 지원), 오프라인/폐쇄망용 이미지 tar 추출 및 번들링 Zip 생성(`packageDocker`), 원격 레지스트리 Push 및 서버 배포 가이드 패키지 생성(`packageDockerRemote`), CLI/DSL 파라미터(`dockerRegistry`, `dockerImageTag`) 신설, 기존 `package` 패키징 체계 100% 호환 보장.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. 🐳 오프라인/폐쇄망용 Docker 패키징 태스크 공식 탑재 (`packageDocker`)

- **Strategy 1 (폐쇄망/오프라인 이미지 배포 표준화)**:
    - 인터넷 또는 Docker Registry 접근이 불가능한 폐쇄망 운영 환경을 위해, 로컬에서 이미지를 빌드한 뒤 `docker save`를 통해 `{appName}.tar`로 추출.
    - 추출된 이미지 tarball과 `docker/docker-compose.yml`, `config/`, `bin/`, `deploy/` 스크립트를 번들링하여 `{appName}-docker-{env}.zip` 단일 아카이브 생성.
    - 서버에서는 전송받은 zip을 해제하고 `sudo ./deploy/install_service.sh`만 실행하면, 내부에서 `docker load -i {appName}.tar`를 자동 수행하여 컨테이너 구동까지 원클릭 완료.
- **Gradle & Maven 동시 지원**:
    - Gradle: `./gradlew packageDocker -Penv=prod`
    - Maven: `mvn distribution:packageDocker -Denv=prod` (별칭: `package-docker`)

#### 2. ☁️ 원격 레지스트리 Push & 서버 배포 준비 태스크 공식 탑재 (`packageDockerRemote`)

- **Strategy 2 (표준 CI/CD 파이프라인 연동 지원)**:
    - Docker Hub, AWS ECR, 사내 Private Registry 등 원격 저장소를 사용하는 표준 CI/CD 환경 지원.
    - 이미지를 빌드하고 지정된 레지스트리로 즉시 `docker push` 수행.
    - **배포 산출물 경량화 및 최적화**: 빌드 완료 후 불필요한 `Dockerfile`, `dev/`, `prod/` 디렉토리를 배포 패키지에서 제외하고, 오직 필요한 `docker/docker-compose.yml` 및 `config/`, `bin/`, `deploy/` 스크립트만 `docker-dist/` 폴더에 깔끔하게 구성.
    - **원클릭 자동 설치 & 자동 Pull 연동**: `docker-dist`의 `install_service.sh`(및 `.bat`)가 전체 원격 이미지 태그를 자동 주입받아, 설치 실행 시 `docker pull`을 자동으로 처리하도록 개선.
    - **배포 모드 스마트 자동 감지**: `docker-compose.yml`이 존재하고 `libs/`가 없는 패키지인 경우 배포 방식(Legacy/Docker) 및 런타임 엔진(JAR/Tomcat) 선택 질의를 자동 생략하고 즉시 Docker 배포로 직행.
    - **URL 프로토콜 자동 정제**: `dockerRegistry` 파라미터에 `http://` 또는 `https://`가 포함되어도 자동으로 제거하여 Docker 태그 규격을 만족하도록 안전하게 정제.
    - 터미널 콘솔에 운영 서버 배포 단계(1. 파일 전송 ➡️ 2. 레지스트리 로그인 ➡️ 3. 자동 설치 및 pull) 가이드 박스를 시각적으로 자동 출력.
- **기존 호환성 보장**:
    - `dockerBuildRemote` 명령어 및 기존 스크립트와의 100% 하위 호환성을 위해 `dockerBuildRemote` 별칭(Alias) 태스크 동시 지원.
    - Gradle: `./gradlew packageDockerRemote -Penv=prod -PdockerRegistry=...` (또는 `./gradlew dockerBuildRemote`)
    - Maven: `mvn distribution:packageDockerRemote -Denv=prod -DdockerRegistry=...` (또는 `mvn distribution:docker-build-remote`)

#### 3. 🎛️ Docker 레지스트리 및 이미지 태그 제어 파라미터 신설

- **유연한 이미지 태깅 지원**:
    - **`dockerRegistry`**: 대상 원격 레지스트리 URL 지정 (CLI: `-PdockerRegistry=...` / `-DdockerRegistry=...`, DSL: `distribution { dockerRegistry = '...' }` / pom `<dockerRegistry>`).
    - **`dockerImageTag`**: 이미지 태그 지정 (기본값: 프로젝트 버전 `project.version`, CLI: `-PdockerImageTag=...` / `-DdockerImageTag=...`, DSL: `distribution { dockerImageTag = '...' }` / pom `<dockerImageTag>`).

#### 4. 🧹 사용자 경험 최적화 및 기존 패키징 호환성 유지

- **독립적인 `dockerBuild` 태스크 분리 배제**:
    - 사용자의 태스크 목록 혼선을 방지하기 위해 단독 `dockerBuild` 태스크는 노출하지 않고, `packageDocker` 및 `packageDockerRemote` 내부 로직으로 깔끔하게 캡슐화.
- **Gradle & Maven 콘솔 배너 및 가이드 포맷 100% 일치**:
    - 패키징 시작 배너(대상 프로젝트, 배포 유형, 활성 프로파일, 타겟 OS, HTTP 서비스 포트, 산출물 이름) 및 완료 배너, `DEPLOY-GUIDE.md`의 형식과 순서를 두 플러그인 간 완전 일치화.
- **기존 `package` 빌드 방식 100% 유지**:
    - 기존의 JAR/Tomcat 표준 배포 패키지(`package`, `packageJar`, `packageTomcat`, `deployService`, `deploy`) 로직은 일체 변경 없이 완전하게 유지.
- **도움말(`distHelp` / `help`) 안내 갱신**:
    - Gradle `./gradlew distHelp` 및 Maven `mvn distribution:help` 콘솔 가이드에 신규 Docker 명령어 섹션 및 옵션 안내 반영.

---

## 🎯 [3.0.0] - 2026-09-17

> 🚀 **Major Release** — Windows 환경(Windows 10/11, Workstation, Windows Server 전 에디션) 공식 지원 추가(방안 C: Docker Compose 컨테이너 배포 모드), Windows 네이티브 배치 스크립트 세트(`install_service.bat`, `uninstall_service.bat`, `start.bat`, `stop.bat`, `status.bat`) 신규 개발, Windows 원스탑 빌드/배포 스크립트(`build_deploy.bat`) 탑재, 배포 아카이브(`.dist.zip`) 내 Windows 스크립트 자동 번들링 및 `initDeployScript` 연동.

### ✨ 신규 기능 및 개선 사항 (Features & Improvements)

#### 1. 🪟 Windows 환경 공식 지원 (방안 C: Docker Compose 컨테이너 배포 표준화)

- **크로스 플랫폼 배포 체계 완성**:
    - 기존 Linux/macOS 중심 배포 체계에서 확장하여, **Windows 환경에서도 무설치 원스탑 배포가 가능하도록 지원**.
    - Windows 환경의 특성(Systemd 부재 및 서비스 제어 차이)에 맞추어 **방안 C (Docker Compose 기반 컨테이너 배포)를 표준 방식으로 채택**.
    - Windows 10/11 일반 데스크톱, Pro, Workstation 및 Windows Server 전 에디션에서 추가 런타임 없이 기본 지원.

#### 2. 🛠️ Windows 전용 네이티브 배치 스크립트(`.bat`) 세트 신규 탑재

- **배포 및 서비스 제어 스크립트 제공**:
    - `deploy/install_service.bat`:
        - Windows 환경 서비스 설치 및 배포 진입점.
        - `where docker` 및 `docker info`를 통한 Docker Desktop / 데몬 구동 여부 사전 자동 점검.
        - `docker compose` (v2) 및 `docker-compose` (v1) 자동 감지.
        - 로컬 이미지 아카이브 로드 또는 Dockerfile 빌드 후 백그라운드 컨테이너 구동 (`docker compose up -d`).
        - 콘솔 UTF-8 (`chcp 65001`) 지원으로 한글 깨짐 방지.
    - `deploy/uninstall_service.bat`:
        - 배포된 Docker 컨테이너 서비스 중지 및 제거 (`docker compose down`).
    - `bin/start.bat`, `bin/stop.bat`, `bin/status.bat`:
        - 배포 완료 후 컨테이너를 쉽게 시작, 중지, 상태 확인할 수 있는 라이프사이클 스크립트 제공.

#### 3. 🚀 Windows 루트 원스탑 빌드 및 배포 스크립트(`build_deploy.bat`) 신설

- **원클릭 자동화**:
    - Windows CMD 및 PowerShell 환경에서 `build_deploy.bat dev` 실행 시, [Git pull ➡️ Gradle/Maven 패키징 ➡️ 산출물 ZIP 자동 압축 해제 ➡️ deploy\install_service.bat 실행]까지 한 번에 완료.
    - `--no-pull`, `-Pport=...` 등 주요 빌드 옵션 지원.

#### 4. 📦 빌드 및 Gradle/Maven 배포 플러그인 동기화 & 타겟 OS 선택 지원

- **타겟 OS 선택 옵션 추가 (`-Pos` / `-Dos`, 기본값: `linux`)**:
    - 패키징 시 불필요한 OS 스크립트가 함께 묶이지 않도록 타겟 OS 필터링 옵션을 지원합니다.
    - 아무런 옵션도 지정하지 않은 경우 **기본값은 `linux`**가 적용되어 Windows 배치 스크립트(`.bat`)는 제외되고 리눅스 쉘 스크립트(`.sh`)만 깔끔하게 패키징됩니다.
    - `-Pos=windows` (또는 `-Dos=windows`): Windows 전용 패키징으로 리눅스 쉘 스크립트(`.sh`)를 제외하고 배치 스크립트(`.bat`)만 포함.
    - `-Pos=all` (또는 `-Dos=all`): 리눅스(`.sh`)와 윈도우(`.bat`) 스크립트를 모두 포함하는 크로스 플랫폼 패키징.
- **자동 토큰 치환**:
    - `@appName@`, `@dockerImage@`, `@httpPort@` 토큰 치환이 배치 스크립트(`.bat`)에도 자동 적용.
- **원스탑 배포 스크립트 초기화**:
    - Gradle/Maven 플러그인의 `initDeployScript` 태스크 실행 시 `build_deploy.sh`와 `build_deploy.bat`이 프로젝트 루트에 함께 생성되도록 개선.

---

## 🎯 [2.0.2] - 2026-09-16

> 🛠️ **Patch Release** — Docker 초기화(`initDocker`) 태스크 최적화(배포 유형별 전용 파일 생성 및 불필요한 샘플 중복 제거), 저장소 원본 Docker 고정 파일 정리(SSOT 확립), 배포 패키지(Zip) 내 템플릿 원본 파일 배제 필터링 적용, 외장 톰캣(Tomcat) SSL(HTTPS) 인증서 호스트 마운트 및 `server.xml` SSL 커넥터 가이드 탑재.

### ✨ 개선 사항 (Improvements)

#### 1. 🐳 `initDocker` 생성 로직 최적화 및 불필요한 샘플 생성 제거

- **선택된 배포 유형 전용 산출물 생성**:
    - `type=tomcat` 지정 시: `Dockerfile-tomcat` ➡️ `Dockerfile`, `docker-compose-tomcat.yml` ➡️ `docker-compose.yml`만 생성.
    - `type=jar` 지정 시: `Dockerfile-jar` ➡️ `Dockerfile`, `docker-compose-jar.yml` ➡️ `docker-compose.yml`만 생성.
- **불필요한 타 유형 샘플 파일 중복 생성 제거**:
    - 기존에 `-Ptype` 지정 여부와 상관없이 비교용 목적으로 함께 생성되던 `Dockerfile-jar`, `Dockerfile-tomcat`, `docker-compose-jar.yml`, `docker-compose-tomcat.yml` 개별 샘플 생성 로직을 제거하여, 선택한 유형의 2개 파일만 깔끔하게 생성되도록 개선.
- **Gradle & Maven 플러그인 및 루트 빌드 스크립트 대칭 반영**:
    - Gradle 플러그인(`initDocker`), Maven 플러그인(`mvn distribution:initDocker`), 루트 `build.gradle`의 `initDocker` 태스크 모두 동일한 방식으로 동작하도록 동기화.

#### 2. 🧹 Docker 단일 원본(SSOT) 확립 및 저장소 원본 고정 파일 정리

- **고정 JAR 기준 파일 삭제**:
    - 저장소 루트의 `docker/Dockerfile` 및 `docker/docker-compose.yml`을 삭제하여, 프로젝트 생성 시 엉뚱한 타입이 기본 적용되거나 타입 불일치가 발생하는 문제 원천 차단.
    - Docker 원본 템플릿의 단일 원본(SSOT)을 `Dockerfile-jar`, `Dockerfile-tomcat`, `docker-compose-jar.yml`, `docker-compose-tomcat.yml`로 일원화하고, `docker/Dockerfile`과 `docker/docker-compose.yml`은 프로젝트 초기화(`initDocker`) 시 생성되는 산출물로 정의.

#### 3. 📦 배포 패키징(Zip) 시 Docker 템플릿 원본 파일 제외 필터링 적용

- **패키지 오염 방지**:
    - `./gradlew package` 및 `mvn distribution:package` 실행 시, Zip 내 `docker/` 디렉토리에 원본 템플릿 파일(`*-jar*`, `*-tomcat*`)이 포함되지 않도록 제외(`exclude`) 필터 적용.
    - 최종 배포 Zip에는 실제 서버에서 구동에 필요한 `docker/Dockerfile` 및 `docker/docker-compose.yml`만 포함되도록 정제.

#### 4. 🔒 외장 톰캣(Tomcat) 배포 시 SSL(HTTPS) 인증서 호스트 마운트 및 설정 템플릿 추가

- **`docker-compose-tomcat.yml` SSL 인증서 볼륨 마운트 템플릿 추가**:
    - 호스트의 SSL 인증서 디렉토리(`${DEST_DIR}/ssl`)를 컨테이너 내부(`/usr/local/tomcat/ssl:ro`, 읽기 전용)로 마운트할 수 있는 주석 가이드 설정 탑재.
    - 별도 다중 포트 오픈 없이 단일 포트 매핑(`"${HTTP_PORT:-@httpPort@}:@httpPort@"`)으로 HTTP와 HTTPS를 일원화하여 유연하게 전환 및 운영 가능하도록 개선.
- **`server.xml` 표준 SSL 커넥터 템플릿 탑재 (방식 A & B 동시 제공)**:
    - **[방식 A] PEM 인증서 방식**: Let's Encrypt 등 `cert.pem`, `privkey.pem`, `chain.pem` 기반 설정 템플릿을 주석으로 제공.
    - **[방식 B] 키스토어 방식**: PKCS12(`.p12`) 또는 JKS(`.jks`) 기반 키스토어 설정 템플릿을 주석으로 제공.
    - SSL 적용 시 기본 HTTP 커넥터를 주석 처리하고 동일한 `@httpPort@`로 SSL 커넥터를 활성화할 수 있도록 상세 가이드 주석 명시.

#### 5. ⚙️ 서비스 설치 스크립트(`install_service.sh`) 런타임 엔진 자동 감지 시 대화형 프롬프트 생략

- **무인 자동화 편의성 향상**:
    - 패키지 내 `webapps/ROOT` 또는 `tomcat/` 디렉토리 감지 시 `tomcat` 엔진으로, `libs/` 디렉토리 감지 시 `jar` 엔진으로 사용자에게 묻지 않고 즉시 자동 진행하도록 개선.
    - 배포 유형이 모호하거나 자동 감지가 불가능한 경우에만 대화형 선택 프롬프트가 표시되도록 정밀화.

---

## 🎯 [2.0.1] - 2026-09-15

> 🛠️ **Patch Release** — 배포 유형별 Docker 템플릿 생성 및 비교 유틸리티(`initDocker`, `showDocker`) 추가, `build_deploy.sh` 파라미터 제어 및 도움말 탑재, Javadoc 경고 해결, Maven 디스크립터 완비, 미사용 K8s 리소스 정리.

### ✨ 개선 사항 (Improvements)

#### 1. 🐳 샘플 Dockerfile 생성 및 아키텍처 비교 유틸리티 탑재 (`initDocker` & `showDocker`)

- **배포 유형별 Dockerfile 자동 생성 (`initDocker`)**:
    - 프로젝트 설정(`packageType`) 또는 CLI 옵션(`-Ptype=jar|tomcat`)에 맞추어 최적화된 `Dockerfile` 및 `docker-compose.yml`을 프로젝트의 `docker/` 폴더에 즉시 자동 생성.
    - 배포 유형별 템플릿 파일명을 확장자 오인 방지 네이밍(`Dockerfile-jar`, `Dockerfile-tomcat`, `docker-compose-jar.yml`, `docker-compose-tomcat.yml`)으로 개편하여 동시 번들링 제공.
- **JAR vs Tomcat 컨테이너 아키텍처 비교 가이드 (`showDocker`)**:
    - 베이스 이미지, 빌드 산출물 위치, 컨테이너 파일 복사 경로, 엔트리포인트, 볼륨 마운트 구조의 차이점을 터미널 콘솔에 시각적인 표 형태로 즉시 비교 출력.
- **도움말 가이드 연동 및 양대 빌드 툴 100% 대칭 지원**:
    - Gradle `./gradlew distHelp` 및 Maven `mvn distribution:help` 도움말 목록에 Docker 유틸리티 명령어 안내 추가.
    - Maven 환경에서도 `mvn distribution:initDocker`, `mvn distribution:showDocker` Goal을 동일하게 지원.

#### 2. 🚀 `build_deploy.sh` 배포 자동화 스크립트 기능 강화

- **`-Ptype`, `-Pport` 파라미터 전달 지원**:
    - 외장 Tomcat 배포 및 커스텀 포트 지정 시 `./build_deploy.sh prod -Ptype=tomcat -Pport=8443` 형태로 파라미터를 직접 전달하여 패키징 및 배포할 수 있도록 개선.
    - Gradle `-P...` 옵션 및 Maven `-D...` 옵션 상호 자동 변환 및 패스스루(Pass-through) 지원.
- **대화형 도움말 (`--help`, `-h`, `help`) 추가**:
    - 스크립트 사용법, 배포 환경, 지원 파라미터, 다양한 실전 실행 예시를 터미널에서 즉시 확인할 수 있는 도움말 옵션 탑재.
- **`--no-pull` 플래그 지원**:
    - Git 저장소 환경에서 배포 전 `git pull` 단계를 건너뛰고 로컬 소스 기준으로 즉시 배포할 수 있는 옵션 추가.

#### 3. 🪶 Maven Plugin 디스크립터 (`plugin.xml`) 누락 보완 및 신규 Goal 완비

- `PackageJarMojo` (`packageJar`) 및 `PackageTomcatMojo` (`packageTomcat`) Mojo 정의를 `META-INF/maven/plugin.xml`에 추가하여 Maven 환경에서도 해당 Goal이 정상 인식 및 실행되도록 수정.
- 신규 `InitDockerMojo` (`initDocker`) 및 `ShowDockerMojo` (`showDocker`) 정의를 디스크립터에 완비하여 Maven CLI 환경 지원 강화.

#### 4. 🧹 미사용 Kubernetes (K8s) 리소스 및 빌드 태스크 정리

- 플랫폼 집중도 향상을 위해 현재 사용하지 않는 `./k8s` 디렉토리(`configmap.yaml`, `deployment.yaml`, `service.yaml`) 완전 삭제.
- 루트 `build.gradle`에서 `k8sBuild` 태스크 및 help 가이드 내 K8s 안내 문구 정리.
- `README.md` 및 `DEVELOPER_GUIDE.md` 문서 내 K8s 관련 섹션 및 다이어그램 정리.

#### 5. 📚 개발자 및 관리자 가이드 (`DEVELOPER_GUIDE.md`) 최신화 및 Javadoc 경고 해결

- **루트 환경 vs 개별 프로젝트 환경 실행 분리**: 루트 관리자 프로젝트의 `distHelp` 별칭 동작 원리와 플러그인이 적용된 하위 프로젝트의 가이드 출력 간 차이점을 명확히 정리.
- **Javadoc 경고 완전 해결 (Warning 0건)**: `DistributionPlugin` 기본 생성자에 한글 Javadoc 명세를 추가하여 빌드 및 배포(`javadoc`) 시 경고를 완전히 제거.
- **아키텍처 문서화 최신화**: 플랫폼 단일 원본(SSOT) 아키텍처 다이어그램에 신규 Docker 템플릿 반영, Tomcat 사전 조건 자동 검증기(`verifyTomcatPrerequisites`) 4단계 로직 상세화 및 GPG 서명 배포 가이드 보강.

---

## 🎯 [2.0.0] - 2026-09-15

> ⚠️ **Major Release** — 아키텍처 변경이 포함되어 있습니다. 이전 버전과의 호환성을 검토 후 적용하세요.

### 🆕 핵심 신기능: JAR/Tomcat 이중 배포 아키텍처

#### 📦 신규 배포 유형 선택 (packageType)

- **`packageType = 'jar'` (기본값)**: 기존 방식 유지. Spring Boot Executable JAR 패키지 생성.
- **`packageType = 'tomcat'` (신규)**: Standalone Apache Tomcat 11 외장 배포 지원.
    - WAR 파일을 자동으로 **Explode (압축 해제)**하여 `webapps/ROOT/` 구조로 패키징.
    - `tomcat/conf/server.xml`, `tomcat/conf/context.xml`, `tomcat/bin/setenv.sh` 등 Tomcat 설정 템플릿 자동 번들링.
    - Gradle: `distribution { packageType = 'tomcat' }` / Maven: `<packageType>tomcat</packageType>`

#### ⚡ 전용 태스크 / Goal 추가

| Gradle 태스크   | Maven Goal                   | 설명                           |
| --------------- | ---------------------------- | ------------------------------ |
| `packageJar`    | `distribution:packageJar`    | JAR 모드 패키지 생성 (고정)    |
| `packageTomcat` | `distribution:packageTomcat` | Tomcat 모드 패키지 생성 (고정) |
| `deployJar`     | —                            | JAR 모드 원스탑 배포           |
| `deployTomcat`  | —                            | Tomcat 모드 원스탑 배포        |

#### 🎛️ CLI 파라미터 지원 확대

- Gradle: `-Ptype=tomcat`, `-PpackageType=tomcat`, `-Pport=8443`, `-PtomcatVersion=11.0.15`
- Maven: `-Dtype=tomcat`, `-DpackageType=tomcat`, `-DhttpPort=8443`, `-DtomcatVersion=11.0.15`
- 빌드 DSL 설정과 CLI 옵션이 동시에 지원되며, CLI 옵션이 DSL 설정보다 우선 적용됩니다.

#### 🛡️ Tomcat 사전 조건 검증기 (`verifyTomcatPrerequisites`)

Tomcat 배포 모드 선택 시 빌드 시점에 자동으로 다음 4가지 조건을 검증합니다:

1. **`war` 플러그인/packaging 선언 여부** — 미선언 시 빌드 즉시 실패 + 해결 가이드 출력.
2. **`SpringBootServletInitializer` 상속 여부** — `@SpringBootApplication` 파일을 자동 스캔하여 `extends SpringBootServletInitializer` 누락 시 빌드 실패 + 해결 코드 예시 출력.
3. **`providedRuntime` / `provided` scope Tomcat 의존성 설정 권고** — 내장 톰캣과의 클래스로더 충돌 방지를 위한 설정 권고 경고 출력.
4. **`docker/Dockerfile` Tomcat ENTRYPOINT 점검** — `catalina.sh run` 설정 누락 시 경고 출력.

#### 🐱 Tomcat 설정 템플릿 번들링

`build_template/tomcat/` 디렉토리를 단일 원본(SSOT)으로 하는 Tomcat 설정 파일들이 플러그인에 내장됩니다:

- `tomcat/conf/server.xml` — 기본 포트 443 설정 포함
- `tomcat/conf/context.xml` — 세션 퍼시스턴스 비활성화
- `tomcat/conf/logging.properties` — 로그 설정
- `tomcat/bin/setenv.sh` — JVM 옵션 및 스프링 외부 설정 주입

#### 🚀 Legacy + Tomcat 배포 호스트 자동 구성 (`install_service.sh`)

Legacy 모드 + Tomcat 타입 선택 시 다음이 자동 실행됩니다:

- 호스트 Tomcat 자동 탐색 (`/usr/local/tomcat`, `/opt/tomcat`, `/opt/apache-tomcat-*` 등)
- 대화형 `CATALINA_HOME` 경로 입력 + `bin/catalina.sh` 유효성 검사
- 입력된 경로를 `.env` 파일과 Systemd 유닛 `[Service] Environment=` 섹션에 자동 주입
- CI/CD 무인 자동화: `--tomcat-home=`, `--catalina-home=`, `CATALINA_HOME=` 환경변수 지원

### ✨ 개선 사항

- **`distHelp` / `mvn distribution:help` 가이드 전면 개편**: 새로운 파라미터(-Penv, -Ptype, -Pport, -PtomcatVersion, DSL 설정) 설명 추가.
- **Gradle `packageTomcat` Implicit Dependency 버그 수정**: 동일 빌드 내에서 `packageTomcat`과 `packageJar`를 동시에 실행해도 Gradle 검증 오류가 발생하지 않도록 수정.
- **Maven 플러그인 구조 개선**: `DistributionMojo`를 상속하는 `PackageTomcatMojo`, `PackageJarMojo` 추가로 Maven 플러그인과 Gradle 플러그인의 명령어 체계 통일.
- **`.gitignore` 경로 패턴 수정**: `./bin/` → `/bin/` (루트 상대 경로로 정확히 매칭).

### 🔧 마이그레이션 가이드 (1.x → 2.0.0)

#### Gradle

```groovy
// build.gradle
plugins {
    id 'io.github.mj-youn.distribution' version '2.0.0'  // 버전 변경
}

distribution {
    packageType = 'jar'     // 신규 필드 (기본값: 'jar', 생략 가능)
    httpPort    = 8080      // 신규 필드 (기본값: 8080, 생략 가능)
    // Tomcat 배포 시:
    // packageType = 'tomcat'
    // tomcatVersion = '11.0.15'
}
```

#### Maven

```xml
<plugin>
    <groupId>io.github.mj-youn</groupId>
    <artifactId>distribution-maven-plugin</artifactId>
    <version>2.0.0</version>  <!-- 버전 변경 -->
    <configuration>
        <packageType>jar</packageType>   <!-- 신규 설정 (기본값: jar, 생략 가능) -->
        <httpPort>8080</httpPort>         <!-- 신규 설정 (기본값: 8080, 생략 가능) -->
    </configuration>
</plugin>
```

> [!NOTE]
> 기존 `./gradlew package -Penv=dev` / `mvn clean package -Denv=dev` 명령어는 하위 호환성이 유지됩니다.
> 기존 설정을 변경하지 않아도 1.x와 동일하게 JAR 배포로 동작합니다.

---

## 🚀 [1.2.2] - 2026-09-11

### ✨ 주요 개선 사항 (Features & Enhancements)

- **빌드 환경 호환성 개선 (Java Toolchain 제약 완화)**
    - Gradle 및 Maven 플러그인의 엄격한 Toolchain 탐색 제약을 완화하고 `sourceCompatibility / targetCompatibility = 17`로 설정.
    - 빌드 서버 환경의 다양한 JDK(Java 17, 21, 25 등)에서 충돌 없이 유연하게 컴파일 및 `publishToMavenLocal`을 수행할 수 있도록 개선.
- **플러그인 버전 업데이트 (v1.2.2)**
    - Gradle 및 Maven 배포 플러그인 전반의 최신 패치 버전 1.2.2 릴리즈.

---

## 🚀 [1.2.1] - 2026-09-11

### 🐛 버그 수정 및 안정화 (Bug Fixes & Improvements)

- **`install_service.sh` 배포 복사 및 권한 설정 보완**
    - 설정 디렉토리 복사 시 `.env` 등 숨김 설정 파일이 누락되지 않도록 `cp -rf "$PKG_ROOT/config/."` 복사 로직 개선.
    - 숨김 파일 포함 안전한 권한 부여를 위해 `find -type f / -type d` 방식으로 파일(644) 및 디렉토리(755) 권한 일괄 적용.
- **`start.sh` JVM 옵션(`JAVA_OPTS`) 파라미터 전달 순서 정상화**
    - `java -jar "$JAVA_OPTS"` 형태에서 `java "${JAVA_OPTS[@]}" -jar "$JAR_FILE"`로 수정하여 JVM 시스템 프로퍼티/옵션이 정상 적용되도록 개선.
- **플러그인 버전 업데이트 (v1.2.1)**
    - Gradle 및 Maven 배포 플러그인 전반의 최신 패치 버전 1.2.1 릴리즈.

---

## 🚀 [1.2.0] - 2026-09-11

### ✨ 주요 개선 사항 (Features & Enhancements)

- **Gradle Plugin Portal 배포 메타데이터 및 공개 저장소 표준화**
    - 플러그인 심사 요건에 맞추어 `website` 및 `vcsUrl` 메타데이터를 공식 GitHub 공개 저장소(`https://github.com/MJ-Youn/build-template`)로 표준화.
    - Gradle Plugin Portal(plugins.gradle.org) 공식 배포 및 소스코드/웹사이트 접근성 검증 보장.
- **플러그인 버전 업데이트 (v1.2.0)**
    - Gradle 및 Maven 배포 플러그인 전반의 최신 안정화 버전 1.2.0 릴리즈.

---

## 🚀 [1.1.7] - 2026-09-09

### ✨ 주요 개선 사항 (Features & Enhancements)

- **`build_deploy.sh` 원스탑 배포 파이프라인 구조 개선 (TTY & sudo 분리 실행)**
    - Gradle/Maven 내부 자식 프로세스에서 `sudo` 실행 시 발생하는 비터미널(Non-TTY) 제약(`sudo: a terminal is required to read the password`) 및 exit code 1 비정상 종료 문제 원천 해결.
    - **빌드(Build)**: 일반 유저 계정으로 안전하게 패키징(`clean package`)만 수행하여 빌드 캐시(`.gradle/`, `build/`) 권한 꼬임 방지.
    - **설치(Deploy)**: 압축 해제 후 쉘 스크립트가 사용자의 터미널(TTY) 세션에서 직접 `sudo ./deploy/install_service.sh`를 실행하여 sudo 암호 입력창 및 대화형 메뉴(Legacy/Docker 선택)가 완벽하게 동작하도록 개선.

---

## 🚀 [1.1.6] - 2026-09-09

### ✨ 주요 개선 사항 (Features & Enhancements)

- **원스탑 배포 시 `sudo` 권한 자동 승격 지원 (`deployService` / `distribution:deploy`)**
    - 일반 유저 계정으로 원스탑 배포 명령어 또는 `build_deploy.sh`를 실행할 때, 내부 `install_service.sh`가 루트 권한(`EUID == 0`) 부족으로 즉시 종료(`코드: 1`)되던 문제 해결.
    - Unix/Linux 환경에서 현재 실행 사용자가 root가 아닐 경우 자동으로 `sudo ./install_service.sh`로 승격하여 안전하게 서비스 설치/구동을 이어가도록 개선.
- **Maven 플러그인 기능 확장 및 안내 일관성 확보**
    - **`initDeployScript` Goal 신규 추가**: `mvn distribution:initDeployScript` 실행 시 프로젝트 루트에 배포 자동화 쉘 스크립트(`build_deploy.sh`) 자동 생성.
    - **`distHelp` Goal 신규 추가**: Gradle과 명령어 통일성을 위해 `mvn distribution:distHelp`를 `help` alias로 지원.
    - **도움말 가이드 서식 일치화**: Gradle(`distHelp`)과 Maven(`help`/`distHelp`)의 도움말 레이아웃, 항목 및 설명 문구를 100% 동일하게 통일.

---

## 🚀 [1.1.5] - 2026-09-07

### 🎨 UI/UX 개선 (Enhancements)

- **서비스 설치 프롬프트 UI/UX 및 출력 정렬 대폭 개선 (`install_service.sh`)**
    - 기존 서비스 감지 시 설치 위치와 로그 경로의 depth, 아이콘, 색상이 비대칭적이던 문제를 수정하여 동일한 들여쓰기와 정렬(`📍 설치 위치`, `📝 로그 경로`)로 통일.
    - 덮어쓰기 시 배포 방식 안내(`🐳 배포 방식 : 기존 방식(Docker) 유지`)의 시각적 일관성 확보 및 후속 설치 단계에서의 불필요한 위치/로그 중복 출력 메시지 정리.

---

## 🚀 [1.1.4] - 2026-09-07

### 🐛 버그 수정 (Bug Fixes)

- **배포 Zip 내 JAR 라이브러리 디렉토리 명칭 표준화 (`lib/` ➡️ `libs/`)**
    - Dockerfile(`COPY libs/ /app/libs/`) 및 `install_service.sh`와의 명칭 불일치로 인해 Docker 빌드 시 `COPY libs/ /app/libs/: "/libs" not found` 에러가 발생하던 결함 수정.
    - Gradle(`DistributionPlugin.java`) 및 Maven(`DistributionMojo.java`) 플러그인 모두 배포 아카이브 내 Jar 라이브러리 저장 경로를 `libs/`로 통일.
    - 서비스 설치 스크립트(`install_service.sh`)에서도 `libs/` 및 `lib/` 경로를 모두 지원하도록 폴백(Fallback) 방어 로직 보강.

---

## 🚀 [1.1.3] - 2026-09-07

### ✨ 주요 개선 사항 (Features & Enhancements)

- **유연한 추가 디렉토리 복제 설정 (`EXTRA_DIRS` / `extraDirs`)**
    - 특정 폴더명 하드코딩 없이, `.env` 파일의 `EXTRA_DIRS="flags data uploads"` 또는 빌드 설정(`<extraDirs>flags</extraDirs>`, `extraDirs = ['flags']`)을 통해 프로젝트 고유의 리소스 폴더를 배포 ZIP 루트에 자동 번들링.
    - 서비스 설치 스크립트(`install_service.sh`)에서도 `EXTRA_DIRS` 및 패키지 내 비표준 디렉토리를 감지하여 최종 서비스 설치 경로(`$DEST_DIR`)로 자동 복사 및 권한(`chown/chmod 755`) 부여.
- **`config/` 하위 디렉토리 재귀 복사 지원 (Maven 플러그인)**
    - Maven 플러그인(`DistributionMojo.java`)에서 `config/` 디렉토리 아래에 하위 디렉토리가 존재하는 경우(예: `config/sql/`, `config/rules/` 등), 누락 없이 트리 구조 전체를 재귀적으로 배포 ZIP에 포함하도록 수정.
- **`appName` 옵션 가이드 및 운영 주의 사항 추가**
    - 미설정 시 기본값(`artifactId` 또는 `rootProject.name`) 동작 원리 안내.
    - 리소스 명칭 정제(Systemd 서비스, `/log/{appName}`, Docker 태그 등)를 위한 권장 사용처 및 배포 후 명칭 변경 시 유의사항(중복 등록 방지) 문서화.

---

## 🚀 [1.1.2] - 2026-09-07

### ✨ 주요 개선 사항 (Features & Enhancements)

- **서비스 설치 스크립트 UX 전면 개선 (`install_service.sh`)**
    - **기존 설치 자동 감지 (`check_and_handle_existing_service`)**:
        - Systemd (`$APP_NAME.service`) 및 SysVinit (`/etc/init.d/$APP_NAME`)을 통해 기존 설치 경로와 기존 로그 경로(`.env`)를 자동으로 감지합니다.
    - **스마트 덮어쓰기 프롬프트**:
        - `기존 서비스 정보를 덮어 씌우시겠습니까? (Y/n)` 질의 추가 (Enter 입력 시 기본값 `Y` 적용).
    - **원클릭 덮어쓰기 (`Y` 선택 시)**:
        - 설치 위치, 재배포 확인, 로그 경로 입력, 배포 방식 선택 등 번거로운 추가 질의를 일체 건너뛰고 기존 설정을 승계하여 즉시 설치 및 재기동을 완료합니다.
    - **안전한 클린 설치 (`n` 선택 시)**:
        - 기존 경로의 `uninstall_service.sh`를 자동 호출하여 기존 서비스를 완전히 제거/정리한 후 신규 설치 단계로 진입합니다.
    - **주요 함수 분기 연동 및 주석 보강**:
        - `determine_install_dir`, `determine_docker_install_dir`, `prompt_log_path`, `select_deploy_mode`에 `OVERWRITE_EXISTING` 분기를 적용하고 상세 주석을 보강하였습니다.

---

## 🛠️ [1.1.1] - 2026-09-07

### ✨ 주요 개선 사항

- **범용 배포 스크립트 (`build_deploy.sh`) 연동 강화**
    - 플러그인이 적용된 프로젝트에서 `build_deploy.sh`가 빌드 툴(Gradle/Maven)을 자동 인식하여 플러그인의 `package` 및 `deploy` 태스크를 직접 호출하도록 연동 구조 개선.
    - 배포 아티팩트 번들링 시 `build_deploy.sh`를 배포 Zip 루트에 자동 포함하여 배포 환경에서도 편리하게 관리할 수 있도록 지원.

---

## 🌐 [1.1.0] - 2026-09-07

### ✨ 주요 개선 사항

- **Maven 빌드 툴 지원 확장 (`distribution-maven-plugin`)**
    - Gradle뿐만 아니라 Maven 프로젝트에서도 내장 스크립트 기반 배포 패키징을 사용할 수 있도록 Maven 플러그인 신규 개발 (`distribution:package`, `distribution:deploy`).
- **루트 멀티 프로젝트 통합 빌드 체계 구축**
    - `distribution-gradle-plugin`과 `distribution-maven-plugin`을 하나의 저장소에서 유기적으로 빌드 및 배포할 수 있도록 설정.
- **Docker 배포 모드 번들링 지원**
    - `Dockerfile`, `docker-compose.yml`, 멀티 환경 구성(`dev`/`prod`)을 플러그인 리소스에 내장하여 Docker 기반 배포 완전 지원.
- **환경 설정 표준화**
    - `.app-env.properties` 설정을 표준 `.env` 파일로 통합하여 Docker 및 Legacy 모드 간 일관된 환경 변수 관리 체계 마련.
- **개발자 가이드 문서화 (`DEVELOPER_GUIDE.md`)**
    - Gradle Plugin Portal 및 Maven Central 배포 절차, 서명(GPG), 버전 관리 가이드 추가.

---

## 🔧 [1.0.2] - 2026-09-07

### 🐛 버그 수정 및 안정화

- **Linux 서비스 등록 안정화**: Systemd Unit 및 SysVinit 서비스 등록 시 유저 권한(chmod/chown) 및 실행 경로 파싱 로직 안정화.
- **Java 툴체인 호환성 점검**: 최신 Java 25 툴체인 및 Java 17+ 런타임 호환성 테스트 통과.

---

## 🔧 [1.0.1] - 2026-09-07

### 🐛 버그 수정 및 안정화

- **프로세스 관리 스크립트 개선**: `start.sh`, `stop.sh`, `status.sh`의 PID 파일 체크 및 중복 실행 방지 로직 개선.
- **동적 로그 경로 처리**: `.env` 설정에 따른 로그 경로 동적 주입 및 로그 디렉토리 권한 자동 부여.

---

## 🎉 [1.0.0] - 2026-09-07

### ✨ 최초 릴리즈 (Initial Release)

- **Gradle 배포 패키징 플러그인(`io.github.mj-youn.distribution`) 최초 배포**
- **내장 스크립트 기반 배포 압축 파일(Zip) 생성**:
    - Spring Boot 표준 디렉토리 구조(`bin`, `libs`, `config`) 자동 구성.
    - 프로파일별 설정 파일 오버레이(Overlay) 및 Ant ReplaceTokens 기반 토큰 치환 기능 지원.
    - 기본 서비스 관리 스크립트 번들링 (`start.sh`, `stop.sh`, `status.sh`, `install_service.sh`, `uninstall_service.sh`).
    - 로컬 파일 오버라이드(`@Override`) 패턴 지원으로 프로젝트별 커스터마이징 허용.
