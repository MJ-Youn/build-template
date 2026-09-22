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
     * 배포 스크립트 대상 OS (linux | windows | all)
     */
    @Parameter(property = "os")
    private String os;

    /**
     * 배포 스크립트 대상 OS 별칭
     */
    @Parameter(property = "targetOs")
    private String targetOs;

    /**
     * InitDeployScriptMojo 기본 생성자입니다.
     */
    public InitDeployScriptMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        String currentOsName = System.getProperty("os.name", "");
        boolean isSystemWindows = currentOsName.toLowerCase().contains("win");

        String osOption = (os != null && !os.isBlank()) ? os.trim().toLowerCase()
                : ((targetOs != null && !targetOs.isBlank()) ? targetOs.trim().toLowerCase() : null);

        boolean generateSh;
        boolean generateBat;

        if ("windows".equals(osOption) || "win".equals(osOption)) {
            generateSh = false;
            generateBat = true;
        } else if ("linux".equals(osOption) || "unix".equals(osOption) || "mac".equals(osOption) || "macos".equals(osOption)) {
            generateSh = true;
            generateBat = false;
        } else if ("all".equals(osOption)) {
            generateSh = true;
            generateBat = true;
        } else {
            // 기본값: 현재 호스트 시스템 OS 감지
            generateSh = !isSystemWindows;
            generateBat = isSystemWindows;
        }

        getLog().info("================================================================");
        getLog().info("🚀 [Distribution Maven Plugin] 배포 스크립트 생성 (현재 OS: " + currentOsName + ")");

        if (generateSh) {
            File targetFile = new File(basedir, "build_deploy.sh");
            InputStream stream = getClass().getClassLoader().getResourceAsStream("template/build_deploy.sh");
            if (stream == null) {
                getLog().error("❌ [Distribution] template/build_deploy.sh 템플릿을 찾을 수 없습니다.");
            } else {
                try (stream) {
                    Files.copy(stream, targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                    targetFile.setExecutable(true, false);
                    getLog().info("✅ build_deploy.sh (Linux/macOS용) 생성 완료!");
                    getLog().info("   - 파일 경로: " + targetFile.getAbsolutePath());
                    getLog().info("   - 사용법: ./build_deploy.sh dev (또는 ./build_deploy.sh prod --sudo)");
                } catch (IOException e) {
                    throw new MojoExecutionException("build_deploy.sh 생성 실패: " + e.getMessage(), e);
                }
            }
        }

        if (generateBat) {
            File batTargetFile = new File(basedir, "build_deploy.bat");
            InputStream batStream = getClass().getClassLoader().getResourceAsStream("template/build_deploy.bat");
            if (batStream == null) {
                getLog().error("❌ [Distribution] template/build_deploy.bat 템플릿을 찾을 수 없습니다.");
            } else {
                try (batStream) {
                    Files.copy(batStream, batTargetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                    getLog().info("✅ build_deploy.bat (Windows용) 생성 완료!");
                    getLog().info("   - 파일 경로: " + batTargetFile.getAbsolutePath());
                    getLog().info("   - 사용법: build_deploy.bat dev");
                } catch (IOException e) {
                    throw new MojoExecutionException("build_deploy.bat 생성 실패: " + e.getMessage(), e);
                }
            }
        }
        getLog().info("================================================================");
    }
}
