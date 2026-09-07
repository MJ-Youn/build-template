package io.github.mj_youn.plugin;

import org.apache.commons.compress.archivers.zip.ZipArchiveEntry;
import org.apache.commons.compress.archivers.zip.ZipArchiveOutputStream;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.*;

/**
 * Maven 프로젝트를 위한 표준 배포 Zip 패키징 플러그인입니다. 내장 배포 스크립트 템플릿 및 파일 단위 @Override를 완벽하게 지원합니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
 */
@Mojo(name = "package", defaultPhase = LifecyclePhase.PACKAGE, requiresProject = true, threadSafe = true)
public class DistributionMojo extends AbstractMojo {

    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    private MavenProject project;

    @Parameter(property = "appName", defaultValue = "${project.artifactId}")
    private String appName;

    @Parameter(property = "env", defaultValue = "dev")
    private String env;

    @Parameter(defaultValue = "${project.build.directory}", required = true)
    private File outputDirectory;

    private static final List<String> ENVIRONMENTS = List.of("dev", "prod", "local", "test", "stage");

    /**
     * DistributionMojo 기본 생성자입니다.
     */
    public DistributionMojo() {}

    /**
     * 출력 디렉토리 경로를 반환합니다.
     *
     * @return 출력 디렉토리 File 인스턴스
     */
    protected File getOutputDirectory() {
        return outputDirectory;
    }

    /**
     * 프로젝트의 ArtifactId를 반환합니다.
     *
     * @return 프로젝트 ArtifactId 문자열
     */
    protected String getProjectArtifactId() {
        return project.getArtifactId();
    }

    /**
     * 프로젝트의 Version을 반환합니다.
     *
     * @return 프로젝트 Version 문자열
     */
    protected String getProjectVersion() {
        return project.getVersion();
    }

    @Override
    public void execute() throws MojoExecutionException {
        getLog().info("================================================================");
        getLog().info("🚀 [Distribution - Maven] 배포 패키지 생성 시작");
        getLog().info("   - 프로젝트: " + project.getArtifactId());
        getLog().info("   - 활성 프로파일: " + env);
        getLog().info("   - 앱 이름: " + appName);
        getLog().info("================================================================");

        File targetZip = new File(outputDirectory, project.getArtifactId() + "-" + project.getVersion() + ".zip");
        File builtinExtractDir = new File(outputDirectory, "tmp/dist-template-builtin");

        // 1. 내장 템플릿 추출
        extractBuiltinResources(builtinExtractDir);

        // 2. 토큰 맵 생성
        Map<String, String> tokens = new HashMap<>();
        tokens.put("appName", appName);
        tokens.put("version", project.getVersion());
        tokens.put("deployMode", "");
        tokens.put("dockerImage", appName + ":" + project.getVersion());

        // 3. Zip 패키지 생성 (중복 방지 셋을 통해 @Override 구현)
        Set<String> addedEntries = new HashSet<>();

        try (ZipArchiveOutputStream zos = new ZipArchiveOutputStream(new FileOutputStream(targetZip))) {
            zos.setEncoding("UTF-8");

            // --- 3.1. [우선순위 1] 로컬 프로젝트의 @Override 파일 적재 ---
            File projectBasedir = project.getBasedir();

            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/deploy"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/service"), "bin/", 0755, tokens, addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/common"), "bin/", 0755, tokens, addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/common"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "docker"), "docker/", 0644, tokens, addedEntries);

            // --- 3.2. [우선순위 2] 내장 기본 템플릿 파일 적재 (로컬에 없는 것만 추가) ---
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/deploy"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/service"), "bin/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/common"), "bin/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/common"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "docker"), "docker/", 0644, tokens, addedEntries);

            // --- 3.3. 환경별 설정 파일 (config.profiles/${env} -> config) ---
            File profileDir = new File(projectBasedir, "config.profiles/" + env);
            if (!profileDir.exists()) {
                profileDir = new File(projectBasedir, "config/" + env);
            }
            if (profileDir.exists()) {
                addConfigFiles(zos, profileDir, "config/", env, addedEntries);
            }

            // 공통 config 파일 (application.yml 등)
            File commonConfigDir = new File(projectBasedir, "config");
            if (commonConfigDir.exists()) {
                addCommonConfigFiles(zos, commonConfigDir, "config/", env, addedEntries);
            }

            // --- 3.4. 실행 가능한 JAR 파일 (target/*.jar -> lib) ---
            addJarFiles(zos, outputDirectory, "lib/", addedEntries);

            getLog().info("✅ 배포 패키지 생성 완료: " + targetZip.getAbsolutePath());

        } catch (IOException e) {
            throw new MojoExecutionException("배포 패키지 생성 실패: " + e.getMessage(), e);
        }
    }

    private void addDirectoryIfExists(ZipArchiveOutputStream zos, File sourceDir, String zipPathPrefix, int unixMode,
            Map<String, String> tokens, Set<String> addedEntries) throws IOException {
        if (!sourceDir.exists() || !sourceDir.isDirectory())
            return;

        File[] files = sourceDir.listFiles();
        if (files == null)
            return;

        for (File file : files) {
            if (file.isDirectory()) {
                addDirectoryIfExists(zos, file, zipPathPrefix + file.getName() + "/", unixMode, tokens, addedEntries);
            } else {
                String entryName = zipPathPrefix + file.getName();
                if (addedEntries.add(entryName)) {
                    byte[] content = filterTokens(Files.readAllBytes(file.toPath()), tokens);
                    ZipArchiveEntry entry = new ZipArchiveEntry(entryName);
                    entry.setUnixMode(unixMode);
                    entry.setSize(content.length);
                    zos.putArchiveEntry(entry);
                    zos.write(content);
                    zos.closeArchiveEntry();
                }
            }
        }
    }

    private void addConfigFiles(ZipArchiveOutputStream zos, File profileDir, String zipPathPrefix, String currentEnv,
            Set<String> addedEntries) throws IOException {
        File[] files = profileDir.listFiles();
        if (files == null)
            return;

        for (File file : files) {
            if (file.isFile()) {
                String targetName = file.getName().replace("-" + currentEnv, "");
                String entryName = zipPathPrefix + targetName;
                if (addedEntries.add(entryName)) {
                    byte[] content = Files.readAllBytes(file.toPath());
                    ZipArchiveEntry entry = new ZipArchiveEntry(entryName);
                    entry.setUnixMode(0644);
                    entry.setSize(content.length);
                    zos.putArchiveEntry(entry);
                    zos.write(content);
                    zos.closeArchiveEntry();
                }
            }
        }
    }

    private void addCommonConfigFiles(ZipArchiveOutputStream zos, File commonDir, String zipPathPrefix,
            String currentEnv, Set<String> addedEntries) throws IOException {
        File[] files = commonDir.listFiles();
        if (files == null)
            return;

        for (File file : files) {
            if (file.isFile()) {
                if (ENVIRONMENTS.contains(file.getName()) || file.getName().contains(currentEnv)) {
                    continue;
                }
                String entryName = zipPathPrefix + file.getName();
                if (addedEntries.add(entryName)) {
                    byte[] content = Files.readAllBytes(file.toPath());
                    ZipArchiveEntry entry = new ZipArchiveEntry(entryName);
                    entry.setUnixMode(0644);
                    entry.setSize(content.length);
                    zos.putArchiveEntry(entry);
                    zos.write(content);
                    zos.closeArchiveEntry();
                }
            }
        }
    }

    private void addJarFiles(ZipArchiveOutputStream zos, File targetDir, String zipPathPrefix, Set<String> addedEntries)
            throws IOException {
        File[] files = targetDir.listFiles((dir, name) -> name.endsWith(".jar") && !name.endsWith(".original"));
        if (files == null)
            return;

        for (File file : files) {
            String entryName = zipPathPrefix + file.getName();
            if (addedEntries.add(entryName)) {
                byte[] content = Files.readAllBytes(file.toPath());
                ZipArchiveEntry entry = new ZipArchiveEntry(entryName);
                entry.setUnixMode(0644);
                entry.setSize(content.length);
                zos.putArchiveEntry(entry);
                zos.write(content);
                zos.closeArchiveEntry();
            }
        }
    }

    private byte[] filterTokens(byte[] input, Map<String, String> tokens) {
        String content = new String(input, StandardCharsets.UTF_8);
        for (Map.Entry<String, String> entry : tokens.entrySet()) {
            content = content.replace("@" + entry.getKey() + "@", entry.getValue());
        }
        return content.getBytes(StandardCharsets.UTF_8);
    }

    private void extractBuiltinResources(File targetDir) {
        if (!targetDir.exists()) {
            targetDir.mkdirs();
        }

        InputStream manifestStream = getClass().getClassLoader().getResourceAsStream("template-manifest.txt");
        if (manifestStream == null)
            return;

        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(manifestStream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty())
                    continue;

                String resourcePath = "template/" + line;
                InputStream resStream = getClass().getClassLoader().getResourceAsStream(resourcePath);
                if (resStream == null)
                    continue;

                File outFile = new File(targetDir, line);
                File parent = outFile.getParentFile();
                if (parent != null && !parent.exists()) {
                    parent.mkdirs();
                }

                try (resStream) {
                    Files.copy(resStream, outFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                }
            }
        } catch (IOException e) {
            getLog().warn("내장 템플릿 자원 추출 실패: " + e.getMessage());
        }
    }
}
