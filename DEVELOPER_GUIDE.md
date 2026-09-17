# 🛠️ Spring Boot Build & Deploy 플랫폼 개발자 및 관리자 가이드 (Maintainer Guide)

> **이 문서는 `build_template` 플랫폼 자체를 유지보수, 개발, 테스트하고, Gradle Plugin Portal 및 Maven Central에 배포(Publish)하는 개발자/관리자를 위한 가이드입니다.** ✨  
> _(일반 Spring Boot 애플리케이션 개발자는 [**사용자 메인 README**](README.md)를 참고하세요.)_

---

## 🏗️ 1. 플랫폼 아키텍처 및 설계 로직

이 저장소는 **Gradle 플러그인**과 **Maven 플러그인**을 한 곳에서 개발 및 관리하는 멀티 모듈 구조를 채택하고 있습니다.

```text
build_template (루트 / SSOT)
├── 📁 scripts/                  # ⭐️ 유일한 마스터 스크립트 원본 (SSOT)
│   ├── deploy/                 # install_service.sh, uninstall_service.sh, install_service.bat, uninstall_service.bat
│   ├── service/                # start.sh, stop.sh, status.sh, start.bat, stop.bat, status.bat, cron/
│   └── common/                 # bootstrap.sh, utils.sh, run_bash_tests.sh
├── 📁 docker/                   # ⭐️ 유일한 마스터 Docker 원본 (SSOT)
│   ├── Dockerfile              # 기본 활성 Dockerfile (JAR 기반 기본값)
│   ├── Dockerfile-jar          # 📦 JAR 배포 전용 Dockerfile 템플릿
│   ├── Dockerfile-tomcat       # 🐱 Apache Tomcat 배포 전용 Dockerfile 템플릿
│   ├── docker-compose.yml      # 기본 활성 docker-compose.yml
│   ├── docker-compose-jar.yml  # JAR 배포 전용 docker-compose
│   ├── docker-compose-tomcat.yml # Tomcat 배포 전용 docker-compose
│   ├── dev/
│   └── prod/
├── 📁 tomcat/                   # ⭐️ 유일한 마스터 Tomcat 설정 원본 (SSOT, v2.0.0 신규)
│   ├── bin/setenv.sh           # JVM 옵션 및 스프링 외부 설정 주입
│   └── conf/                   # server.xml, context.xml, logging.properties
├── 📁 distribution-gradle-plugin/ # 🐘 Gradle 배포 플러그인 모듈
│   ├── src/main/java/io/github/mj_youn/plugin/
│   │   ├── DistributionPlugin.java     # 플러그인 엔트리포인트 및 태스크 등록
│   │   └── DistributionExtension.java  # distribution { ... } DSL 확장 모델
│   └── build.gradle                    # Plugin Portal 배포 설정
├── 📁 distribution-maven-plugin/  # 🪶 Maven 배포 플러그인 모듈
│   ├── src/main/java/io/github/mj_youn/plugin/
│   │   ├── DistributionMojo.java       # package goal (JAR/Tomcat 공통)
│   │   ├── PackageJarMojo.java         # packageJar goal (JAR 전용 고정)
│   │   ├── PackageTomcatMojo.java      # packageTomcat goal (Tomcat 전용 고정)
│   │   ├── DeployMojo.java             # deploy goal (원스탑 자동 배포)
│   │   ├── HelpMojo.java               # help goal (배포 가이드 출력)
│   │   ├── DistHelpMojo.java           # distHelp goal (help alias)
│   │   ├── InitDeployScriptMojo.java   # initDeployScript goal (build_deploy.sh 및 build_deploy.bat 생성)
│   │   ├── InitDockerMojo.java         # initDocker goal (Dockerfile/compose 자동 생성)
│   │   └── ShowDockerMojo.java         # showDocker goal (JAR vs Tomcat 비교 가이드)
│   ├── src/main/resources/META-INF/maven/plugin.xml # Maven 플러그인 디스크립터
│   └── build.gradle                    # Sonatype Central Portal 배포 및 GPG 서명 설정
├── 📄 build_deploy.sh           # ⭐️ 원클릭 로컬/원격 자동 빌드/배포 스크립트 (Linux/macOS)
├── 📄 build_deploy.bat          # ⭐️ 원클릭 로컬 자동 빌드/배포 스크립트 (Windows 전용)
├── 📁 config.profiles/          # 환경별(dev, prod 등) 외부 설정 파일 원본
├── build.gradle                 # 루트 빌드 스크립트 (원클릭 동시 배포 및 레거시 데모 태스크)
└── settings.gradle              # 서브모듈 선언 (rootProject.name = 'build_test')
```

---

### 🔄 단일 원본(SSOT) 자동 동기화 원리

- 배포 스크립트, Docker 템플릿, Tomcat 설정 파일, `build_deploy.sh`의 소스는 오직 루트 디렉토리(`/scripts`, `/docker`, `/tomcat`, `/build_deploy.sh`)에만 존재합니다.
- 각 서브모듈의 `build.gradle`에 정의된 `processResources` 태스크가 플러그인 빌드 시점에 루트의 마스터 자원들을 플러그인 JAR의 `resources/template/` 내부로 자동 복사합니다:
    - `scripts/` ➡️ `template/scripts/`
    - `docker/` ➡️ `template/docker/`
    - `tomcat/` ➡️ `template/tomcat/`
    - `build_deploy.sh` ➡️ `template/build_deploy.sh`
- 빌드 시 `template-manifest.txt` 파일 목록이 자동 생성되어 런타임에 JAR 내부의 모든 리소스가 누락 없이 대상 프로젝트에 정확하게 추출 및 번들링됩니다.
- 따라서 스크립트나 설정을 개선할 때 루트의 파일 하나만 수정하면 **Gradle 플러그인과 Maven 플러그인 모두에 100% 동시에 최신 코드가 반영**됩니다.

---

### ⚔️ Gradle 태스크 ↔ Maven Goal 1:1 완벽 대칭 대응표

`distribution` 플랫폼은 빌드 도구(Gradle / Maven)와 무관하게 완전히 동일한 기능과 배포 패키지 구조를 보장합니다:

| 기능 설명              | 🐘 Gradle 플러그인 태스크    | 🪶 Maven 플러그인 Goal                         | 비고                                          |
| :--------------------- | :--------------------------- | :--------------------------------------------- | :-------------------------------------------- |
| **통합 패키징**        | `./gradlew package`          | `mvn distribution:package`                     | DSL/CLI 설정에 따라 JAR 또는 Tomcat 패키징    |
| **JAR 전용 패키징**    | `./gradlew packageJar`       | `mvn distribution:packageJar`                  | Executable JAR 기반 Zip 생성 (고정)           |
| **Tomcat 전용 패키징** | `./gradlew packageTomcat`    | `mvn distribution:packageTomcat`               | Standalone Tomcat 11 기반 Zip 생성 (고정)     |
| **원스탑 서비스 배포** | `./gradlew deployService`    | `mvn distribution:deploy`                      | 빌드 ➡️ 압축해제 ➡️ `install_service.sh` 실행 |
| **JAR 원스탑 배포**    | `./gradlew deployJar`        | `mvn distribution:deploy -DpackageType=jar`    | JAR 기반 원스탑 배포                          |
| **Tomcat 원스탑 배포** | `./gradlew deployTomcat`     | `mvn distribution:deploy -DpackageType=tomcat` | Tomcat 기반 원스탑 배포                       |
| **배포 가이드 출력**   | `./gradlew distHelp`         | `mvn distribution:help` (또는 `distHelp`)      | 명령어 및 옵션 도움말 출력                    |
| **배포 스크립트 생성** | `./gradlew initDeployScript` | `mvn distribution:initDeployScript`            | 루트에 `build_deploy.sh` 자동 생성            |

---

### ⚙️ Maven Plugin 디스크립터 (`plugin.xml`) 구성

Maven 플러그인은 컴파일 시점에 `META-INF/maven/plugin.xml`을 참조하여 Goal과 매개변수를 바인딩합니다:

| Goal               | Mojo 구현 클래스       | 파라미터 구성                                                                                                   |
| :----------------- | :--------------------- | :-------------------------------------------------------------------------------------------------------------- |
| `package`          | `DistributionMojo`     | `project`, `appName`, `env`, `packageType`, `type`, `httpPort`, `tomcatVersion`, `outputDirectory`, `extraDirs` |
| `packageJar`       | `PackageJarMojo`       | 상동 (`packageType=jar` 고정)                                                                                   |
| `packageTomcat`    | `PackageTomcatMojo`    | 상동 (`packageType=tomcat` 고정)                                                                                |
| `deploy`           | `DeployMojo`           | `project`, `appName`, `env`, `outputDirectory`                                                                  |
| `help`             | `HelpMojo`             | `requiresProject = false` (프로젝트 없이 단독 실행 가능)                                                        |
| `distHelp`         | `DistHelpMojo`         | `requiresProject = false` (`help` 단축 별칭)                                                                    |
| `initDeployScript` | `InitDeployScriptMojo` | `basedir`                                                                                                       |

---

### 🎛️ DSL 파라미터 및 CLI 오버라이드 매핑

플러그인 설정은 빌드 스크립트 DSL과 CLI 실행 파라미터 양쪽 모두에서 제어할 수 있습니다:

| 속성명            | 설명                        | Gradle DSL              | Maven pom.xml                        | CLI 파라미터 (우선순위 높음)                                              | 기본값                       |
| :---------------- | :-------------------------- | :---------------------- | :----------------------------------- | :------------------------------------------------------------------------ | :--------------------------- |
| **앱 이름**       | 패키지/스크립트 내 서비스명 | `appName = '...'`       | `<appName>...</appName>`             | `-PappName=...` / `-DappName=...`                                         | 프로젝트 이름 (`artifactId`) |
| **배포 유형**     | 기본 패키징 방식            | `packageType = '...'`   | `<packageType>...</packageType>`     | `-Ptype=...` / `-Dtype=...`<br/>`-PpackageType=...` / `-DpackageType=...` | `jar`                        |
| **배포 타겟 OS**  | 패키징 대상 OS 스크립트 필터링 | `os = 'linux'`          | `<os>linux</os>`                     | `-Pos=linux\|windows\|all`<br/>`-Dos=linux\|windows\|all`                  | `linux`                      |
| **배포 환경**     | 활성 프로파일               | -                       | `<env>...</env>`                     | `-Penv=dev\|prod\|local` / `-Denv=...`                                    | `dev`                        |
| **HTTP 포트**     | 서비스 포트                 | `httpPort = 8080`       | `<httpPort>8080</httpPort>`          | `-Pport=...` / `-PhttpPort=...`<br/>`-DhttpPort=...`                      | `8080`                       |
| **Tomcat 버전**   | 외장 톰캣 버전              | `tomcatVersion = '...'` | `<tomcatVersion>...</tomcatVersion>` | `-PtomcatVersion=...` / `-DtomcatVersion=...`                             | `11.0.15`                    |
| **추가 디렉토리** | 패키지 루트 포함 폴더       | `extraDirs = ['...']`   | `<extraDirs>...</extraDirs>`         | `-DextraDirs="..."`                                                       | 없음                         |

#### 💡 `.env` 파일의 `EXTRA_DIRS` 자동 감지 및 패키징

- 개별 프로젝트의 `.env` 파일(`config.profiles/${env}/.env`, `.env`, `scripts/service/.env`)에 `EXTRA_DIRS="flags,data,custom"` 형식으로 정의되어 있을 경우, 플러그인이 이를 **자동으로 파싱하여 배포 Zip 루트에 포함**합니다. 별도의 빌드 스크립트 수정이 필요 없습니다.

---

### 🛡️ Tomcat 모드 사전 조건 자동 검증기 (`verifyTomcatPrerequisites`)

외장 Apache Tomcat 11 배포(`packageTomcat` 또는 `packageType=tomcat`) 실행 시, 런타임 오류를 방지하기 위해 다음 4가지 조건을 엄격하게 사전 검증합니다:

1. **WAR 플러그인 필수 검증**:
    - Gradle: `plugins { id 'war' }` 선언 여부 확인 (미선언 시 빌드 즉시 중단)
    - Maven: `<packaging>war</packaging>` 선언 여부 확인
2. **`SpringBootServletInitializer` 상속 검증**:
    - `src/main/java` 내 `@SpringBootApplication` 클래스가 `SpringBootServletInitializer`를 `extends`하고 `configure()` 메서드를 오버라이드했는지 소스 코드 단위로 검증 (미충족 시 가이드 예시 코드와 함께 빌드 즉시 중단)
3. **`providedRuntime` 의존성 충돌 방지 권고**:
    - 외장 톰캣과 스프링 부트 내장 톰캣의 클래스로더 충돌을 방지하기 위해 `providedRuntime 'org.springframework.boot:spring-boot-starter-tomcat'` 선언 여부를 확인하고 경고/안내 출력
4. **`docker/Dockerfile` 톰캣 환경 점검 권고**:
    - 로컬 `docker/Dockerfile`에 Tomcat 베이스 이미지 또는 `catalina.sh` 실행 설정이 포함되어 있는지 점검

---

## 🧪 2. 로컬 빌드 및 테스트 가이드

### 사전 환경 조건

- **JDK Requirement**: **Java 25** 이상
    - Gradle 및 Maven 실행 환경에서 시스템 기본 자바가 8/17/21인 경우 `UnsupportedClassVersionError` 또는 툴체인 불일치가 발생할 수 있으므로 항상 Java 25 `JAVA_HOME`을 지정하여 실행합니다.

```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home
```

---

### ⚠️ [중요] 루트 프로젝트(플러그인 개발자) vs 개별 프로젝트(사용자) 실행 환경 구분

이 저장소는 **플러그인 자체를 개발/유지보수하는 저장소(멀티모듈)**이므로, 루트 디렉토리에서 실행하는 명령어와 플러그인을 적용한 개별 프로젝트에서 실행하는 명령어가 명확히 다릅니다:

#### ① 루트 저장소(`build_template/`) 개발자/관리자 명령어

루트 디렉토리에서는 플러그인 로컬 빌드/설치, 테스트, 그리고 공식 저장소 퍼블릭 배포를 수행합니다:

```bash
# 1. 플러그인 로컬 빌드 및 로컬 Maven 캐시(~/.m2/repository)에 설치 (로컬 테스트 전 필수)
./gradlew :distribution-gradle-plugin:publishToMavenLocal
./gradlew :distribution-maven-plugin:publishToMavenLocal

# 2. 공식 퍼블릭 저장소 원클릭 동시 배포 (Gradle Plugin Portal + Sonatype Central Portal)
./gradlew publishAllPlugins

# (참고) 루트 데모 프로젝트 빌드 가이드 확인
# ※ 루트의 distHelp는 개발 편의를 위해 루트 help 태스크로 연결된 '별칭(Alias)'입니다.
./gradlew help       # (또는 ./gradlew distHelp)
```

#### ② 플러그인이 적용된 개별 Spring Boot 프로젝트 사용자 명령어

`plugins { id 'io.github.mj-youn.distribution' version '3.0.0' }`를 적용한 실제 프로젝트에서 실행하는 명령어:

```bash
# 🐘 Gradle 환경
./gradlew distHelp                # 배포 플러그인 가이드 출력
./gradlew packageJar -Penv=dev    # JAR 배포 Zip 생성
./gradlew packageTomcat -Penv=dev # Tomcat 배포 Zip 생성 (webapps/ROOT 포함)
./gradlew deployJar -Penv=dev     # 원스탑 JAR 배포 및 구동
./gradlew initDeployScript        # build_deploy.sh 및 build_deploy.bat 자동 생성
./gradlew initDocker              # 배포 유형에 맞는 Dockerfile & docker-compose 자동 생성
./gradlew initDocker -Ptype=tomcat # Tomcat 전용 Dockerfile 생성
./gradlew showDocker              # 🐳 JAR vs Tomcat Dockerfile 아키텍처 비교 가이드 출력

# 🪶 Maven 환경
mvn distribution:help             # 배포 플러그인 가이드 출력 (또는 distHelp)
mvn distribution:packageJar -Denv=dev
mvn distribution:packageTomcat -Denv=dev
mvn distribution:deploy -Denv=dev
mvn distribution:initDeployScript
mvn distribution:initDocker -Dtype=tomcat
mvn distribution:showDocker
```

---

### 1) 로컬 샘플 프로젝트에서 플러그인 동작 검증 시나리오

로컬 캐시에 설치된 플러그인을 독립된 샘플 프로젝트에서 테스트합니다:

1. **Gradle JAR 패키징 & 배포**:
    - `./gradlew packageJar -Penv=dev` ➡️ `build/dist/{APP_NAME}-{version}-dev.dist.zip` 생성 확인
    - Zip 내부에 `libs/*.jar`, `bin/`, `deploy/`, `config/`, `docker/` 구조 검증
2. **Gradle Standalone Tomcat 패키징 & 검증**:
    - `./gradlew packageTomcat -Penv=dev` ➡️ Zip 내부에 `webapps/ROOT/` (Exploded WAR), `tomcat/conf/`, `tomcat/bin/setenv.sh` 포함 여부 확인
    - `Application.java`의 `SpringBootServletInitializer` 상속을 제거했을 때 `verifyTomcatPrerequisites`가 빌드를 정상 차단하고 해결책을 제시하는지 확인
3. **Maven 플러그인 검증**:
    - `mvn distribution:packageJar -Denv=dev`
    - `mvn distribution:packageTomcat -Denv=dev`
4. **파일 단위 @Override 테스트**:
    - 프로젝트 로컬에 `scripts/service/start.sh` 또는 `tomcat/conf/server.xml`을 생성하여 특정 내용을 수정한 뒤 패키징 시 Zip 내에 커스텀 파일이 우선 적용되는지 확인
5. **CLI 오버라이드 테스트**:
    - `./gradlew package -Ptype=tomcat -Penv=dev` 실행 시 DSL 설정(`packageType = 'jar'`)을 무시하고 Tomcat 패키징이 수행되는지 확인
6. **`initDeployScript` 테스트**:
    - `./gradlew initDeployScript` 실행 후 루트에 실행 권한(`0755`)을 가진 `build_deploy.sh`가 올바르게 생성되는지 확인

---

## 🚀 3. 공식 저장소 릴리즈 및 원클릭 동시 배포

### 1) 사전 배포 인증 설정 (`~/.gradle/gradle.properties`)

배포를 진행하기 전에 개발자 PC의 `~/.gradle/gradle.properties` 파일에 아래 인증 정보가 모두 등록되어 있어야 합니다:

#### ① Gradle Plugin Portal 인증키

```properties
gradle.publish.key=발급받은_GRADLE_PORTAL_KEY
gradle.publish.secret=발급받은_GRADLE_PORTAL_SECRET
```

> [Gradle Plugin Portal 계정 페이지](https://plugins.gradle.org/)의 "API Keys" 메뉴에서 생성합니다.

#### ② Maven Central (Sonatype Central Portal) 토큰

```properties
centralUsername=발급받은_CENTRAL_PORTAL_TOKEN_USERNAME
centralPassword=발급받은_CENTRAL_PORTAL_TOKEN_PASSWORD
```

> [Sonatype Central Portal](https://central.sonatype.com/)의 "Account" ➡️ "Generate User Token"에서 생성합니다.

#### ③ GPG Signing (서명) 키 설정 ⭐️ (Maven Central 필수)

Maven Central에 배포되는 모든 산출물(`.jar`, `.pom`, `.module`)은 **GPG PGP 서명**이 필수입니다:

```properties
# 인메모리 PGP 서명 키 사용 시 (권장)
signingKey=-----BEGIN PGP PRIVATE KEY BLOCK-----\\n...\\n-----END PGP PRIVATE KEY BLOCK-----
signingPassword=GPG_개인키_비밀번호
```

> _또는 로컬 시스템에 `gpg` CLI와 키링이 구성되어 있는 경우 Gradle이 자동으로 로컬 GPG 에이전트를 호출하여 서명합니다._

---

### 2) 🌐 퍼블릭 공식 배포 명령어 가이드

저장소 루트 디렉토리에서 아래 명령을 통해 개별 배포 또는 원클릭 동시 배포를 수행할 수 있습니다:

#### ① Gradle 플러그인 배포 (`Gradle Plugin Portal`)

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew publishGradlePlugins
```

- **저장소**: [Gradle Plugin Portal (io.github.mj-youn.distribution)](https://plugins.gradle.org/plugin/io.github.mj-youn.distribution)

#### ② Maven 플러그인 배포 (`Sonatype Central Portal`)

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew publishMavenPlugins
```

- **저장소**: [Sonatype Central Portal Deployments](https://central.sonatype.com/publishing/deployments)

#### ③ 두 플러그인 원클릭 동시 배포 (One-Click Publish All) 🚀

```bash
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew publishAllPlugins
```

---

## 📌 버전 업데이트 정책 및 체크리스트

플러그인 기능 추가나 스크립트 수정으로 신규 버전을 릴리즈할 때는 다음 5개 파일의 버전을 일치시켜 함께 갱신합니다:

- [ ] `distribution-gradle-plugin/build.gradle` (`version = 'x.y.z'`)
- [ ] `distribution-maven-plugin/build.gradle` (`version = 'x.y.z'`)
- [ ] `distribution-maven-plugin/src/main/resources/META-INF/maven/plugin.xml` (`<version>x.y.z</version>`)
- [ ] 문서 내 버전 표기 최신화:
    - `README.md`
    - `README_EN.md`
    - `distribution-gradle-plugin/README.md`
    - `distribution-maven-plugin/README.md`
- [ ] `release.md` — 변경 사항 릴리즈 노트 작성

> 💡 **스크립트/설정 파일 변경 시**: `scripts/`, `docker/`, `tomcat/`, `build_deploy.sh` 하위의 마스터 파일만 수정하면 두 플러그인 모두에 자동 반영됩니다 (별도 복사 불필요, SSOT 원칙).

---

## 🧜‍♀️ 배포 워크플로우 (Workflow)

```mermaid
flowchart TD
    Start["🚀 1. 프로젝트 생성"] --> Dev["💻 2. 개발 및 커스터마이징"]
    Dev --> BuildSelect{"🛠️ 3. 빌드/배포 방식 선택"}

    %% 서브그래프: package 태스크 (Legacy + Docker 겸용)
    subgraph PackagePath ["📦 package 태스크 (Legacy + Docker 겸용)"]
        direction TB
        LegacyBuild["☕ Gradle/Maven 패키징<br/>(Jar/WAR + Scripts + Dockerfile)"]
        LegacyBuild --> LegacyTrans["📂 파일 전송/압축해제"]
        LegacyTrans --> InstallSelect{"⚙️ 배포 방식 선택<br/>(install_service.sh)"}
        InstallSelect -->|"1 Legacy (Java/Tomcat)"| LegacyRun["☕ Java/Tomcat 직접 실행<br/>(Systemd/SysVinit 등록)"]
        InstallSelect -->|"2 Docker"| PkgDocker["🐳 배포 패키지 내<br/>Dockerfile로 이미지 빌드<br/>& Compose 실행"]
    end

    %% 서브그래프: Docker 전용 전략
    subgraph DockerPath ["🐳 Docker Path (전용 태스크)"]
        direction TB
        DockerDecide{"전략 선택"}

        %% Strategy 1: Local Image
        subgraph DockerOpt1 ["① 오프라인 빌드 (Offline)"]
            D1_Build["🔨 packageDocker task<br/>(이미지 빌드)"]
            D1_Save["💾 Docker Image Save<br/>(.tar 파일)"]
            D1_Trans["📂 파일 전송<br/>(Local → Server)"]
            D1_Load["📦 스마트 인스톨<br/>(자동 docker load)"]

            D1_Build --> D1_Save --> D1_Trans --> D1_Load
        end

        %% Strategy 2: Repository
        subgraph DockerOpt2 ["② 레지스트리 (Registry)"]
            D2_Build["🔨 로컬 빌드<br/>(dockerBuildRemote task)"]
            D2_Push["☁️ Push to Registry<br/>(on Local PC)"]
            D2_Pull["⬇️ Pull from Registry<br/>(on Server)"]

            D2_Build --> D2_Push --> D2_Pull
        end

        DockerDecide --> DockerOpt1
        DockerDecide --> DockerOpt2

        D1_Load --> DockerService["⚙️ 서비스 등록/실행<br/>(Systemd/SysVinit)"]
        D2_Pull --> DockerService
    end

    %% 메인 연결
    BuildSelect -->|"package"| LegacyBuild
    BuildSelect -->|"Docker 전용 태스크"| DockerDecide

    LegacyRun --> Monitor["📈 통합 모니터링"]
    PkgDocker --> Monitor
    DockerService --> Monitor

    %% 범례
    subgraph Legend ["🔖 범례 (Legend)"]
        direction TB
        L1["💻 Local PC 환경"]
        L2["🖥️ Remote Server 환경"]
    end

    %% 스타일 정의
    classDef default fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef start fill:#E1F5FE,stroke:#01579B,stroke-width:2px,color:#000;
    classDef decision fill:#F3E5F5,stroke:#4A148C,stroke-width:2px,color:#000,stroke-dasharray: 5 5;
    classDef legacy fill:#FFEBEE,stroke:#B71C1C,stroke-width:2px,color:#000;
    classDef docker fill:#E3F2FD,stroke:#0D47A1,stroke-width:2px,color:#000;
    classDef endNode fill:#E8F5E9,stroke:#2E7D32,stroke-width:2px,color:#000;

    %% 환경별 (Local, Remote) Style
    classDef local_env fill:#BBDEFB,stroke:#1976D2,stroke-width:2px,color:#000;
    classDef remote_env fill:#C8E6C9,stroke:#388E3C,stroke-width:2px,color:#000;

    class Start,Dev start;
    class BuildSelect,DockerDecide,InstallSelect, decision;
    class Monitor endNode;

    %% Nodes & Legend Styling (Local vs Remote)
    class LegacyBuild,D1_Build,D1_Save,D1_Trans,D2_Build,D2_Push,L1 local_env;
    class LegacyTrans,LegacyRun,PkgDocker,D1_Load,D2_Pull,DockerService,L2 remote_env;
    class AS1,AS2,AS3 remote_env;
```

---

## 🧜‍♀️ 배포 시퀀스 (Sequence Diagram)

### 📦 Legacy 배포 (`packageJar` / `packageTomcat`)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as 🧑‍💻 개발자
    participant Tool as 🐘 Gradle / 🪶 Maven
    participant Server as 🖥️ 운영 서버

    Dev->>Tool: packageJar -Penv=prod (또는 packageTomcat)
    activate Tool

    alt JAR 모드 (packageType=jar)
        Tool->>Tool: Executable JAR 빌드 + Scripts + Dockerfile + config 패키징
        Tool->>Tool: Zip에 libs/ 포함
    else Tomcat 모드 (packageType=tomcat)
        Tool->>Tool: verifyTomcatPrerequisites 검증
        Note over Tool: ✅ war 플러그인 / SpringBootServletInitializer 확인
        Tool->>Tool: WAR 빌드 → Explode → webapps/ROOT/
        Tool->>Tool: tomcat/conf/, tomcat/bin/ 설정 번들링
    end

    Tool-->>Dev: {APP_NAME}-{version}.zip 생성
    deactivate Tool

    Dev->>Server: scp + unzip (또는 deploy 태스크로 자동화)
    activate Server
    Dev->>Server: sudo ./deploy/install_service.sh

    Note over Server: 배포 방식 선택 (대화형)

    alt 1) Legacy JAR — Java 직접 실행
        Server->>Server: JDK로 Executable JAR 실행
        Server->>Server: Systemd/SysVinit 서비스 등록
    else 2) Legacy Tomcat — 외장 Tomcat
        Server->>Server: CATALINA_HOME 경로 입력/자동 탐색
        Server->>Server: webapps/ROOT/ → $CATALINA_HOME/webapps/ROOT/ 복사
        Server->>Server: .env + Systemd에 CATALINA_HOME 자동 주입
        Server->>Server: catalina.sh start
    else 3) Docker — 패키지 내 Dockerfile 빌드
        Server->>Server: docker build
        Server->>Server: docker compose up -d
        Server->>Server: Systemd/SysVinit 서비스 등록
    end

    Server-->>Dev: 서비스 시작 완료
    deactivate Server
```

---

### 🐳 Docker 배포 (2가지 전용 전략 + 1 통합 배포)

Docker 전용 태스크는 주로 **어디서 빌드하고 어떻게 서버에 배포할 것인가(네트워크 및 인프라 환경)**에 따라 나뉩니다. 다음 표를 참고하여 환경에 맞는 방식을 선택하세요:

|      구분       | Strategy 1: `packageDocker`                     | Strategy 2: `dockerBuildRemote`                               | (참고) 통합 배포: `package`                |
| :-------------: | :---------------------------------------------- | :------------------------------------------------------------ | :----------------------------------------- |
|  **핵심 목적**  | 외부 서버 전송을 위한 **단일 Zip 패키지 생성**  | 원격 저장소를 활용한 **표준 파이프라인 구성**                 | 배포 서버에서 런타임에 직접 실행 방식 선택 |
|  **타겟 환경**  | 인터넷/레지스트리 접근이 불가한 **폐쇄망 환경** | AWS ECR, Docker Hub 등 **원격 레지스트리 환경**               | 서버에서 소스를 클론받아 바로 띄우는 환경  |
|  **작업 내용**  | 이미지 빌드 + `.tar` 추출 + Zip 파일 압축       | 이미지 빌드 + 원격 레지스트리로 `docker push`                 | Jar 빌드 + Dockerfile + 스크립트 압축      |
| **주요 산출물** | `build/dist/...-docker-prod.zip`                | Remote Registry에 업로드된 Docker Image                       | `build/dist/...-prod.dist.zip`             |
|  **전송 방식**  | 수동 전송 필요 (Zip 파일을 복사)                | 자동 풀 (운영 서버에서 `docker pull`로 수신)                  | 소스 pull 또는 Zip 복사                    |
|  **실행 예시**  | `./gradlew packageDocker -Penv=prod`            | `./gradlew dockerBuildRemote -Penv=prod -PdockerRegistry=...` | `./gradlew package -Penv=prod`             |

#### Strategy 1 — 오프라인 빌드 (Offline Image) (`./gradlew packageDocker`)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as 🧑‍💻 개발자
    participant Gradle as 🐘 Gradle / 🪶 Maven
    participant Server as 🖥️ 운영 서버

    Dev->>Gradle: ./gradlew packageDocker -Penv=prod
    activate Gradle
    Gradle->>Gradle: Docker 이미지 빌드 (linux/amd64)
    Gradle->>Gradle: docker save → image.tar 추출
    Gradle->>Gradle: tar + 배포 스크립트 → docker.zip 패키징
    Gradle-->>Dev: {APP_NAME}-docker-prod.zip 생성
    deactivate Gradle

    Dev->>Server: scp + unzip
    activate Server
    Dev->>Server: sudo ./deploy/install_service.sh
    Server->>Server: docker load (image.tar)
    Server->>Server: docker compose up -d
    Server->>Server: Systemd/SysVinit 서비스 등록
    Server-->>Dev: 컨테이너 실행 완료
    deactivate Server
```

#### Strategy 2 — Registry Push & Pull (`./gradlew dockerBuildRemote`)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as 🧑‍💻 개발자
    participant Gradle as 🐘 Gradle / 🪶 Maven
    participant Registry as 🗄️ Docker Registry
    participant Server as 🖥️ 운영 서버

    Dev->>Gradle: ./gradlew dockerBuildRemote -Penv=prod -PdockerRegistry=...
    activate Gradle
    Gradle->>Gradle: Docker 이미지 빌드 (linux/amd64)
    Gradle->>Gradle: DEPLOY-GUIDE.md 자동 생성
    Gradle->>Registry: docker push {image}:{tag}
    Gradle-->>Dev: Push 완료 + docker-dist/ 폴더 준비
    deactivate Gradle

    Dev->>Server: scp docker-dist/ 폴더 전송
    activate Server
    Server->>Registry: docker pull {image}:{tag}
    Dev->>Server: sudo ./deploy/install_service.sh
    Server->>Server: docker compose up -d
    Server->>Server: Systemd/SysVinit 서비스 등록
    Server-->>Dev: 컨테이너 실행 완료
    deactivate Server
```
