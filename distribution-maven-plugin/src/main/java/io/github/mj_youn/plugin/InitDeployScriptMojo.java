package io.github.mj_youn.plugin;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;

/**
 * 프로젝트 루트에 배포 자동화 쉘 스크립트(build_deploy.sh)를 생성하는 Maven 플러그인 Goal입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 09.
 */
@Mojo(name = "initDeployScript", requiresProject = true, threadSafe = true)
public class InitDeployScriptMojo extends AbstractMojo {

    @Parameter(defaultValue = "${project.basedir}", readonly = true)
    private File basedir;

    /**
     * InitDeployScriptMojo 기본 생성자입니다.
     */
    public InitDeployScriptMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        File targetFile = new File(basedir, "build_deploy.sh");
        InputStream stream = getClass().getClassLoader().getResourceAsStream("template/build_deploy.sh");
        if (stream == null) {
            getLog().error("❌ [Distribution] template/build_deploy.sh 템플릿을 찾을 수 없습니다.");
            return;
        }

        try (stream) {
            Files.copy(stream, targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            targetFile.setExecutable(true, false);
            getLog().info("================================================================");
            getLog().info("✅ [Distribution] build_deploy.sh 가 프로젝트 루트에 생성되었습니다!");
            getLog().info("   - 파일 경로: " + targetFile.getAbsolutePath());
            getLog().info("   - 사용법: ./build_deploy.sh -Denv=dev (또는 ./build_deploy.sh dev)");
            getLog().info("================================================================");
        } catch (IOException e) {
            throw new MojoExecutionException("build_deploy.sh 생성 실패: " + e.getMessage(), e);
        }
    }
}
