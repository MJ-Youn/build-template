package io.github.mj_youn.plugin;

import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Execute;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * Docker 이미지를 빌드하고 원격 레지스트리에 Push하는 Goal입니다. (Strategy 2 - CI/CD 파이프라인용)
 *
 * <p>사용법:</p>
 * <pre>
 * mvn distribution:packageDockerRemote -Denv=prod -DdockerRegistry=my.reg.com/repo
 * mvn distribution:package-docker-remote -Denv=prod -DdockerRegistry=my.reg.com/repo
 * </pre>
 *
 * @author MJ Yun
 * @since 2026. 09. 21.
 */
@Mojo(name = "packageDockerRemote", defaultPhase = LifecyclePhase.NONE, requiresProject = true, threadSafe = true)
@Execute(phase = LifecyclePhase.PACKAGE)
public class PackageDockerRemoteMojo extends DistributionMojo {

    /**
     * PackageDockerRemoteMojo 기본 생성자입니다.
     */
    public PackageDockerRemoteMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        executePackageDockerRemote();
    }
}
