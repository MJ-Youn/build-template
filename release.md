# 📦 Release Notes

`io.github.mj-youn.distribution` (Gradle) & `distribution-maven-plugin` (Maven) 빌드/배포 플러그인의 버전별 릴리즈 노트입니다. ✨

## 🎯 [2.0.1] - 2026-09-15

> 🛠️ **Patch Release** — `build_deploy.sh` 파라미터 제어 및 도움말 기능 추가, Maven 디스크립터 누락 보완, 미사용 K8s 리소스 정리.

### ✨ 개선 사항 (Improvements)

#### 1. `build_deploy.sh` 배포 자동화 스크립트 기능 강화
- **`-Ptype`, `-Pport` 파라미터 전달 지원**:
  - 외장 Tomcat 배포 및 커스텀 포트 지정 시 `./build_deploy.sh prod -Ptype=tomcat -Pport=8443` 형태로 파라미터를 직접 전달하여 패키징 및 배포할 수 있도록 개선.
  - Gradle `-P...` 옵션 및 Maven `-D...` 옵션 상호 자동 변환 및 패스스루(Pass-through) 지원.
- **대화형 도움말 (`--help`, `-h`, `help`) 추가**:
  - 스크립트 사용법, 배포 환경, 지원 파라미터, 다양한 실전 실행 예시를 터미널에서 즉시 확인할 수 있는 도움말 옵션 탑재.
- **`--no-pull` 플래그 지원**:
  - Git 저장소 환경에서 배포 전 `git pull` 단계를 건너뛰고 로컬 소스 기준으로 즉시 배포할 수 있는 옵션 추가.

#### 2. Maven Plugin 디스크립터 (`plugin.xml`) 누락 보완
- `PackageJarMojo` (`packageJar`) 및 `PackageTomcatMojo` (`packageTomcat`) Mojo 정의를 `META-INF/maven/plugin.xml`에 추가하여 Maven 환경에서도 해당 Goal이 정상 인식 및 실행되도록 수정.

#### 3. 샘플 Dockerfile 생성 및 아키텍처 비교 기능 탑재 (`initDocker` & `showDocker`)
- **배포 유형별 Dockerfile 자동 생성 (`initDocker`)**:
  - 프로젝트 설정(`packageType`) 또는 `-Ptype=jar|tomcat` 옵션에 따라 최적화된 `Dockerfile` 및 `docker-compose.yml`을 프로젝트의 `docker/` 폴더에 즉시 자동 생성.
  - 참고용 개별 샘플(`Dockerfile-jar`, `Dockerfile-tomcat`, `docker-compose-jar.yml`, `docker-compose-tomcat.yml`) 동시 제공.
- **JAR vs Tomcat 컨테이너 아키텍처 비교 가이드 (`showDocker`)**:
  - Base Image, 빌드 산출물 위치, 컨테이너 복사 경로, 엔트리포인트, 볼륨 마운트 구조의 차이점을 터미널 콘솔에 시각적인 표 형태로 즉시 비교 출력.
- **`distHelp` / `help` 가이드 연동**:
  - Gradle `./gradlew distHelp` 및 Maven `mvn distribution:help` 도움말 목록에 Docker 유틸리티 명령어 안내 추가.
- **Maven Goal 대칭 지원**:
  - `mvn distribution:initDocker`, `mvn distribution:showDocker` Goal 동시 제공.

#### 4. 미사용 Kubernetes (K8s) 리소스 및 빌드 태스크 정리
- 플랫폼 집중도 향상을 위해 현재 사용하지 않는 `./k8s` 디렉토리(`configmap.yaml`, `deployment.yaml`, `service.yaml`) 완전 삭제.
- 루트 `build.gradle`에서 `k8sBuild` 태스크 및 help 가이드 내 K8s 안내 문구 정리.
- `README.md` 및 `DEVELOPER_GUIDE.md` 문서 내 K8s 관련 섹션 및 다이어그램 정리.

#### 5. 개발자 및 관리자 가이드 (`DEVELOPER_GUIDE.md`) 최신화 및 Javadoc 개선
- 플랫폼 단일 원본(SSOT) 아키텍처 및 Gradle ↔ Maven 1:1 대칭 대응표 보강.
- 루트 관리자 프로젝트 환경과 개별 프로젝트 플러그인 적용 환경의 명령어 차이점 명확화.
- `DistributionPlugin` 기본 생성자 Javadoc 명세 추가로 컴파일/배포 시 Javadoc 경고 완전 해결.
- Tomcat 사전 조건 자동 검증기(`verifyTomcatPrerequisites`) 4단계 로직 상세화.
- Sonatype Central Portal(Maven Central) 배포를 위한 GPG 서명(Signing) 설정 가이드 추가.

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

| Gradle 태스크 | Maven Goal | 설명 |
|---|---|---|
| `packageJar` | `distribution:packageJar` | JAR 모드 패키지 생성 (고정) |
| `packageTomcat` | `distribution:packageTomcat` | Tomcat 모드 패키지 생성 (고정) |
| `deployJar` | — | JAR 모드 원스탑 배포 |
| `deployTomcat` | — | Tomcat 모드 원스탑 배포 |

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
