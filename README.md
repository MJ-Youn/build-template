# 🚀 Spring Boot Build & Deploy Platform

> **이 프로젝트는 Spring Boot 애플리케이션의 배포 체계를 표준화하기 위한 중앙 빌드/배포 플랫폼 허브입니다.**  
> 이제는 복잡한 스크립트 파일들을 프로젝트마다 복사(Boilerplate)하여 분산 관리할 필요가 없습니다.  
> **Gradle 플러그인**과 **Maven 플러그인**을 한 지붕 아래에서 단일 원본(SSOT)으로 관리하며, 개별 프로젝트에서는 **플러그인 선언 1줄**만으로 완벽한 표준 배포 환경을 구축할 수 있습니다. ✨

---

## 🌟 핵심 가치: 왜 플러그인 방식을 사용해야 하는가?

1. **📦 배포 인프라 무설치 (Zero Copy)**:
    - 개별 프로젝트에 `scripts/`나 `docker/` 폴더를 복사해 둘 필요가 없습니다.
    - 플러그인 내부에 서비스 등록/시작/종료 스크립트와 `Dockerfile`이 기본 탑재되어 배포 아카이브(`.zip`)를 자동 조립합니다.
2. **🧩 파일 단위 @Override 메커니즘 (Java의 상속 원리)**:
    - 특정 프로젝트에서 JVM 옵션이나 스크립트 커스터마이징이 필요할 때, 프로젝트 로컬에 동일한 경로의 파일(예: `scripts/service/start.sh`)을 생성하기만 하면 **자동으로 로컬 파일이 우선 적용(@Override)**됩니다.
    - 수정하지 않은 나머지 스크립트들은 플러그인의 최신 템플릿 파일이 그대로 유지됩니다.
3. **🔄 단일 마스터 원본(SSOT)과 Gradle & Maven 통합 관리**:
    - 본 저장소의 루트 `/scripts`와 `/docker`가 유일한 마스터 원본입니다.
    - 플러그인 빌드 시 루트의 마스터 자원을 자동으로 끌어가므로 스크립트 중복 관리가 0개입니다.
    - `./gradlew publishAllPlugins` 명령 한 줄로 **Gradle Plugin Portal**과 **Maven Central**에 동시에 최신 버전을 배포합니다.

---

## 🔌 배포 플러그인 (Distribution Plugins)

개별 프로젝트의 빌드 도구에 맞추어 플러그인을 적용하세요:

| 빌드 도구  | 플러그인 모듈                                 | 배포 저장소          | 문서 바로가기                                                    |
| :--------- | :-------------------------------------------- | :------------------- | :--------------------------------------------------------------- |
| **Gradle** | `io.github.mj-youn.distribution`              | Gradle Plugin Portal | [**Gradle Plugin README**](distribution-gradle-plugin/README.md) |
| **Maven**  | `io.github.mj-youn:distribution-maven-plugin` | Maven Central        | [**Maven Plugin README**](distribution-maven-plugin/README.md)   |

### 💻 개별 프로젝트 적용 방법 (1줄 설정)

#### 🐘 Gradle 프로젝트 (`build.gradle`)

```groovy
plugins {
    id 'io.github.mj-youn.distribution' version '1.1.5'
}
```

- **배포 패키지 생성**:
    ```bash
    ./gradlew package -Penv=dev    # 개발 환경 배포 Zip
    ./gradlew package -Penv=prod   # 운영 환경 배포 Zip
    ```

#### 🪶 Maven 프로젝트 (`pom.xml`)

```xml
<build>
    <plugins>
        <plugin>
            <groupId>io.github.mj-youn</groupId>
            <artifactId>distribution-maven-plugin</artifactId>
            <version>1.1.5</version>
            <executions>
                <execution>
                    <goals><goal>package</goal></goals>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

- **배포 패키지 생성**:
    ```bash
    mvn clean package -Denv=dev    # 개발 환경 배포 Zip
    mvn clean package -Denv=prod   # 운영 환경 배포 Zip
    ```

#### 🏷️ `appName` 옵션 설정 가이드 및 주의 사항 (선택 사항)

플러그인 설정의 `appName`은 서버 배포 및 운영 전반에서 사용되는 **해당 서비스의 공식 식별자(Identifier)**입니다.

##### 1) 기본 동작 (미설정 시)

- **설정하지 않아도 문제없이 동작합니다.**
- 기본값:
    - **Maven**: `pom.xml`의 `<artifactId>` (예: `nccatweb`)
    - **Gradle**: `settings.gradle`의 `rootProject.name` (예: `LGUplus-HDRMS-WEB`)

##### 2) 언제 설정하면 좋은가요?

다음과 같은 경우 `appName`을 간결하고 명확한 소문자 식별자로 지정하는 것을 강력히 권장합니다:

- **저장소명이나 artifactId가 길거나 대문자/특수문자가 포함된 경우**:
    - 예: `LGUplus-HDRMS-WEB` ➡️ `appName = 'hdrms'`
- **서버 운영 리소스 명칭을 통일하고 싶을 때**:
    - 🐧 **Linux Systemd 서비스명**: `/etc/systemd/system/{appName}.service` (`systemctl start {appName}`)
    - 📁 **기본 로그 저장 경로**: `/log/{appName}` (예: `/log/hdrms`)
    - 🐳 **Docker 이미지 태그**: `{appName}:{version}` (예: `hdrms:1.1.5`)
    - 🐚 **프로세스 제어 콘솔 출력**: `🚀 [{appName}] 서비스를 시작합니다...`

##### 3) ⚠️ 설정 시 주의 사항

> **이미 서버에 배포된 서비스의 `appName` 변경 시**:  
> Linux Systemd는 파일명(`{appName}.service`)으로 서비스를 식별합니다. 이미 배포된 서버에서 `appName`을 변경하면 이전 서비스와 이름이 달라져 **새로운 별개 서비스로 중복 등록**될 수 있습니다. 따라서 최초 배포 단계에서 원하는 서비스 명칭을 확정하시는 것을 권장합니다.

---

## 💡 배포 및 빌드 가이드 확인 (`help`)

개별 프로젝트에서 터미널을 통해 언제든지 지원하는 태스크, 골(Goal), 환경 옵션 및 사용 예시를 확인할 수 있습니다:

### 🐘 Gradle 프로젝트

```bash
./gradlew help        # 프로젝트 기본 도움말과 배포 가이드 배너 출력
./gradlew distHelp    # 배포 전용 상세 가이드 출력
```

### 🪶 Maven 프로젝트

```bash
mvn distribution:help
```

---

## 🚀 원스탑 빌드 및 서비스 자동 배포 (`deployService` / `distribution:deploy`)

> **서버에 소스 코드가 위치한 환경(Legacy/서버 직접 빌드)**에서, 번거로운 "빌드 ➡️ 압축 해제 ➡️ 스크립트 실행" 과정을 **단 한 줄의 명령어로 완전 자동화**합니다.  
> (기존 외장 스크립트였던 `build_deploy.sh`의 기능을 플러그인 내부 태스크/골로 완벽히 내장하였습니다.)

### 🔄 실행 흐름

```
[1/3] 🔨 Package         → 환경별 배포 패키지(ZIP) 자동 조립 (Jar + Scripts + Dockerfile)
[2/3] 📦 AUTO 압축 해제   → 빌드 디렉토리에 산출물 Zip 자동 해제
[3/3] 🚀 서비스 구동     → deploy/install_service.sh 자동 실행 (서비스 등록 및 백그라운드 구동)
```

### 💻 실행 명령어

#### 🐘 Gradle 프로젝트

```bash
./gradlew deployService -Penv=dev    # 개발 환경 빌드 & 즉시 서비스 설치/구동
./gradlew deployService -Penv=prod   # 운영 환경 빌드 & 즉시 서비스 설치/구동
```

#### 🪶 Maven 프로젝트

```bash
mvn distribution:deploy -Denv=dev    # 개발 환경 빌드 & 즉시 서비스 설치/구동
mvn distribution:deploy -Denv=prod   # 운영 환경 빌드 & 즉시 서비스 설치/구동
```

### 📋 상세 동작

1. **패키징 (Package)**: 지정된 환경(`-Penv` 또는 `-Denv`)의 프로파일(`config.profiles/{env}`)과 스크립트 오버레이를 적용하여 배포 아카이브(`.zip`)를 생성합니다.
2. **압축 자동 해제 (Unzip)**: 생성된 배포 ZIP을 빌드 디렉토리 내부 임시 폴더에 압축 해제합니다.
3. **서비스 인스톨러 자동 실행**: 압축 해제된 `deploy/install_service.sh`에 실행 권한(`0755`)을 부여하고 즉시 실행하여, Linux 백그라운드 데몬 서비스 등록 및 앱 구동까지 마칩니다.

---

## 📦 빌드 및 배포 (Build & Deploy)

> **💡 Docker 배포 시 주요 특징 (설정 파일 Host Mount & .env 적용)**
>
> - 배포 결과물에는 호스트 환경에서 직접 수정 가능한 `config/` 디렉토리가 포함됩니다.
> - `install_service.sh` 실행 시 혹은 `docker-compose up` 시 서버 측 `config/` 폴더가 컨테이너 내부로 바인드 마운트되어, **이미지 재빌드 없이 `application.yml`, `log4j2.yml` 등을 런타임에 즉시 변경**할 수 있습니다.
> - 초기 설치 시 빈 마운트로 인한 파일 유실을 막기 위해 이미지에서 초기 설정 파일들을 자동으로 추출(Seed)하는 방어 로직이 내장되어 있습니다.
> - 자체 문자열 치환(`@VAR@`) 대신 표준 **Docker Compose `.env` 파일** 환경변수를 사용하여 `docker-compose up` 명령어 단독 실행 시에도 완벽하게 동작합니다.

### 🐳 Docker 배포 1: 로컬 빌드 (Standard)

**"로컬 빌드 -> 이미지 추출 -> 서버 전송 -> 로드 & 실행"** 전략을 사용합니다.
서버에 소스 코드를 올리거나 빌드 도구를 설치할 필요가 없어 보안과 관리가 용이합니다.

**1. 빌드 (Development PC)**

```bash
# 🐘 Gradle 환경
./gradlew packageDocker -Penv=prod

# 🪶 Maven 환경
mvn distribution:package-docker -Denv=prod
```

- **결과물**: `build/dist/{APP_NAME}-docker-prod.zip` 또는 `target/{APP_NAME}-docker-prod.zip`
- **포함 내용**:
    - `image.tar`: Docker 이미지 (linux/amd64)
    - `docker-compose.yml`: 실행 설정 (표준 변수 사용)
    - `config/`: 운영 환경용 설정 파일 (Host Mount용)
    - `deploy/install_service.sh`: 서비스 등록/실행 및 `.env` 파일 생성 스크립트
    - `deploy/uninstall_service.sh`: 서비스 제거 스크립트
    - `utils.sh`: 공통 스크립트

**2. 배포 (Production Server)**

```bash
# 1. 파일 전송 (scp 등)
scp build/dist/{APP_NAME}-docker-prod.zip user@server:/home/user/

# 2. 서버 접속 후 압축 해제 및 설치
unzip {APP_NAME}-docker-prod.zip -d deploy
cd deploy
sudo ./deploy/install_service.sh
```

- **자동 수행**:
    - Docker 이미지 로드 (`docker load`)
    - 배포 경로 기반 `.env` 파일 자동 생성
    - Docker Compose 실행 (`docker-compose up -d`)
    - Linux 서비스(Systemd) 등록 (재부팅 시 자동 실행)

### 🐳 Docker 배포 2: 레지스트리 (Push & Pull)

**"Local/CI 빌드 -> Registry Push -> Server Pull -> 실행"** 전략을 사용합니다.
Docker Hub, ECR, GCR 등 원격 레지스트리를 활용하는 표준적인 방식입니다.

**1. 빌드 및 Push (Development PC / CI)**

```bash
# 🐘 Gradle 환경
./gradlew dockerBuildRemote -Penv=prod -PdockerRegistry=my-registry.com/repo

# 🪶 Maven 환경
mvn distribution:docker-build-remote -Denv=prod -DdockerRegistry=my-registry.com/repo

# (선택) 태그 지정 가능 (기본값: latest)
# Gradle: ./gradlew dockerBuildRemote -Penv=prod -PdockerRegistry=... -PdockerImageTag=v1.0.0
# Maven:  mvn distribution:docker-build-remote -Denv=prod -DdockerRegistry=... -DdockerImageTag=v1.0.0
```

- **결과물**:
    - Docker Registry에 이미지 업로드 (`my-registry.com/repo/{APP_NAME}:latest`)
    - `build/docker-dist` (또는 `target/docker-dist`): 실행에 필요한 파일들 (`docker-compose.yml`, `config`, 스크립트 등)

**2. 배포 (Server)**

서버에는 **`build/docker-dist` (또는 `target/docker-dist`) 폴더의 내용물만** 있으면 됩니다. (소스 코드 불필요)
CI/CD 파이프라인을 통해 설정 파일만 배포하거나, scp로 전송하세요.

```bash
# 1. 배포 디렉토리로 이동
cd docker-dist

# 2. 서비스 등록 (이미지는 레지스트리에서 자동 Pull 및 .env 구성)
sudo ./deploy/install_service.sh
```

> ⚠️ **주의**: Private Registry를 사용하는 경우, 서버에서 `docker login`이 선행되어야 합니다.

### 🖥️ 일반 서버 배포 (Legacy)

Docker 없이 Java(JDK)만 설치된 서버에 배포하는 방식입니다.

**1. 빌드 (Development PC)**

- **Gradle**: `./gradlew package -Penv=prod`
- **Maven**: `mvn clean package -Denv=prod`
- **결과물**: `build/distributions/{APP_NAME}-{version}.zip` 또는 `target/{APP_NAME}-{version}.zip`

**2. 배포 (Server) — 수동 아카이브 전송 시**

```bash
# 압축 해제 후 설치 스크립트 실행
unzip {APP_NAME}-*.zip -d {APP_NAME}
cd {APP_NAME}
sudo ./deploy/install_service.sh
```

**3. 배포 (Server) — 서버 소스 직접 원스탑 빌드/구동 (권장)**

서버에 소스 코드가 위치해 있는 경우, 별도의 스크립트 없이 플러그인 원스탑 명령으로 패키징부터 설치/실행까지 한 번에 처리할 수 있습니다:

```bash
# Gradle 환경
./gradlew deployService -Penv=prod

# Maven 환경
mvn distribution:deploy -Denv=prod
```

### ☸️ Kubernetes 배포 (K8s) (개발 예정)

Docker 배포를 넘어, Kubernetes 환경을 위한 매니페스트(`yaml`)도 자동으로 생성해줍니다.

**1. 빌드 (Development PC)**

```bash
# 🐘 Gradle 환경
./gradlew k8sBuild -Penv=prod

# 🪶 Maven 환경
mvn distribution:k8s-build -Denv=prod
```

- **결과물**: `build/dist/{APP_NAME}-k8s-prod.zip` 또는 `target/{APP_NAME}-k8s-prod.zip`
- **내용**: `deployment.yaml`, `service.yaml`, `configmap.yaml` (프로젝트 이름 자동 적용됨)

**2. 배포 (K8s Cluster)**

```bash
# 압축 해제
unzip {APP_NAME}-k8s-prod.zip -d k8s-deploy
cd k8s-deploy/k8s

# 클러스터에 적용
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

---

## ✅ 배포 검증 (Verification)

배포가 정상적으로 완료되었는지 확인하는 3단계 루틴입니다.

### 1. 프로세스 및 포트 확인

서비스가 실행 중이고 포트(8080)가 열려있는지 확인합니다.

```bash
# 🐳 Docker 배포 시
docker ps | grep my-service

# 🖥️ 일반 배포 시
ps -ef | grep java
# 또는
netstat -anlp | grep :8080
```

### 2. 로그 확인 (필수)

애플리케이션이 에러 없이 부팅되었는지 로그를 확인하세요.
`Started Application` 문구가 보이면 성공입니다.

```bash
# 🐳 Docker 배포 시
docker logs -f my-service

# 🖥️ 일반 배포 시 (편의 스크립트)
tail-log-my-service.sh
```

### 3. API 응답 확인 (e.g. Health Check)

실제로 요청을 보내 응답이 오는지 테스트합니다.

```bash
# 로컬에서 테스트
curl -v http://localhost:8080/

# 응답 예시
# < HTTP/1.1 200 OK ...
```

---

## 📂 Scripts 디렉토리 구조

`/scripts` 디렉토리는 역할에 따라 명확히 하위 폴더로 구분되어 관리됩니다:

- **`scripts/deploy/`** (배포/설치 및 제거)
    - `install_service.sh`: 서비스 설치 및 Systemd/SysVinit 등록 스크립트
    - `uninstall_service.sh`: 서비스 중지 및 제거 스크립트
- **`scripts/service/`** (서비스 구동 및 런타임 운영)
    - `start.sh`: 백그라운드 서비스 시작 스크립트
    - `stop.sh`: 서비스 프로세스 종료 스크립트 (Graceful shutdown & Force kill)
    - `status.sh`: 서비스 구동 상태, PID, 포트, 로그 경로 확인 스크립트
    - `cron/`: 크론 및 헬스체크 작업
- **`scripts/common/`** (공통 유틸리티)
    - `bootstrap.sh`: 환경 로더 및 유틸리티 폴백
    - `utils.sh`: 컬러 로깅 및 안전 경로 검증 함수
    - `run_bash_tests.sh`: Bash 테스트 실행기

> 💡 빌드(`package`) 시 `scripts/deploy` 및 `scripts/common`은 배포 아카이브의 `deploy/` 폴더로 패키징되며, `scripts/service` 및 `scripts/common`은 `bin/` 폴더로 패키징됩니다.

---

## 🎨 고급 설정: 환경별 빌드 (Overlay)

설정 파일(`config`)과 스크립트(`scripts`)는 **"덮어쓰기 전략"** 을 따릅니다.
환경별로 다른 설정이 필요하면, `config.profiles/{env}/` 및 `scripts/{env}/` 폴더에 파일을 넣으세요.

| 경로                                        | 역할                                 | 우선순위                                       |
| ------------------------------------------- | ------------------------------------ | ---------------------------------------------- |
| `config.profiles/prod/application-prod.yml` | **운영 환경 전용 애플리케이션 설정** | 🥇 1순위 (`config/application.yml`로 덮어써짐) |
| `config.profiles/prod/log4j2-prod.yml`      | **운영 환경 전용 로깅 설정**         | 🥇 1순위 (`config/log4j2.yml`로 덮어써짐)      |
| `config/application.yml`                    | **공통 기본 설정**                   | 🥈 2순위                                       |
| `config/log4j2.yml`                         | **공통 기본 로깅 설정**              | 🥈 2순위                                       |
| `scripts/prod/.env`                         | **운영 환경 전용 스크립트 환경변수** | 🥇 1순위 (Zip에 이 파일이 덮어써짐)            |
| `scripts/.env`                              | **공통 기본값**                      | 🥈 2순위                                       |

**예시: 운영 서버 설정 및 로그 경로 변경**

1. `config.profiles/prod/application-prod.yml` 및 `config.profiles/prod/log4j2-prod.yml` 작성
2. `scripts/prod/.env` 작성: `LOG_PATH="/var/log/my-service"`
3. `./gradlew package -Penv=prod` 실행 시 자동으로 적용됨.

---

## ⚙️ 런타임 환경 설정 (.env) 완벽 가이드

> **`start.sh` 스크립트 전체를 복사하지 않고, 옵션과 파라미터만 스마트하게 변경하고 싶으신가요?**  
> 이제 배포 패키지에 `.env` 파일만 생성하면 JVM 메모리 튜닝, 시스템 프로퍼티, Spring Boot 애플리케이션 인수를 단 한 줄로 자유롭게 제어할 수 있습니다. ✨

### 📍 `.env` 파일 위치 및 로딩 우선순위

스크립트 실행 시 다음 경로를 순서대로 탐색하여 로드합니다 (뒤에 로드된 파일이 앞선 설정을 오버라이드):

1. `📦 {PROJECT_ROOT}/.env` : 패키지 루트 디렉토리 (**Docker Compose와 공용 사용 시 권장**)
2. `📁 config/.env` : 설정 디렉토리 내부
3. `📁 bin/.env` : 실행 스크립트 디렉토리 내부 (Legacy 스크립트 전용)

> 💡 **빌드 시 자동 포함 방법**: 프로젝트 소스 트리의 `scripts/service/.env` 또는 환경별 `scripts/{env}/.env`에 파일을 생성해두면, 플러그인이 빌드(`package`) 시 자동으로 배포 아카이브 내부에 포함시킵니다.

---

### 📋 지원하는 주요 환경변수 목록

| 분류                   | 변수명                | 기본값                | 설명 및 예시                                                                                                               |
| :--------------------- | :-------------------- | :-------------------- | :------------------------------------------------------------------------------------------------------------------------- |
| **JVM 힙 메모리**      | `JVM_XMS`             | _(미지정)_            | JVM 초기 힙 메모리 크기 (예: `-Xms1024m`, `-Xms2g`)                                                                        |
|                        | `JVM_XMX`             | _(미지정)_            | JVM 최대 힙 메모리 크기 (예: `-Xmx2048m`, `-Xmx4g`)                                                                        |
| **JVM 추가 옵션**      | `EXTRA_JAVA_OPTS`     | _(공백)_              | GC 설정, 파일 인코딩, 타임존 등 추가 옵션<br/>`"-XX:+UseG1GC -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Seoul"`            |
| **Spring Boot 인수**   | `APP_ARGS`            | _(공백)_              | JAR 실행 시 뒤에 붙을 프로그램 커맨드라인 인수<br/>`"--server.port=9090 --custom.flag=true --spring.main.banner-mode=off"` |
| **프로세스 관리**      | `SERVER_PORT`         | `8080` (자동 감지)    | 서비스 포트 (미지정 시 `application.yml`의 port 자동 파싱)                                                                 |
|                        | `LOG_PATH`            | `{PROJECT_ROOT}/log`  | 애플리케이션 로그 파일이 저장될 절대/상대 경로                                                                             |
|                        | `PID_FILE`            | `bin/application.pid` | 프로세스 ID(PID)가 기록될 파일 경로                                                                                        |
|                        | `STOP_TIMEOUT`        | `10` (초)             | 서비스 정상 종료(Graceful Shutdown) 대기 시간                                                                              |
| **Docker / 컨테이너**  | `APP_UID` / `APP_GID` | `1000` / `1000`       | 컨테이너 내부 실행 리눅스 계정의 UID 및 GID                                                                                |
|                        | `CHOWN_DIRS`          | _(미지정)_            | 볼륨 마운트 시 컨테이너 기동 시점에 소유권을 자동 변경할 폴더 목록                                                         |
|                        | `TZ`                  | `Asia/Seoul`          | 컨테이너 시스템 타임존                                                                                                     |
| **추가 디렉토리 복제** | `EXTRA_DIRS`          | _(미지정)_            | 배포 패키지 및 설치 위치로 함께 복사할 추가 폴더 목록 (공백 구분)<br/>`EXTRA_DIRS="flags data uploads"`                    |

---

### 🐳 일반 서버(Legacy) `.env` vs Docker Compose `.env` 차이 및 통합 사용법

많은 분들이 궁금해하시는 두 방식의 차이점과 통합 활용 팁입니다:

#### 1. 두 방식의 역할 차이

| 구분               | 🖥️ 일반 서버(Legacy) `.env`                                 | 🐳 Docker Compose `.env`                                        |
| :----------------- | :---------------------------------------------------------- | :-------------------------------------------------------------- |
| **주요 소비자**    | Bash 쉘 스크립트 (`start.sh`, `stop.sh`, `status.sh`)       | Docker Compose CLI (`docker-compose up`)                        |
| **동작 메커니즘**  | 스크립트 실행 시 `source .env`로 Bash 환경변수로 로드       | Compose 파일 파싱 시 `${VAR}` 치환 및 컨테이너 환경변수 주입    |
| **핵심 사용 목적** | JVM 튜닝, Spring Boot 프로그램 인수, 로컬 프로세스 PID 관리 | 호스트-컨테이너 포트 매핑, 이미지 태그, 호스트 볼륨 경로 바인딩 |

#### 2. 🤝 함께(공용으로) 사용해도 되나요?

**네, 완벽하게 함께 사용할 수 있습니다!** 🎉

Docker Compose와 Bash 스크립트 모두 표준적인 `KEY="VALUE"` 문법을 따르기 때문에, **배포 패키지 루트의 단일 `.env` 파일에 두 설정을 함께 작성**해 두면 다음과 같이 유기적으로 동작합니다:

1. **Docker Compose 실행 시**: Compose CLI가 `.env`에서 `SERVER_PORT`, `APP_UID`, `TZ` 등을 읽어 컨테이너 설정 및 포트 포워딩에 반영합니다.
2. **컨테이너 내부 기동 시**: 컨테이너의 진입점(`start.sh`)이 마운트된 동일한 `.env`를 자동으로 `source`하여 `JVM_XMX`, `EXTRA_JAVA_OPTS`, `APP_ARGS`를 Java 프로세스에 적용합니다.

```bash
# ⭐️ 패키지 루트의 .env (Legacy와 Docker Compose 통합 예시)
# 1) Docker Compose용 호스트 설정
SERVER_PORT=8080
TZ=Asia/Seoul
APP_UID=1000
APP_GID=1000

# 2) Java & Spring Boot 실행용 설정 (Legacy 및 Docker 컨테이너 내부 공용)
JVM_XMS="-Xms1g"
JVM_XMX="-Xmx2g"
EXTRA_JAVA_OPTS="-XX:+UseG1GC -Dfile.encoding=UTF-8"
APP_ARGS="--spring.profiles.active=prod"
LOG_PATH="/var/log/my-service"
STOP_TIMEOUT=15

# 3) 추가 리소스 디렉토리 복제 설정 (예: flags, data 등)
EXTRA_DIRS="flags data"
```

---

### 📁 추가 리소스 디렉토리 복제 가이드 (`EXTRA_DIRS` / `extraDirs`)

프로젝트에 따라 표준 디렉토리(`bin`, `libs`, `config`, `docker`) 외에 **국기 이미지(`flags/`), 정적 데이터(`data/`), 업로드 템플릿(`uploads/`)** 등 프로젝트 고유의 리소스 폴더를 배포 패키지 및 최종 서버 설치 디렉토리로 함께 복제해야 하는 경우가 있습니다.

이러한 경우 코드 수정 없이 **설정 한 줄**로 유연하게 처리할 수 있습니다:

#### 1. `.env` 파일로 지정하는 방법 (권장)

`.env` (또는 `config.profiles/{env}/.env`)에 공백으로 구분하여 원하는 폴더명을 작성합니다:

```bash
# 배포 패키지 및 설치 경로로 함께 복사할 추가 폴더 목록 (공백 구분)
EXTRA_DIRS="flags data uploads"
```

#### 2. 빌드 스크립트(`pom.xml` / `build.gradle`)로 지정하는 방법

- **Maven (`pom.xml`)**:
    ```xml
    <configuration>
      <appName>${project.artifactId}</appName>
      <!-- 추가 복제할 폴더 지정 (공백 또는 콤마 구분) -->
      <extraDirs>flags data</extraDirs>
    </configuration>
    ```
- **Gradle (`build.gradle`)**:
    ```groovy
    distribution {
        appName = 'my-service'
        extraDirs = ['flags', 'data']
    }
    ```

#### ⚙️ 동작 메커니즘

1. **빌드 시 (`package`)**: 플러그인이 설정된 디렉토리를 프로젝트 루트에서 탐색하여 배포 ZIP 아카이브 루트에 트리 구조 그대로 번들링합니다.
2. **서비스 설치 시 (`install_service.sh`)**:
    - **Legacy 모드**: 배포 패키지 내의 해당 폴더들을 최종 설치 위치(`$DEST_DIR`)로 자동 복사하고 실행 계정 소유권(`chown/chmod 755`)을 부여합니다.
    - **Docker 모드**: Dockerfile의 `COPY flags/ /app/flags/` 명령어가 정상 동작하도록 빌드 컨텍스트에 배치합니다.

---

## 🛠️ 플랫폼 개발 및 관리자 가이드 (Maintainer Guide)

> **이 저장소(`build_template`) 자체를 개발, 유지보수하고 공식 저장소(Gradle Portal / Maven Central)에 배포하는 관리자이신가요?**

플러그인 아키텍처, 단일 원본(SSOT) 리소스 동기화 원리, 로컬 테스트 및 **원클릭 동시 배포(`publishAllPlugins`)**에 대한 상세 내용은 아래 전용 가이드 문서를 참고하시기 바랍니다:

👉 [**Spring Boot Build & Deploy 플랫폼 개발자 및 관리자 가이드 (DEVELOPER_GUIDE.md)**](DEVELOPER_GUIDE.md)
