package io.github.mj_youn.plugin;

import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * Spring Boot Executable JAR 배포 전용 Zip 패키징 Goal입니다. {@code packageType=jar}를 명시적으로 고정합니다.
 *
 * <p>
 * 사용법:
 * </p>
 * 
 * <pre>
 * mvn distribution:packageJar -Denv=dev
 * </pre>
 *
 * @author MJ Yun
 * @since 2026. 09. 15.
 * @version 2.0.1
 */
@Mojo(name = "packageJar", defaultPhase = LifecyclePhase.PACKAGE, requiresProject = true, threadSafe = true)
public class PackageJarMojo extends DistributionMojo {

    /**
     * PackageJarMojo 기본 생성자입니다.
     */
    public PackageJarMojo() {}

    /**
     * 항상 "jar"를 반환합니다 (고정 모드).
     *
     * @return "jar"
     */
    @Override
    protected String resolvePackageType() {
        return "jar";
    }

    /**
     * JAR 모드임을 고정적으로 반환합니다.
     *
     * @return false
     */
    @Override
    protected boolean isTomcat() {
        return false;
    }

    @Override
    public void execute() throws MojoExecutionException {
        super.execute();
    }
}
