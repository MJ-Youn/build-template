package io.github.mj_youn.plugin;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * Maven 배포 플러그인의 사용 가이드 및 명령어 안내를 출력하는 Goal입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 15.
 */
@Mojo(name = "help", requiresProject = false, threadSafe = true)
public class HelpMojo extends AbstractMojo {

    /**
     * HelpMojo 기본 생성자입니다.
     */
    public HelpMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        String msg = """
================================================================================
🚀 [Distribution Maven Plugin 3.0.0] 빌드 및 배포 가이드
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

[🎛️ CLI 파라미터 옵션]
  -Denv=dev|prod|local|test|stage         : 배포 환경 프로파일 지정
                                            config.profiles/{env}/ 의 설정 파일이
                                            패키지 config/ 로 오버레이됩니다.
  -Dos=linux|windows|all                  : 배포 대상 운영체제 지정 (기본값: linux)
                                            linux  : *.sh 스크립트만 포함 (*.bat 제외)
                                            windows: *.bat 스크립트만 포함 (*.sh 제외)
                                            all    : *.sh 및 *.bat 스크립트 모두 포함
  -DpackageType=jar|tomcat                : 배포 유형 CLI 오버라이드
  -Dtype=jar|tomcat                       : 배포 유형 CLI 오버라이드 (type alias)
  -DhttpPort=8443                         : HTTP 서비스 포트 지정 (기본값: 8080)
  -DtomcatVersion=11.0.15                 : Apache Tomcat 버전 지정

[🛠️ pom.xml DSL 설정]
  <configuration>
    <appName>my-service</appName>           <!-- 서비스 이름 (기본값: artifactId) -->
    <packageType>jar</packageType>          <!-- 기본 배포 유형: jar 또는 tomcat -->
    <httpPort>8080</httpPort>               <!-- 서비스 포트 (기본값: 8080) -->
    <tomcatVersion>11.0.15</tomcatVersion>  <!-- Tomcat 버전 (Tomcat 모드 전용) -->
  </configuration>

[🔧 유틸리티]
  mvn distribution:initDeployScript       : 프로젝트 루트에 build_deploy.sh 자동 생성
  mvn distribution:initDocker             : 배포 유형에 맞는 Dockerfile & docker-compose 생성
  mvn distribution:initDocker -Dtype=jar  : JAR 배포용 Dockerfile 생성 (libs/ + bin/start.sh)
  mvn distribution:initDocker -Dtype=tomcat : Tomcat 배포용 Dockerfile 생성 (Apache Tomcat + webapps/ROOT)
  mvn distribution:showDocker             : JAR vs Tomcat Dockerfile 구조 및 차이점 콘솔 출력
  mvn distribution:help                   : 이 도움말 출력 (또는 mvn distribution:distHelp)
  ./build_deploy.sh                       : 쉘 스크립트 기반 원스탑 배포

================================================================================
""";
    getLog().info(msg);
  }
}
