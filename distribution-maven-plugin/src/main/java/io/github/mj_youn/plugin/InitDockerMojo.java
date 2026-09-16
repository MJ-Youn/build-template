package io.github.mj_youn.plugin;

import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;

/**
 * 프로젝트의 docker/ 디렉토리에 배포 유형(JAR 또는 Tomcat)에 맞는 샘플 Dockerfile 및 docker-compose.yml을 생성하는 Maven Goal입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 15.
 * @version 2.0.2
 */
@Mojo(name = "initDocker", requiresProject = true, threadSafe = true)
public class InitDockerMojo extends AbstractMojo {

    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    private MavenProject project;

    @Parameter(defaultValue = "${project.basedir}", readonly = true)
    private File basedir;

    @Parameter(property = "packageType", defaultValue = "jar")
    private String packageType;

    @Parameter(property = "type")
    private String type;

    @Parameter(property = "appName")
    private String appName;

    @Parameter(property = "httpPort", defaultValue = "8080")
    private int httpPort;

    @Parameter(property = "tomcatVersion", defaultValue = "11.0.15")
    private String tomcatVersion;

    /**
     * InitDockerMojo 기본 생성자입니다.
     */
    public InitDockerMojo() {}

    @Override
    public void execute() throws MojoExecutionException {
        String resolvedType = (type != null && !type.isBlank()) ? type : packageType;
        if (resolvedType == null || resolvedType.isBlank()) {
            resolvedType = "jar";
        }
        boolean isTomcat = "tomcat".equalsIgnoreCase(resolvedType) || "war".equalsIgnoreCase(resolvedType);

        String resolvedAppName = (appName != null && !appName.isBlank()) ? appName
                : (project != null ? project.getArtifactId() : "app");

        Map<String, Object> tokens = new HashMap<>();
        tokens.put("appName", resolvedAppName);
        tokens.put("httpPort", String.valueOf(httpPort));
        tokens.put("tomcatVersion", tomcatVersion);
        tokens.put("appType", resolvedType);

        File dockerDir = new File(basedir, "docker");
        if (!dockerDir.exists()) {
            dockerDir.mkdirs();
        }

        try {
            // 1. 배포 타입에 맞는 주 Dockerfile 및 docker-compose.yml 생성
            String activeDockerTemplate = isTomcat ? "template/docker/Dockerfile-tomcat" : "template/docker/Dockerfile-jar";
            String activeComposeTemplate = isTomcat ? "template/docker/docker-compose-tomcat.yml" : "template/docker/docker-compose-jar.yml";

            File activeDockerFile = new File(dockerDir, "Dockerfile");
            File activeComposeFile = new File(dockerDir, "docker-compose.yml");

            copyTemplateResource(activeDockerTemplate, activeDockerFile, tokens);
            copyTemplateResource(activeComposeTemplate, activeComposeFile, tokens);

            getLog().info("================================================================");
            getLog().info("🐳 [Distribution] Docker 설정 생성 완료 (배포 유형: " + resolvedType.toUpperCase() + ")");
            getLog().info("   - 생성된 Dockerfile     : " + activeDockerFile.getAbsolutePath());
            getLog().info("   - 생성된 docker-compose : " + activeComposeFile.getAbsolutePath());
            getLog().info("================================================================");

            // 비교 가이드 출력
            new ShowDockerMojo().execute();

        } catch (IOException e) {
            throw new MojoExecutionException("Docker 템플릿 생성 실패: " + e.getMessage(), e);
        }
    }

    private void copyTemplateResource(String resourcePath, File targetFile, Map<String, Object> tokens) throws IOException {
        InputStream stream = getClass().getClassLoader().getResourceAsStream(resourcePath);
        if (stream == null) {
            throw new IOException("클래스패스 템플릿을 찾을 수 없습니다: " + resourcePath);
        }
        try (stream) {
            String content = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            if (tokens != null) {
                for (Map.Entry<String, Object> entry : tokens.entrySet()) {
                    String placeholder = "@" + entry.getKey() + "@";
                    content = content.replace(placeholder, String.valueOf(entry.getValue()));
                }
            }
            if (targetFile.getParentFile() != null) {
                targetFile.getParentFile().mkdirs();
            }
            Files.writeString(targetFile.toPath(), content, StandardCharsets.UTF_8);
        }
    }
}
