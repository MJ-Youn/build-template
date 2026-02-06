FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# 배포 패키지 내용 복사
# libs, config, bin 폴더가 빌드 컨텍스트 루트에 있다고 가정
# gradle zipDist 실행 후 추출하거나 프로젝트 루트에서 복사

COPY libs/ /app/libs/
COPY config/ /app/config/
COPY bin/ /app/bin/

# 스크립트 실행 권한 부여
RUN chmod +x /app/bin/*.sh

# 포트 노출 (기본 8080)
EXPOSE 8080

# 설정 파일 위치 환경 변수 (스크립트에서 처리하지만 명시)
ENV CONFIG_LOCATION=file:/app/config/

# 애플리케이션 실행
CMD ["/app/bin/start.sh"]
