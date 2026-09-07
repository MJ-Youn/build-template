package io.github.mj_youn.plugin;

import org.apache.commons.compress.archivers.zip.ZipArchiveEntry;
import org.apache.commons.compress.archivers.zip.ZipFile;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Execute;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.util.Enumeration;

/**
 * Maven 프로젝트의 패키지 빌드 후 Zip을 자동으로 풀어 install_service.sh를 실행하는 원스탑 배포 플러그인 Goal입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
 */
@Mojo(name = "deploy", defaultPhase = LifecyclePhase.NONE, requiresProject = true, threadSafe = true)
@Execute(phase = LifecyclePhase.PACKAGE)
public class DeployMojo extends DistributionMojo {

    /**
     * DeployMojo 기본 생성자입니다.
     */
    public DeployMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        // 1. 부모의 package 로직 실행 (Zip 생성)
        super.execute();

        File outputDirectory = getOutputDirectory();
        File targetZip = new File(outputDirectory, getProjectArtifactId() + "-" + getProjectVersion() + ".zip");
        File unpackDir = new File(outputDirectory, "unpacked");

        getLog().info("================================================================");
        getLog().info("🚀 [Distribution - Maven] 원스탑 서비스 배포(distribution:deploy) 시작");
        getLog().info("   - 패키지 파일: " + targetZip.getAbsolutePath());
        getLog().info("   - 압축 해제 경로: " + unpackDir.getAbsolutePath());
        getLog().info("================================================================");

        if (!targetZip.exists()) {
            throw new MojoExecutionException("배포 패키지 파일이 존재하지 않습니다: " + targetZip.getAbsolutePath());
        }

        // 2. 압축 해제
        deleteRecursively(unpackDir);
        unpackDir.mkdirs();

        try (ZipFile zipFile = new ZipFile(targetZip)) {
            Enumeration<ZipArchiveEntry> entries = zipFile.getEntries();
            while (entries.hasMoreElements()) {
                ZipArchiveEntry entry = entries.nextElement();
                File entryFile = new File(unpackDir, entry.getName());
                if (entry.isDirectory()) {
                    entryFile.mkdirs();
                } else {
                    File parent = entryFile.getParentFile();
                    if (parent != null && !parent.exists()) {
                        parent.mkdirs();
                    }
                    try (InputStream is = zipFile.getInputStream(entry);
                            FileOutputStream fos = new FileOutputStream(entryFile)) {
                        is.transferTo(fos);
                    }
                    if (entry.getUnixMode() > 0 && (entry.getUnixMode() & 0111) != 0) {
                        entryFile.setExecutable(true, false);
                    }
                }
            }
        } catch (Exception e) {
            throw new MojoExecutionException("Zip 압축 해제 실패: " + e.getMessage(), e);
        }

        // 3. deploy/install_service.sh 실행
        File installScript = new File(unpackDir, "deploy/install_service.sh");
        if (!installScript.exists()) {
            throw new MojoExecutionException(
                    "deploy/install_service.sh 스크립트를 찾을 수 없습니다: " + installScript.getAbsolutePath());
        }
        installScript.setExecutable(true, false);

        try {
            ProcessBuilder pb = new ProcessBuilder("./install_service.sh");
            pb.directory(installScript.getParentFile());
            pb.inheritIO();
            Process process = pb.start();
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                throw new MojoExecutionException("install_service.sh 실행이 비정상 종료되었습니다 (코드: " + exitCode + ")");
            }
        } catch (Exception e) {
            throw new MojoExecutionException("서비스 설치 스크립트 실행 실패: " + e.getMessage(), e);
        }
    }

    private void deleteRecursively(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursively(child);
                }
            }
        }
        file.delete();
    }
}
