package io.github.mj_youn.plugin;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * Maven 배포 플러그인의 사용 가이드 및 명령어 안내를 출력하는 Goal입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
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
        🚀 [Distribution Maven Plugin] 빌드 및 배포 가이드
        ================================================================================
        [기본 명령어]
          mvn clean package -Denv=dev       : 개발 환경 배포 패키지(Zip) 생성
          mvn clean package -Denv=prod      : 운영 환경 배포 패키지(Zip) 생성
          mvn distribution:deploy -Denv=prod: 원스탑 배포 (빌드 + 압축해제 + 서비스 설치/구동)

        [환경 지정 옵션 (-Denv=...)]
          지정 시 config.profiles/{env}/ 내 설정 파일들이 패키지 config/ 로 오버레이됩니다.
        ================================================================================
        """;
    getLog().info(msg);
  }
}
