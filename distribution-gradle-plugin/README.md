# 🚀 Distribution Gradle Plugin (`io.github.mj-youn.distribution`)

> Spring Boot 애플리케이션의 표준 빌드/배포 구조(`deploy`, `bin`, `config`, `lib`, `docker`)를 손쉽게 패키징하고,  
> 배포 스크립트 템플릿 내장 및 프로젝트별 **파일 단위 @Override**를 완벽하게 지원하는 Gradle 커스텀 플러그인입니다. ✨

- **Author**: MJ Yun
- **JDK Requirement**: Java 25 이상
- **Plugin ID**: `io.github.mj-youn.distribution`
- **Gradle Plugin Portal**: [https://plugins.gradle.org/plugin/io.github.mj-youn.distribution](https://plugins.gradle.org/plugin/io.github.mj-youn.distribution)

---

## 🌟 핵심 기능

1. **배포 인프라 무설치 (Zero Configuration)**:
    - 각 프로젝트에 별도의 `scripts/`나 `docker/` 폴더를 복사해 둘 필요가 없습니다.
    - 플러그인 JAR 내부에 최신 배포 스크립트(`install_service.sh`, `start.sh`, `stop.sh`, `utils.sh` 등)와 `Dockerfile`이 기본 탑재되어 있습니다.
2. **파일 단위 @Override 메커니즘 (Java의 상속과 동일)**:
    - 특정 프로젝트에서 JVM 옵션이나 스크립트 내용 변경이 필요할 때, 프로젝트 로컬에 동일한 경로의 파일(예: `scripts/service/start.sh`)을 생성하기만 하면 **자동으로 로컬 파일이 우선 적용(@Override)**됩니다.
    - 수정하지 않은 나머지 스크립트들은 플러그인의 최신 템플릿 파일이 그대로 유지됩니다.
3. **환경별 프로파일 자동 매핑**:
    - `-Penv=dev`, `-Penv=prod` 옵션에 따라 `config.profiles/${env}` 디렉토리 내의 설정 파일을 패키지 `config/` 디렉토리에 파일명 접미사(`-dev` 등)를 자동 제거하여 표준 명칭으로 패키징합니다.
4. **환경별 빌드 및 표준 배포 패키징**:
    - 환경 지정 옵션(`-Penv=dev`, `-Penv=prod` 등)을 통해 환경별 프로파일 자동 오버레이.
    - `package`: 일반 서버(Legacy / Docker 선택 가능) 배포용 Zip 패키지 생성 (`JAR + Scripts + Config + Docker`).
    - 서버 배포 시 `deploy/install_service.sh`를 실행하여 Systemd/SysVinit 등록 또는 Docker 방식을 대화형으로 선택 설치.

---

## 📦 패키지 산출물 구조

생성된 아카이브(`.zip`)는 다음과 같은 표준 구조를 가집니다:

```text
📦 {project.name}-{project.version}.zip
├── 📁 deploy/                  # 서비스 등록 및 설치 스크립트
│   ├── install_service.sh
│   ├── uninstall_service.sh
│   └── utils.sh / bootstrap.sh
├── 📁 bin/                     # 서비스 기동/중지 스크립트
│   ├── start.sh
│   ├── stop.sh
│   ├── status.sh
│   ├── cron/crond
│   └── utils.sh / bootstrap.sh
├── 📁 config/                  # 애플리케이션 환경설정
│   ├── application.yml         (선택된 프로파일 파일이 표준 이름으로 치환됨)
│   └── log4j2.yml
├── 📁 lib/                     # Spring Boot 실행 JAR 파일
│   └── {project.name}-{project.version}.jar
└── 📁 docker/                  # 도커 빌드 및 컴포즈 파일
    ├── Dockerfile
    ├── docker-compose.yml
    ├── dev/
    └── prod/
```

---

## 💻 개별 프로젝트 적용 방법

개별 Spring Boot 프로젝트의 `build.gradle`에 플러그인을 선언합니다:

```groovy
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.2.0' // 또는 프로젝트 버전
    // ⭐️ 배포 플러그인 추가
    id 'io.github.mj-youn.distribution' version '1.2.1'
}

// (선택 사항) 앱 이름 커스텀 및 사용자 정의 토큰/추가 디렉토리 지정
// 💡 appName 미지정 시 rootProject.name이 기본 적용됩니다.
//    프로젝트 이름이 길거나 대문자가 포함된 경우(예: LGUplus-HDRMS-WEB) 소문자 서비스명(예: hdrms)으로 지정을 권장합니다.
distribution {
    appName = 'my-custom-service'
    token 'customKey', 'customValue'
    extraDirs = ['flags', 'data'] // (선택 사항) 배포 ZIP 루트로 함께 복제할 추가 디렉토리
}
```

### 🚀 빌드 및 배포 명령어 가이드

#### [기본 빌드 명령어]

```bash
./gradlew build           # 표준 빌드 수행 (JAR 빌드)
./gradlew clean           # 빌드 결과물 정리
```

#### [환경 지정 옵션 (-Penv=...)]

모든 배포 태스크에 환경(`dev`, `prod`, `local` 등)을 지정할 수 있습니다.  
지정 시 `config.profiles/{env}/` 내의 파일들이 패키지 `config/`로 오버레이되며, 파일명 접미사(`-dev` 등)가 자동 제거됩니다.

```bash
./gradlew package -Penv=dev
./gradlew package -Penv=prod
```

#### [배포 태스크 (Distribution Tasks)]

- 💡 **`distHelp` (배포 도움말 가이드 출력)**
    - 터미널에 환경 변수, 지원 태스크 목록 및 실행 예시 가이드를 출력합니다.

    ```bash
    ./gradlew distHelp
    # 또는 기본 도움말
    ./gradlew help
    ```

- 📦 **`package` (일반 서버 배포용 Zip 패키징)**
    - 일반 서버(Legacy / Docker 선택 가능) 배포용 Zip 생성
    - **산출물**: `build/distributions/{APP_NAME}-{version}.zip`
    - **포함 내용**: `JAR` + `Scripts (deploy/, bin/)` + `Config` + `Docker (Dockerfile, docker-compose.yml)`
    - 서버 배포 시 수동 압축 해제 후 `deploy/install_service.sh`를 실행하여 Legacy 또는 Docker 방식을 대화형으로 선택 설치할 수 있습니다.

    ```bash
    ./gradlew package -Penv=prod
    ```

- 🚀 **`deployService` (원스탑 빌드 & 자동 서비스 배포)**
    - 서버에서 소스 코드를 빌드하고, 산출물 Zip을 즉시 압축 해제한 뒤 `deploy/install_service.sh`를 자동 실행합니다.
    - 기존 `build_deploy.sh`의 기능을 플러그인 내장 태스크로 완전 자동화한 명령어입니다.
    ```bash
    ./gradlew deployService -Penv=dev
    ./gradlew deployService -Penv=prod
    ```

---

## 🛠️ 플러그인 개발 및 배포 가이드

### 1. 플러그인 로컬 빌드 및 로컬 저장소 배포 (테스트용)

프로젝트 루트 디렉토리에서 실행합니다:

```bash
# 로컬 컴파일 및 빌드 검증
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew :distribution-gradle-plugin:build

# 로컬 Maven 캐시(~/.m2/repository)에 배포하여 로컬 테스트에 사용
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew :distribution-gradle-plugin:publishToMavenLocal
```

### 2. Gradle Plugin Portal 공개 배포

1. `~/.gradle/gradle.properties` 파일에 발급받은 API 키 등록:
    ```properties
    gradle.publish.key=발급받은_KEY
    gradle.publish.secret=발급받은_SECRET
    ```
2. 프로젝트 루트 디렉토리에서 배포 명령어 실행:
    ```bash
    JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew :distribution-gradle-plugin:publishPlugins
    ```
