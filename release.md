# 📦 Release Notes

`io.github.mj-youn.distribution` (Gradle) & `distribution-maven-plugin` (Maven) 빌드/배포 플러그인의 버전별 릴리즈 노트입니다. ✨

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
