# 🚀 Distribution Maven Plugin (`distribution-maven-plugin`)

> Spring Boot 애플리케이션의 표준 빌드/배포 구조(`deploy`, `bin`, `config`, `lib`, `docker`)를 손쉽게 패키징하고,  
> 배포 스크립트 템플릿 내장 및 프로젝트별 **파일 단위 @Override**를 지원하는 Maven 커스텀 플러그인입니다. ✨

- **Author**: MJ Yun
- **JDK Requirement**: Java 25 이상
- **GroupId**: `io.github.mj-youn`
- **ArtifactId**: `distribution-maven-plugin`
- **Version**: `1.1.3`
- **Goals**:
    - `package`: 표준 배포 Zip 아카이브 생성
    - `deploy`: 빌드(패키징) ➡️ Zip 자동 압축 해제 ➡️ `install_service.sh` 자동 실행 (원스탑 배포)
    - `help`: 배포 플러그인 도움말 및 사용 가이드 출력

---

## 🌟 핵심 기능

1. **배포 인프라 무설치 (Zero Configuration)**:
    - Maven 프로젝트에 별도의 `scripts/`나 `docker/` 폴더를 둘 필요가 없습니다.
    - 플러그인 내부에 최신 배포 스크립트(`install_service.sh`, `start.sh`, `stop.sh`, `utils.sh` 등)와 `Dockerfile`이 기본 내장되어 있습니다.
2. **파일 단위 @Override 메커니즘 (Java의 상속과 동일)**:
    - 특정 프로젝트에서 JVM 옵션이나 스크립트 내용 변경이 필요할 때, 프로젝트 로컬에 동일한 경로의 파일(예: `scripts/service/start.sh`)을 생성하기만 하면 **자동으로 로컬 파일이 우선 적용(@Override)**됩니다.
    - 수정하지 않은 나머지 스크립트들은 플러그인의 최신 템플릿 파일이 그대로 유지됩니다.
3. **환경별 프로파일 자동 매핑**:
    - `-Denv=dev`, `-Denv=prod` (또는 pom의 `<env>` 프로퍼티) 옵션에 따라 `config.profiles/${env}` 디렉토리 내의 설정 파일을 패키지 `config/` 디렉토리에 파일명 접미사(`-dev` 등)를 자동 제거하여 표준 명칭으로 패키징합니다.
4. **표준 배포 패키지 (Zip) 생성**:
    - 실행 권한(`0755`)이 보존된 리눅스 서비스 등록 및 기동 스크립트가 포함된 완전한 배포용 Zip 패키지를 생성합니다.
5. **원스탑 서비스 자동 배포 (`mvn distribution:deploy`)**:
    - 서버에서 소스를 빌드하여 패키징한 후, 즉시 산출물 Zip을 해제하고 `deploy/install_service.sh`를 실행하여 서비스 등록/구동까지 한 번에 완료합니다.

---

## 📦 패키지 산출물 구조

생성된 아카이브(`.zip`)는 다음과 같은 표준 구조를 가집니다:

```text
📦 {project.artifactId}-{project.version}.zip
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
│   └── {project.artifactId}-{project.version}.jar
└── 📁 docker/                  # 도커 빌드 및 컴포즈 파일
    ├── Dockerfile
    ├── docker-compose.yml
    ├── dev/
    └── prod/
```

---

## 💻 개별 Maven 프로젝트 적용 방법

개별 Spring Boot 프로젝트의 `pom.xml`에 플러그인을 선언합니다:

```xml
<build>
    <plugins>
        <!-- ⭐️ 배포 플러그인 추가 -->
        <plugin>
            <groupId>io.github.mj-youn</groupId>
            <artifactId>distribution-maven-plugin</artifactId>
            <version>1.1.3</version>
            <executions>
                <execution>
                    <phase>package</phase>
                    <goals>
                        <goal>package</goal>
                    </goals>
                </execution>
            </executions>
            <configuration>
                <!-- (선택 사항) 앱 이름 커스텀 (미지정 시 project.artifactId가 기본 적용됨) -->
                <!-- artifactId가 길거나 대문자가 포함된 경우 간결한 소문자 서비스명으로 지정을 권장합니다 -->
                <appName>my-maven-service</appName>
                <!-- (선택 사항) 배포 ZIP 루트로 함께 복제할 추가 디렉토리 (공백/콤마 구분) -->
                <extraDirs>flags data</extraDirs>
            </configuration>
        </plugin>
    </plugins>
</build>
```

### 🚀 빌드 및 배포 명령어 가이드

#### 💡 [배포 도움말 확인]

```bash
mvn distribution:help
```

#### 📦 [기본 패키징 (ZIP 생성)]

```bash
# 개발(dev) 환경 패키징
mvn clean package -Denv=dev

# 운영(prod) 환경 패키징
mvn clean package -Denv=prod
```

- **산출물**: `target/{project.artifactId}-{project.version}.zip`
- 서버 배포 시 압축 해제 후 `deploy/install_service.sh`를 실행하면 Systemd/SysVinit 서비스 또는 Docker 컨테이너 방식으로 즉시 설치됩니다.

#### 🚀 [원스탑 빌드 및 서비스 자동 배포]

```bash
# 빌드 ➡️ 압축 해제 ➡️ install_service.sh 자동 실행까지 원클릭 완료
mvn distribution:deploy -Denv=dev
mvn distribution:deploy -Denv=prod
```

---

## 🛠️ 플러그인 로컬 빌드 및 배포 가이드

루트 프로젝트 디렉토리에서 Gradle 명령어로 Maven 플러그인을 빌드 및 배포합니다:

```bash
# 로컬 컴파일 및 빌드 검증
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew :distribution-maven-plugin:build

# 로컬 Maven 캐시(~/.m2/repository)에 배포
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew :distribution-maven-plugin:publishToMavenLocal

# Maven Central (Sonatype) 배포
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-25.jdk/Contents/Home ./gradlew :distribution-maven-plugin:publish
```
