package io.github.mj_youn.plugin;

import org.apache.commons.compress.archivers.zip.ZipArchiveEntry;
import org.apache.commons.compress.archivers.zip.ZipArchiveInputStream;
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
import java.util.function.Predicate;

/**
 * Maven 프로젝트를 위한 표준 배포 Zip 패키징 플러그인입니다. Executable JAR 및 Standalone Apache Tomcat 11 배포를 모두 지원합니다.
 *
 * <p>
 * 지원 명령어:
 * </p>
 * 
 * <pre>
 *   mvn distribution:package                           (기본: DSL packageType 사용)
 *   mvn distribution:package -DpackageType=tomcat      (Tomcat 모드 지정)
 *   mvn distribution:package -Dtype=tomcat             (단축 CLI 옵션)
 *   mvn distribution:packageTomcat                     (전용 Tomcat 태스크)
 *   mvn distribution:packageJar                        (전용 JAR 태스크)
 * </pre>
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
 * @version 2.0.2
 */
@Mojo(name = "package", defaultPhase = LifecyclePhase.PACKAGE, requiresProject = true, threadSafe = true)
public class DistributionMojo extends AbstractMojo {

    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    private MavenProject project;

    /** 애플리케이션 이름 (기본값: artifactId) */
    @Parameter(property = "appName", defaultValue = "${project.artifactId}")
    private String appName;

    /** 배포 환경 프로파일 (dev, prod, local, test, stage) */
    @Parameter(property = "env", defaultValue = "dev")
    private String env;

    /**
     * 패키지 유형 선택: {@code jar} (Spring Boot Executable JAR) 또는 {@code tomcat} (Standalone Apache
     * Tomcat). CLI에서 {@code -DpackageType=tomcat} 으로 오버라이드 가능합니다.
     */
    @Parameter(property = "packageType", defaultValue = "jar")
    private String packageType;

    /**
     * CLI 단축 속성 (-Dtype=tomcat)으로도 packageType을 지정할 수 있도록 지원합니다. packageType 보다 낮은 우선순위를 가집니다.
     */
    @Parameter(property = "type")
    private String type;

    /** Apache Tomcat 버전 (기본값: 11.0.15) */
    @Parameter(property = "tomcatVersion", defaultValue = "11.0.15")
    private String tomcatVersion;

    /** HTTP 서비스 포트 (기본값: 8080) */
    @Parameter(property = "httpPort", defaultValue = "8080")
    private int httpPort;

    @Parameter(defaultValue = "${project.build.directory}", required = true)
    private File outputDirectory;

    @Parameter(property = "extraDirs")
    private String extraDirs;

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

    /**
     * 실제 패키지 유형을 결정합니다. (type 파라미터 > packageType 파라미터 순서)
     *
     * @return 소문자로 변환된 패키지 유형 문자열 (jar 또는 tomcat)
     */
    protected String resolvePackageType() {
        if (type != null && !type.isBlank()) {
            return type.toLowerCase();
        }
        return packageType != null ? packageType.toLowerCase() : "jar";
    }

    /**
     * Tomcat 모드 여부를 반환합니다.
     *
     * @return tomcat 또는 war 모드이면 true
     */
    protected boolean isTomcat() {
        String pt = resolvePackageType();
        return "tomcat".equalsIgnoreCase(pt) || "war".equalsIgnoreCase(pt);
    }

    @Override
    public void execute() throws MojoExecutionException {
        boolean tomcatMode = isTomcat();
        String resolvedType = resolvePackageType();

        getLog().info("================================================================");
        getLog().info("\ud83d\ude80 [Distribution 2.0.2 - Maven] 배포 패키지 생성 시작");
        getLog().info("   - 프로젝트     : " + project.getArtifactId());
        getLog().info("   - 활성 프로파일: " + env);
        getLog().info("   - 배포 유형    : " + resolvedType.toUpperCase() + " ("
                + (tomcatMode ? "Standalone Tomcat" : "Executable JAR") + ")");
        getLog().info("   - HTTP 포트    : " + httpPort);
        getLog().info("================================================================");

        // Tomcat 모드 사전 조건 검증
        if (tomcatMode) {
            verifyTomcatPrerequisites();
        }

        File targetZip = new File(outputDirectory, project.getArtifactId() + "-" + project.getVersion() + ".zip");
        File builtinExtractDir = new File(outputDirectory, "tmp/dist-template-builtin");

        // 1. 내장 템플릿 추출
        extractBuiltinResources(builtinExtractDir);

        // 2. 토큰 맵 생성
        Map<String, String> tokens = createReplaceTokens(resolvedType);

        // 3. Tomcat 모드: WAR 압축 해제 (webapps/ROOT 준비)
        File explodedWebappsDir = new File(outputDirectory, "exploded-webapps/ROOT");
        if (tomcatMode) {
            File warFile = findWarFile(outputDirectory);
            if (warFile != null && warFile.exists()) {
                getLog().info("\ud83d\udce6 [Distribution] 외장 톰캣 배포를 위해 WAR 압축을 해제합니다: " + warFile.getName());
                deleteRecursively(explodedWebappsDir);
                explodedWebappsDir.mkdirs();
                explodeWar(warFile, explodedWebappsDir);
            } else {
                getLog().warn(
                        "\u26a0\ufe0f [Distribution] Tomcat 모드이지만 target/*.war 파일을 찾을 수 없습니다. 먼저 mvn package를 실행하세요.");
            }
        }

        // 4. Zip 패키지 생성 (중복 방지 셋을 통해 @Override 구현)
        Set<String> addedEntries = new HashSet<>();

        try (ZipArchiveOutputStream zos = new ZipArchiveOutputStream(new FileOutputStream(targetZip))) {
            zos.setEncoding("UTF-8");

            File projectBasedir = project.getBasedir();

            // --- 4.1. [우선순위 1] 로컬 프로젝트의 @Override 파일 적재 ---
            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/deploy"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/service"), "bin/", 0755, tokens, addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/common"), "bin/", 0755, tokens, addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "scripts/common"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(projectBasedir, "docker"), "docker/", 0644, tokens, addedEntries,
                    f -> !f.getName().contains("-jar") && !f.getName().contains("-tomcat"));
            // 로컬 tomcat/ 오버라이드
            addDirectoryIfExists(zos, new File(projectBasedir, "tomcat"), "tomcat/", 0644, tokens, addedEntries);

            // --- 4.2. [우선순위 2] 내장 기본 템플릿 파일 적재 (로컬에 없는 것만 추가) ---
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/deploy"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/service"), "bin/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/common"), "bin/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "scripts/common"), "deploy/", 0755, tokens,
                    addedEntries);
            addDirectoryIfExists(zos, new File(builtinExtractDir, "docker"), "docker/", 0644, tokens, addedEntries,
                    f -> !f.getName().contains("-jar") && !f.getName().contains("-tomcat"));

            // Tomcat 모드: 내장 tomcat/ 설정 + webapps/ROOT 포함
            if (tomcatMode) {
                addDirectoryIfExists(zos, new File(builtinExtractDir, "tomcat"), "tomcat/", 0644, tokens, addedEntries);
                if (explodedWebappsDir.exists()) {
                    addDirectoryIfExists(zos, explodedWebappsDir, "webapps/ROOT/", 0644, null, addedEntries);
                }
            }

            // --- 4.3. 환경별 설정 파일 (config.profiles/${env} -> config) ---
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

            // --- 4.4. 실행 가능한 JAR 파일 ---
            //    Tomcat 모드에서는 WAR가 webapps/ROOT에 Explode되므로 libs/ 불필요
            if (!tomcatMode) {
                addJarFiles(zos, outputDirectory, "libs/", addedEntries);
            }

            // --- 4.5. 추가 복제 디렉토리 (EXTRA_DIRS / extraDirs) ---
            Set<String> extraDirsToCopy = resolveExtraDirs(projectBasedir, env);
            for (String dirName : extraDirsToCopy) {
                File extraDir = new File(projectBasedir, dirName);
                if (extraDir.exists() && extraDir.isDirectory()) {
                    getLog().info("\ud83d\udce6 추가 디렉토리 번들링: " + dirName);
                    addDirectoryIfExists(zos, extraDir, dirName + "/", 0755, tokens, addedEntries);
                } else {
                    getLog().warn("\u26a0\ufe0f 설정된 추가 디렉토리를 찾을 수 없습니다: " + dirName);
                }
            }

        } catch (IOException e) {
            throw new MojoExecutionException("배포 패키지 생성 실패: " + e.getMessage(), e);
        }

        long sizeInMb = targetZip.length() / (1024 * 1024);
        getLog().info("================================================================");
        getLog().info("\u2705 [Distribution 2.0.2] 배포 패키지 생성 완료!");
        getLog().info("   - 산출물 경로: " + targetZip.getAbsolutePath());
        getLog().info("   - 파일 크기  : " + sizeInMb + " MB (" + targetZip.length() + " bytes)");
        getLog().info("================================================================");
    }

    /**
     * 스크립트 및 설정 파일 치환용 토큰 맵 생성
     *
     * @param resolvedType
     *            결정된 패키지 유형
     * @return 토큰 맵
     */
    protected Map<String, String> createReplaceTokens(String resolvedType) {
        Map<String, String> tokens = new HashMap<>();
        String name = (appName != null && !appName.isBlank()) ? appName : project.getArtifactId();
        tokens.put("appName", name);
        tokens.put("version", project.getVersion());
        tokens.put("deployMode", "");
        tokens.put("dockerImage", name + ":" + project.getVersion());
        tokens.put("appType", resolvedType);
        tokens.put("tomcatVersion", tomcatVersion != null ? tomcatVersion : "11.0.15");
        tokens.put("httpPort", String.valueOf(httpPort));
        return tokens;
    }

    /**
     * 외장 톰캣 배포 사전 조건 검증
     *
     * @throws MojoExecutionException
     *             검증 실패 시
     */
    protected void verifyTomcatPrerequisites() throws MojoExecutionException {
        // 1. Maven war packaging 확인
        String packaging = project.getPackaging();
        if (!"war".equalsIgnoreCase(packaging)) {
            String msg = "\n================================================================================\n"
                    + "\u274c [Distribution Plugin - Tomcat 사전 조건 검증 실패]\n"
                    + "--------------------------------------------------------------------------------\n"
                    + "외장 톰캣 배포(packageType='tomcat')를 위해서는 Maven 프로젝트의\n" + "packaging이 'war'여야 합니다.\n\n"
                    + "[해결 방법 예시 - pom.xml]\n" + "  <packaging>war</packaging>\n"
                    + "================================================================================";
            getLog().error(msg);
            throw new MojoExecutionException(
                    "Tomcat 사전 조건 검증 실패: pom.xml의 packaging이 'war'가 아닙니다. (현재: " + packaging + ")");
        }

        // 2. SpringBootServletInitializer 상속 확인
        File srcDir = new File(project.getBasedir(), "src/main/java");
        if (srcDir.exists()) {
            boolean foundSpringBootApp = false;
            boolean extendsServletInitializer = false;
            File springBootAppFile = null;

            try {
                List<File> javaFiles = new ArrayList<>();
                findJavaFiles(srcDir, javaFiles);
                for (File file : javaFiles) {
                    String fileContent = Files.readString(file.toPath(), StandardCharsets.UTF_8);
                    if (fileContent.contains("@SpringBootApplication")) {
                        foundSpringBootApp = true;
                        springBootAppFile = file;
                        if (fileContent.contains("SpringBootServletInitializer") && fileContent.contains("extends")) {
                            extendsServletInitializer = true;
                            break;
                        }
                    }
                }
            } catch (Exception e) {
                getLog().warn("\u26a0\ufe0f [Distribution] Tomcat 사전 검증 중 소스 파일 읽기 실패: " + e.getMessage());
            }

            if (foundSpringBootApp && !extendsServletInitializer) {
                String clsName = springBootAppFile != null ? springBootAppFile.getName().replace(".java", "")
                        : "Application";
                String filePath = springBootAppFile != null ? springBootAppFile.getAbsolutePath() : "src/main/java";
                String msg = String.format(
                        "\n================================================================================\n"
                                + "\u274c [Distribution Plugin - Tomcat 사전 조건 검증 실패]\n"
                                + "--------------------------------------------------------------------------------\n"
                                + "외장 톰캣 배포(packageType='tomcat')를 위해서는 메인 스프링 부트 애플리케이션 클래스가\n"
                                + "'org.springframework.boot.web.servlet.support.SpringBootServletInitializer'를\n"
                                + "반드시 상속(extends)해야 합니다.\n\n" + "[검증 실패 파일]\n  %s\n\n" + "[해결 방법 예시 - %s.java]\n"
                                + "  @SpringBootApplication\n"
                                + "  public class %s extends SpringBootServletInitializer {\n" + "      @Override\n"
                                + "      protected SpringApplicationBuilder configure(SpringApplicationBuilder builder) {\n"
                                + "          return builder.sources(%s.class);\n" + "      }\n" + "  }\n"
                                + "================================================================================",
                        filePath, clsName, clsName, clsName);
                getLog().error(msg);
                throw new MojoExecutionException(
                        "Tomcat 사전 조건 검증 실패: " + clsName + " 클래스가 SpringBootServletInitializer를 상속하지 않았습니다.");
            }
        }

        // 3. provided scope Tomcat 설정 권고
        boolean hasProvidedTomcat = project.getDependencies().stream()
                .anyMatch(d -> "provided".equalsIgnoreCase(d.getScope()) && d.getArtifactId() != null
                        && d.getArtifactId().contains("tomcat"));
        if (!hasProvidedTomcat) {
            getLog().warn("--------------------------------------------------------------------------------\n"
                    + "\u26a0\ufe0f [Distribution Plugin - Tomcat 의존성 설정 권고]\n"
                    + "외장 톰캣 배포 시 내장 톰캣과의 클래스로더 충돌을 방지하기 위해\n" + "pom.xml에 다음 의존성을 provided scope으로 선언하는 것을 권장합니다:\n"
                    + "  <dependency>\n" + "    <groupId>org.springframework.boot</groupId>\n"
                    + "    <artifactId>spring-boot-starter-tomcat</artifactId>\n" + "    <scope>provided</scope>\n"
                    + "  </dependency>\n"
                    + "--------------------------------------------------------------------------------");
        }

        // 4. docker/Dockerfile Tomcat 설정 점검
        File dockerfile = new File(project.getBasedir(), "docker/Dockerfile");
        if (dockerfile.exists()) {
            try {
                String dfContent = Files.readString(dockerfile.toPath(), StandardCharsets.UTF_8);
                if (!dfContent.contains("catalina.sh") && !dfContent.toLowerCase().contains("tomcat")) {
                    getLog().warn("--------------------------------------------------------------------------------\n"
                            + "\u26a0\ufe0f [Distribution Plugin - Dockerfile 점검 권고]\n"
                            + "현재 Tomcat 배포 모드이지만 docker/Dockerfile에서 'catalina.sh run' 또는\n"
                            + "Tomcat 베이스 설정이 감지되지 않았습니다.\n"
                            + "--------------------------------------------------------------------------------");
                }
            } catch (Exception ignored) {
            }
        }

        getLog().info("\u2705 [Distribution] Tomcat 사전 조건 검증 통과!");
    }

    /**
     * WAR 파일을 지정된 디렉토리에 압축 해제합니다.
     *
     * @param warFile
     *            WAR 파일
     * @param targetDir
     *            압축 해제 대상 디렉토리
     * @throws MojoExecutionException
     *             실패 시
     */
    private void explodeWar(File warFile, File targetDir) throws MojoExecutionException {
        try (ZipArchiveInputStream zais = new ZipArchiveInputStream(
                new BufferedInputStream(new FileInputStream(warFile)))) {
            ZipArchiveEntry entry;
            while ((entry = zais.getNextEntry()) != null) {
                File outFile = new File(targetDir, entry.getName());
                if (entry.isDirectory()) {
                    outFile.mkdirs();
                } else {
                    File parent = outFile.getParentFile();
                    if (parent != null && !parent.exists()) {
                        parent.mkdirs();
                    }
                    try (FileOutputStream fos = new FileOutputStream(outFile)) {
                        zais.transferTo(fos);
                    }
                }
            }
        } catch (IOException e) {
            throw new MojoExecutionException("WAR 압축 해제 실패: " + e.getMessage(), e);
        }
    }

    /**
     * 출력 디렉토리에서 WAR 파일을 탐색합니다.
     *
     * @param targetDir
     *            Maven target 디렉토리
     * @return WAR 파일 (없으면 null)
     */
    private File findWarFile(File targetDir) {
        if (targetDir == null || !targetDir.exists())
            return null;
        File[] wars = targetDir.listFiles((dir, name) -> name.endsWith(".war") && !name.endsWith(".original"));
        if (wars != null && wars.length > 0) {
            return wars[0];
        }
        return null;
    }

    private void addDirectoryIfExists(ZipArchiveOutputStream zos, File sourceDir, String zipPathPrefix, int unixMode,
            Map<String, String> tokens, Set<String> addedEntries) throws IOException {
        addDirectoryIfExists(zos, sourceDir, zipPathPrefix, unixMode, tokens, addedEntries, null);
    }

    private void addDirectoryIfExists(ZipArchiveOutputStream zos, File sourceDir, String zipPathPrefix, int unixMode,
            Map<String, String> tokens, Set<String> addedEntries, Predicate<File> fileFilter) throws IOException {
        if (!sourceDir.exists() || !sourceDir.isDirectory())
            return;

        File[] files = sourceDir.listFiles();
        if (files == null)
            return;

        Arrays.sort(files);
        for (File file : files) {
            if (fileFilter != null && !fileFilter.test(file)) {
                continue;
            }
            if (file.isDirectory()) {
                addDirectoryIfExists(zos, file, zipPathPrefix + file.getName() + "/", unixMode, tokens, addedEntries,
                        fileFilter);
            } else {
                String entryName = zipPathPrefix + file.getName();
                if (addedEntries.add(entryName)) {
                    byte[] content = tokens != null ? filterTokens(Files.readAllBytes(file.toPath()), tokens)
                            : Files.readAllBytes(file.toPath());
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
            if (file.isDirectory()) {
                addConfigFiles(zos, file, zipPathPrefix + file.getName() + "/", currentEnv, addedEntries);
            } else if (file.isFile()) {
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
            if (file.isDirectory()) {
                if (ENVIRONMENTS.contains(file.getName()) || file.getName().equals(currentEnv)) {
                    continue;
                }
                addCommonConfigFiles(zos, file, zipPathPrefix + file.getName() + "/", currentEnv, addedEntries);
            } else if (file.isFile()) {
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

    private Set<String> resolveExtraDirs(File projectBasedir, String currentEnv) {
        Set<String> dirs = new LinkedHashSet<>();
        if (extraDirs != null && !extraDirs.trim().isEmpty()) {
            for (String d : extraDirs.split("[,\\s]+")) {
                if (!d.trim().isEmpty())
                    dirs.add(d.trim());
            }
        }
        List<File> envFiles = List.of(new File(projectBasedir, "config.profiles/" + currentEnv + "/.env"),
                new File(projectBasedir, "config/" + currentEnv + "/.env"), new File(projectBasedir, ".env"),
                new File(projectBasedir, "scripts/service/.env"));
        for (File envFile : envFiles) {
            if (envFile.exists() && envFile.isFile()) {
                try {
                    List<String> lines = Files.readAllLines(envFile.toPath(), StandardCharsets.UTF_8);
                    for (String line : lines) {
                        line = line.trim();
                        if (line.startsWith("EXTRA_DIRS=")) {
                            String val = line.substring("EXTRA_DIRS=".length()).trim();
                            val = val.replaceAll("^[\"']|[\"']$", "");
                            for (String d : val.split("[,\\s]+")) {
                                if (!d.trim().isEmpty())
                                    dirs.add(d.trim());
                            }
                        }
                    }
                } catch (Exception ignored) {
                }
            }
        }
        return dirs;
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
        String fileContent = new String(input, StandardCharsets.UTF_8);
        for (Map.Entry<String, String> entry : tokens.entrySet()) {
            fileContent = fileContent.replace("@" + entry.getKey() + "@", entry.getValue());
        }
        return fileContent.getBytes(StandardCharsets.UTF_8);
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

    private void findJavaFiles(File dir, List<File> result) {
        File[] files = dir.listFiles();
        if (files == null)
            return;
        for (File f : files) {
            if (f.isDirectory()) {
                findJavaFiles(f, result);
            } else if (f.getName().endsWith(".java")) {
                result.add(f);
            }
        }
    }

    /**
     * 디렉토리를 재귀적으로 삭제합니다.
     *
     * @param file
     *            삭제 대상 파일 또는 디렉토리
     */
    protected void deleteRecursively(File file) {
        if (file == null || !file.exists())
            return;
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
