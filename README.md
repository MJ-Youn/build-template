# 🚀 Build Test Project

Spring Boot 기반의 빌드 및 배포 자동화 테스트 프로젝트입니다.
환경별 설정 분리, 자동화된 배포 스크립트, 시스템 서비스 등록 기능을 제공합니다.

## 📋 시스템 요구사항
- **JDK 21** 이상 ☕
- **Linux** 환경 (배포 대상) 🐧

## 🛠️ 빌드 (Build)

프로젝트 루트에서 다음 명령어를 실행하여 배포 패키지(`zip`)를 생성합니다.

### 1. 기본 빌드 (전체 설정 포함)
모든 환경(`dev`, `prod`)의 설정 파일이 포함된 패키지를 생성합니다.
```bash
./gradlew build
# 또는
./gradlew package
```
- **📦 결과물**: `build/dist/build_test-{version}.dist.zip`

### 2. 환경별 빌드 (Prod/Dev)
특정 환경의 설정 파일만 포함하여 패키징합니다.
```bash
# 🏭 운영 환경 (Prod)
./gradlew build -Penv=prod

# 🚧 개발 환경 (Dev)
./gradlew build -Penv=dev
```
- **📦 결과물**: `build/dist/build_test-{version}-{env}.dist.zip` (예: `build_test-0.0.1-SNAPSHOT-prod.dist.zip`)

## 🚀 배포 및 설치 (Deployment)

생성된 `zip` 파일을 서버로 전송한 후, 압축을 해제하고 설치 스크립트를 실행합니다.

### 1. 설치
`bin` 폴더 내의 `install_service.sh`를 **root** 권한으로 실행합니다.

```bash
sudo ./install_service.sh
```

- **📍 설치 위치 지정**: 스크립트 실행 시 설치할 경로를 물어봅니다. (기본값: `/opt/build_test`)
    - 🔄 기존에 설치된 서비스가 있다면 자동으로 감지하여 스마트 재배포(덮어쓰기)를 지원합니다.
- **⚙️ 서비스 등록**: `Systemd` 또는 `SysVinit`을 자동 감지하여 서비스를 등록하고 시작합니다.
- **📜 편의 스크립트**: 설치 시 `~/bin` 폴더에 로그 확인 및 상태 점검 스크립트가 자동 생성됩니다.

### 2. 설치 후 디렉토리 구조
설치 완료 시 지정된 경로(예: `/opt/build_test`)에 다음과 같이 구성됩니다.
```text
/opt/build_test/
 ├── bin/
 │   ├── start.sh          # ▶️ 서비스 시작
 │   ├── stop.sh           # ⏹️ 서비스 중지
 │   └── status.sh         # ℹ️ 상태 확인 (-Dapp.name 기반)
 ├── config/               # 🔧 설정 파일 (application.yml, log4j2.yml 등)
 ├── libs/                 # ☕ 실행 가능한 JAR 파일
 └── log/                  # 📝 로그 파일 저장소
```

## 🎮 운영 및 로그 (Operations)

### 서비스 제어
설치된 서비스는 `systemctl` 또는 `service` 명령어로 제어할 수 있습니다.

```bash
# Systemd
sudo systemctl start build_test
sudo systemctl stop build_test
sudo systemctl restart build_test
sudo systemctl status build_test  # 내부적으로 status.sh 실행

# SysVinit
sudo service build_test start
sudo service build_test status
```

### 📝 로그 확인
설치 시 사용자 홈 디렉토리(`~/bin`)에 생성된 편의 스크립트를 사용하세요.

```bash
# 어디서든 실행 가능 (PATH에 ~/bin이 등록된 경우)
tail-log-build_test.sh
```
- **로그 파일 위치**: `/opt/build_test/log/build_test.log`

### ℹ️ 상태 확인
로그 스크립트와 마찬가지로 어디서든 실행 가능합니다.

```bash
# 서비스 프로세스 실행 여부 확인
/opt/build_test/bin/status.sh
# 또는 서비스 명령어로 확인 (권장)
sudo service build_test status
```

## 💻 개발 (Development)
- **Log4j2 설정**: `config/log4j2.yml`에서 로그 설정을 관리합니다.
    - 파일명 패턴: `${sys:log.path}/${sys:app.name}.log`
- **APP_NAME 주입**: 빌드 시 `settings.gradle`의 프로젝트 이름이 스크립트에 자동 주입됩니다 (`@appName@`).
- **JVM 옵션**: `start.sh` 실행 시 `-Dapp.name` 및 `-Dlog.path`가 자동으로 설정됩니다.
