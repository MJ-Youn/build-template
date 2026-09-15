package io.github.mj_youn.plugin;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * JAR 배포와 Tomcat 배포의 Docker 컨테이너 구조 및 Dockerfile 차이점을 콘솔에서 확인하는 Maven Goal입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 15.
 * @version 2.0.1
 */
@Mojo(name = "showDocker", requiresProject = false, threadSafe = true)
public class ShowDockerMojo extends AbstractMojo {

    /**
     * ShowDockerMojo 기본 생성자입니다.
     */
    public ShowDockerMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        String guide = """
================================================================================
🐳 [Distribution Maven Plugin 2.0.1] JAR vs Tomcat Dockerfile 아키텍처 비교 가이드
================================================================================

┌─────────────────┬──────────────────────────────────┬──────────────────────────────────┐
│ 비교 항목       │ 📦 JAR 모드 (Executable JAR)     │ 🐱 Tomcat 모드 (Standalone Tomcat)│
├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
│ 베이스 이미지   │ eclipse-temurin:25-jdk-alpine    │ eclipse-temurin:25-jdk-alpine +  │
│                 │                                  │ Apache Tomcat 바이너리 자동 설치 │
├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
│ 빌드 산출물     │ target/*.jar                     │ target/exploded-webapps/ROOT/    │
│                 │ (Spring Boot 실행 가능 단일 JAR) │ (또는 ROOT.war)                  │
├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
│ 컨테이너 복사   │ COPY libs/ /app/libs/            │ COPY webapps/ROOT/ .../webapps/ROOT/
│                 │ COPY config/ /app/config/        │ COPY tomcat/conf/ .../conf/      │
│                 │ COPY bin/ /app/bin/              │ COPY tomcat/bin/setenv.sh .../   │
│                 │                                  │ COPY config/ .../config/         │
├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
│ 실행 엔트리포인트│ ENTRYPOINT ["/app/bin/start.sh"] │ ENTRYPOINT ["catalina.sh", "run"]│
├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
│ 주요 볼륨 마운트│ -v ./config:/app/config          │ -v ./webapps/ROOT:.../ROOT       │
│                 │ -v ./log:/log                    │ -v ./tomcat/conf:.../conf        │
│                 │                                  │ -v ./config:.../config           │
│                 │                                  │ -v ./log/tomcat:.../logs         │
├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
│ 주요 용도 및 장점│ 경량 마이크로서비스, 빠른 기동,   │ 엔터프라이즈 레거시 호환, JNDI/Datasource,
│                 │ 단일 패키지 배포 표준            │ 외부 설정 동적 튜닝, Exploded 무중단 갱신
└─────────────────┴──────────────────────────────────┴──────────────────────────────────┘

[💡 사용 명령어]
  1. 현재 설정 기반 생성 : mvn distribution:initDocker
  2. JAR 배포용 강제 생성 : mvn distribution:initDocker -Dtype=jar
  3. Tomcat용 강제 생성  : mvn distribution:initDocker -Dtype=tomcat
  4. 본 비교 가이드 재출력: mvn distribution:showDocker
================================================================================
""";
        getLog().info(guide);
    }
}
