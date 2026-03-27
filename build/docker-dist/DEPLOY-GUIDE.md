# 🐳 build_test — Docker 배포 가이드 (Strategy 3: Registry)

> **이 파일은 `./gradlew dockerPushImage` 빌드 시 자동 생성되었습니다.**
> 서버 담당자는 이 파일의 안내에 따라 서비스를 배포·실행하세요.

- **빌드 환경**: `dev`
- **이미지**: `3rd-docker.ymtech.co.kr:5000/build_test:0.0.1-SNAPSHOT`
- **생성 일시**: 2026-03-26 10:29:37

---

## 📋 이 폴더(docker-dist)에 포함된 파일

| 파일 | 설명 |
|------|------|
| `docker-compose.yml` | 컨테이너 실행 설정 (`.env` 파일과 함께 사용) |
| `install_docker_service.sh` | 서비스 자동 설치 스크립트 (Systemd/SysVinit 등록 포함) |
| `utils.sh` | 공통 유틸리티 스크립트 |
| `config/` | 애플리케이션 설정 파일 (Host Mount용 — 수정 가능) |
| `.app-env.properties` | 로그 경로 등 배포 환경 기본값 |
| `DEPLOY-GUIDE.md` | 이 파일 |

---

## 🚀 배포 순서

### 1. 이 폴더를 서버로 전송

```bash
# SCP 예시 (로컬 PC → 서버)
scp -r build/docker-dist/ user@your-server:/home/user/
```

### 2. 서버 접속 후 Docker 로그인 (Private Registry인 경우)

```bash
docker login 3rd-docker.ymtech.co.kr:5000
```

### 3. Docker 이미지 Pull

```bash
docker pull 3rd-docker.ymtech.co.kr:5000/build_test:0.0.1-SNAPSHOT
```

### 4-a. 자동 설치 (서비스 등록 포함, 권장)

Systemd/SysVinit 서비스로 등록하고 재부팅 시에도 자동 시작되도록 설정합니다.

```bash
cd /home/user/docker-dist
sudo ./install_docker_service.sh
```

> 스크립트 실행 시 **설치 경로**, **로그 경로**를 대화형으로 입력합니다.
> `.env` 파일이 자동으로 생성됩니다.

### 4-b. 수동 실행 (docker compose 직접)

Systemd 등록 없이 바로 컨테이너를 실행하려면:

```bash
cd /home/user/docker-dist

# .env 파일 직접 작성
cat > .env <<EOF
APP_NAME=build_test
DOCKER_IMAGE=3rd-docker.ymtech.co.kr:5000/build_test:0.0.1-SNAPSHOT
LOG_PATH=/var/log/build_test
DEST_DIR=$(pwd)
EOF

mkdir -p /var/log/build_test

# 컨테이너 실행
docker compose up -d
```

---

## 🔍 운영 명령어

```bash
# 컨테이너 상태 확인
docker ps | grep build_test

# 실시간 로그 확인
docker logs -f --tail 200 build_test-app

# 서비스 재시작 (Systemd인 경우)
sudo systemctl restart build_test

# 컨테이너 직접 재시작
docker compose restart

# 서비스 중지
docker compose down
```

---

## ⚙️ 설정 파일 변경 방법

`config/` 폴더의 파일(예: `application.yml`, `log4j2.yml`)은 컨테이너에 **Host Mount** 되어 있습니다.
파일을 수정한 뒤 컨테이너를 재시작하면 **이미지 재빌드 없이** 즉시 반영됩니다.

```bash
# 설정 파일 수정 후
docker compose restart
# 또는
sudo systemctl restart build_test
```
