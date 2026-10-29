package io.github.mj_youn.plugin;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * Maven 배포 플러그인의 사용 가이드 및 명령어 안내를 출력하는 Goal입니다.
 *
 * @author 윤명준 (MJ Yun)
 * @since 2026. 09. 15.
 */
@Mojo(name = "help", requiresProject = false, threadSafe = true)
public class HelpMojo extends AbstractMojo {

  /**
   * HelpMojo 기본 생성자입니다.
   */
  public HelpMojo() {}

  /**
   * @see org.apache.maven.plugin.Mojo#execute()
   * @author 윤명준 (MJ Yun)
   * @since 2026. 09. 15.
   */
  @Override
  public void execute() throws MojoExecutionException {
    String msg = """
        ================================================================================
        🚀 [Distribution Maven Plugin 3.5.0] 빌드 및 배포 가이드
        ================================================================================

        [📦 JAR 모드 명령어 (Executable JAR 배포)]
          mvn distribution:packageJar -Denv=dev    : JAR 기반 배포 패키지(Zip) 생성
          mvn distribution:packageJar -Denv=prod   : JAR 기반 운영 패키지(Zip) 생성
          mvn distribution:deploy -Denv=prod       : JAR 원스탑 배포 (빌드 + 설치)

        [🐱 Tomcat 모드 명령어 (Standalone Apache Tomcat 배포)]
          mvn distribution:packageTomcat -Denv=dev : Tomcat 배포 패키지(Zip) 생성 (webapps/ROOT 포함)
          mvn distribution:packageTomcat -Denv=prod: Tomcat 운영 패키지(Zip) 생성
          mvn distribution:deploy -DpackageType=tomcat -Denv=prod : Tomcat 원스탑 배포

        [⚡ 기본 명령어 (DSL/pom.xml packageType 설정 기반)]
          mvn clean package -Denv=dev             : 기본 설정(packageType) 기반 패키지 생성
          mvn distribution:deploy -Denv=dev       : 기본 설정 기반 원스탑 배포

        [🐳 Docker 배포 명령어 (Strategy 1 & 2)]
          mvn distribution:packageDocker -Denv=prod             : Docker 이미지 빌드 후 .tar 추출 + Zip 패키징 (Strategy 1: 오프라인용)
          mvn distribution:packageDockerRemote -Denv=prod -DdockerRegistry=my.reg.com/repo : Docker 이미지 빌드 & 원격 레지스트리 Push
          (별칭: mvn distribution:package-docker / mvn distribution:package-docker-remote / mvn distribution:docker-build-remote)

        [🌱 환경 설정 (.env) 파일 위치 및 우선순위 안내]
          빌드/패키징 시 프로파일(-Denv={env})에 따라 .env 파일이 패키지 루트(.env)에 오버레이됩니다:
            1순위: docker.profiles/{env}/.env-{env} (또는 docker.profiles/{env}/.env) [Docker 전용 1순위]
            2순위: config.profiles/{env}/.env-{env} (또는 config.profiles/{env}/.env) [공통 프로파일 2순위]
            3순위: 프로젝트 루트의 .env                                              [기본 fallback 3순위]
          * 일반 서버 실행 시: 루트 .env -> config/.env -> bin/.env 순으로 자동 탐색하여 JVM 옵션 등 주입
          * Docker 실행 시: docker-compose와 동일 경로의 .env 자동 로드 (또는 install_service 실행 시 자동 주입)
          * 샘플 생성: mvn distribution:initDocker 실행 시 docker/.env.example 및 docker.profiles/dev/.env-dev 자동 생성

        [🎛️ CLI 파라미터 옵션]
          -Denv=dev|prod|local|test|stage         : 배포 환경 프로파일 지정
                                                    config.profiles/{env}/ 의 설정 파일이
                                                    패키지 config/ 로 오버레이됩니다.
          -Dos=linux|windows|all                  : 배포 대상 운영체제 지정 (기본값: linux)
                                                    linux  : *.sh 스크립트만 포함 (*.bat 제외)
                                                    windows: *.bat 및 Docker 컨테이너 구동용 *.sh 모두 포함
                                                    all    : *.sh 및 *.bat 스크립트 모두 포함
          -DpackageType=jar|tomcat                : 배포 유형 CLI 오버라이드
          -Dtype=jar|tomcat                       : 배포 유형 CLI 오버라이드 (type alias)
          -DhttpPort=8443                         : HTTP 서비스 포트 지정 (기본값: 8443)
          -DtomcatVersion=11.0.15                 : Apache Tomcat 버전 지정

        [🛠️ pom.xml DSL 설정]
          <configuration>
            <appName>my-service</appName>           <!-- 서비스 이름 (기본값: artifactId) -->
            <packageType>jar</packageType>          <!-- 기본 배포 유형: jar 또는 tomcat -->
            <httpPort>8443</httpPort>               <!-- 서비스 포트 (기본값: 8443) -->
            <tomcatVersion>11.0.15</tomcatVersion>  <!-- Tomcat 버전 (Tomcat 모드 전용) -->
          </configuration>

        [🔧 유틸리티]
          mvn distribution:initDeployScript       : 현재 OS에 맞는 build_deploy.sh(.bat) 자동 생성 (옵션: -Dos=all)
          mvn distribution:initDocker             : 배포 유형에 맞는 Dockerfile & docker-compose 생성
          mvn distribution:initDocker -Dtype=jar  : JAR 배포용 Dockerfile 생성 (libs/ + bin/start.sh)
          mvn distribution:initDocker -Dtype=tomcat : Tomcat 배포용 Dockerfile 생성 (Apache Tomcat + webapps/ROOT)
          mvn distribution:initEnv                : Docker Compose 환경변수(.env) 생성 (docker.profiles/dev/.env-dev)
          mvn distribution:initApplicationEnv     : Spring Boot 런타임 설정(application.env) 생성 (config.profiles/dev/application-dev.env)
          mvn distribution:showDocker             : JAR vs Tomcat Dockerfile 구조 및 차이점 콘솔 출력
          mvn distribution:help                   : 이 도움말 출력 (또는 mvn distribution:distHelp)
          ./build_deploy.sh                       : 쉘 스크립트 기반 원스탑 배포 (Windows: build_deploy.bat)

        ================================================================================
        """;
    getLog().info(msg);
  }
}
