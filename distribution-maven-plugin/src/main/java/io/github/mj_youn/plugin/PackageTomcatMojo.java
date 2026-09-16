package io.github.mj_youn.plugin;

import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;

/**
 * Standalone Apache Tomcat 11 배포 전용 Zip 패키징 Goal입니다. {@code packageType=tomcat}을 명시적으로 고정합니다.
 *
 * <p>
 * 사용법:
 * </p>
 * 
 * <pre>
 * mvn distribution:packageTomcat -Denv=dev
 * </pre>
 *
 * @author MJ Yun
 * @since 2026. 09. 15.
 * @version 2.0.2
 */
@Mojo(name = "packageTomcat", defaultPhase = LifecyclePhase.PACKAGE, requiresProject = true, threadSafe = true)
public class PackageTomcatMojo extends DistributionMojo {

    /**
     * PackageTomcatMojo 기본 생성자입니다.
     */
    public PackageTomcatMojo() {}

    /**
     * 항상 "tomcat"을 반환합니다 (고정 모드).
     *
     * @return "tomcat"
     */
    @Override
    protected String resolvePackageType() {
        return "tomcat";
    }

    /**
     * Tomcat 모드임을 고정적으로 반환합니다.
     *
     * @return true
     */
    @Override
    protected boolean isTomcat() {
        return true;
    }

    @Override
    public void execute() throws MojoExecutionException {
        super.execute();
    }
}
