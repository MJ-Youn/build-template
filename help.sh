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

  🐳 2. dockerBuild (Strategy 1)
     - 로컬 Docker 데몬에 이미지를 빌드하고 스크립트와 함께 Zip 배포 패키지 생성
     - **주의**: 네트워크를 통해 Image Tar를 직접 전송하는 방식이므로, 저장소가 없을 때 유용
     - 산출물: target/dist/{APP_NAME}-docker-{env}.zip
     - 예시: ./mvnw package -PdockerBuild -Pprod

  🔨 3. dockerBuildImage (Strategy 2)
     - 파일 전송(소스 코드 전송)을 서버에서 직접 받아 서버 Local 데몬에 이미지 빌드 시 활용
     - 바로 `docker-compose up` 으로 실행할 수 있도록 `target/docker-dist/` 환경 구성
     - 예시: ./mvnw package -PdockerBuildImage -Pprod

  ☁️ 4. dockerPushImage (Strategy 3)
     - 빌드 후 원격 레지스트리로 Image Push 수행 (CI/CD 표준 동작)
     - 옵션 필요: -DdockerRegistry={REGISTRY_URL} [-DdockerImageTag={TAG_NAME}]
     - 예시: ./mvnw package -PdockerPushImage -Pprod -DdockerRegistry=my.reg.com/repo

  ☸️ 5. k8sBuild
     - Kubernetes 배포 매니페스트 (deployment.yaml 등) 스캐폴딩 생성
     - 산출물: target/dist/{APP_NAME}-k8s-{env}.zip
     - 예시: ./mvnw package -Pk8sBuild -Pprod
================================================================================
EOF
