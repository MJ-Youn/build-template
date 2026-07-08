#!/usr/bin/env bash

cat << 'EOF'
================================================================================
🚀 [Build Template] 빌드 및 배포 가이드 (Spring Boot Boilerplate)
================================================================================
💡 초기화 스크립트 (init.sh): 
   명령어 `./init.sh` 를 통해 패키지명, 포트포워딩 등을 입력하여 자동 설정할 수 있습니다!

이 프로젝트는 여러 빌드/배포 환경(Legacy, Docker, K8s)을 지원합니다.

[기본 빌드 명령어]
  ./mvnw package            : 표준 빌드 수행 (기본 패키징 포함)
  ./mvnw clean              : 빌드 결과물 정리

[환경 지정 프로필 (-P...)]
  모든 배포 태스크에 환경(`dev`, `prod`, `local` 등)을 지정할 수 있습니다.
  지정 시 `config/{env}/` 및 `scripts/{env}/` 내의 파일들이 오버레이(덮어쓰기) 됩니다.
  예시: ./mvnw package -Pprod

[배포 프로필/태스크 (Distribution Tasks)]
  📦 1. package
     - 일반 서버(Legacy / Docker 선택 가능) 배포용 Zip 생성
     - 산출물: target/dist/{APP_NAME}-{version}-{env}.dist.zip
     - 포함 내용: JAR + Scripts + Config + docker/ (Dockerfile, docker-compose.yml)
     - 서버 배포 시 install_service.sh를 실행하면 Legacy 또는 Docker 방식을 선택할 수 있습니다.
     - 예시: ./mvnw package -Pprod

  🐳 2. dockerBuildOffline (Strategy 1 - 오프라인/폐쇄망 환경용)
     - [타겟 환경] 외부 인터넷이나 레지스트리 접근이 불가한 폐쇄망 서버
     - [작업 내용] 이미지를 빌드하고 .tar로 추출하여 스크립트와 함께 Zip 압축
     - [전송 방식] 완성된 Zip 파일을 운영 서버로 직접 복사(전송)해야 함
     - [주요 산출물] target/dist/{APP_NAME}-docker-{env}.zip
     - [실행 예시] ./mvnw package -Pprod && ./bin/docker-build-offline.sh prod

  🔨 3. dockerBuildLocal (Strategy 2 - 운영 서버 직접 빌드용)
     - [타겟 환경] 배포할 운영 서버 내에서 소스를 직접 빌드하는 환경
     - [작업 내용] 로컬 데몬에 이미지를 만들고 즉시 실행할 수 있도록 환경 구성
     - [전송 방식] 파일 전송 불필요 (바로 cd target/docker-dist 후 실행)
     - [주요 산출물] 로컬 Docker Image + target/docker-dist/ 폴더
     - [실행 예시] ./mvnw package -Pprod && ./bin/docker-build-local.sh prod

  ☁️ 4. dockerBuildRemote (Strategy 3 - 표준 CI/CD 파이프라인용)
     - [타겟 환경] AWS ECR, Docker Hub 등의 원격 저장소를 활용하는 환경
     - [작업 내용] Docker 이미지를 빌드하고 지정된 원격 레지스트리로 push
     - [전송 방식] 파일 전송 불필요 (운영 서버에서 docker pull로 수신)
     - [주요 산출물] 원격 레지스트리에 업로드된 Docker Image
     - [옵션 필수] -DdockerRegistry={REGISTRY_URL} (선택: -DdockerImageTag={TAG_NAME})
     - [실행 예시] ./mvnw package -Pprod && ./bin/docker-build-remote.sh my.reg.com/repo prod

  ☸️ 5. k8sBuild
     - Kubernetes 배포 매니페스트 (deployment.yaml 등) 스캐폴딩 생성
     - 산출물: target/dist/{APP_NAME}-k8s-{env}.zip
     - 예시: ./mvnw package -Pk8sBuild -Pprod
================================================================================
EOF
