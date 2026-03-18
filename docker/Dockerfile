FROM eclipse-temurin:25-jdk-alpine

WORKDIR /app

# Alpine 이미지는 기본적으로 bash가 없으므로 설치
RUN apk add --no-cache bash

# 배포 패키지 내용 복사
# libs, config, bin 폴더가 빌드 컨텍스트 루트에 있다고 가정
# gradle zipDist 실행 후 추출하거나 프로젝트 루트에서 복사

COPY libs/ /app/libs/
COPY config/ /app/config/
COPY bin/start.sh /app/bin/start.sh
COPY bin/utils.sh /app/bin/utils.sh
COPY bin/bootstrap.sh /app/bin/bootstrap.sh

# 스크립트 실행 권한 부여
RUN chmod +x /app/bin/*.sh

# 애플리케이션 실행
CMD ["./bin/start.sh"]
