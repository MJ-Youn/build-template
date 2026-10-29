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
 * @author 윤명준 (MJ Yun)
 * @since 2026. 09. 15.
 */
@Mojo(name = "packageJar", defaultPhase = LifecyclePhase.PACKAGE, requiresProject = true, threadSafe = true)
public class PackageJarMojo extends DistributionMojo {

    /**
     * PackageJarMojo 기본 생성자입니다.
     */
    public PackageJarMojo() {}

    /**
     * @see io.github.mj_youn.plugin.DistributionMojo#resolvePackageType()
     * @author 윤명준 (MJ Yun)
     * @since 2026. 09. 15.
     */
    @Override
    protected String resolvePackageType() {
        return "jar";
    }

    /**
     * @see io.github.mj_youn.plugin.DistributionMojo#isTomcat()
     * @author 윤명준 (MJ Yun)
     * @since 2026. 09. 15.
     */
    @Override
    protected boolean isTomcat() {
        return false;
    }

    /**
     * @see io.github.mj_youn.plugin.DistributionMojo#execute()
     * @author 윤명준 (MJ Yun)
     * @since 2026. 09. 15.
     */
    @Override
    public void execute() throws MojoExecutionException {
        super.execute();
    }
}
