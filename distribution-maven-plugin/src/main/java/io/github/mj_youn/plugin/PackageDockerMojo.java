package io.github.mj_youn.plugin;

import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Execute;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * Docker 이미지를 빌드하고 배포용 스크립트와 함께 Zip으로 패키징하는 Goal입니다. (Strategy 1 - 오프라인/폐쇄망용)
 *
 * <p>사용법:</p>
 * <pre>
 * mvn distribution:packageDocker -Denv=prod
 * mvn distribution:package-docker -Denv=prod
 * </pre>
 *
 * @author MJ Yun
 * @since 2026. 09. 21.
 */
@Mojo(name = "packageDocker", defaultPhase = LifecyclePhase.NONE, requiresProject = true, threadSafe = true)
@Execute(phase = LifecyclePhase.PACKAGE)
public class PackageDockerMojo extends DistributionMojo {

    /**
     * PackageDockerMojo 기본 생성자입니다.
     */
    public PackageDockerMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        executePackageDocker();
    }
}
