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
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 프로젝트에 .env.example 템플릿을 기반으로 런타임 환경변수 설정 파일(.env)을 생성하는 Maven Goal입니다.
 *
 * @author 윤명준 (MJ Yun)
 * @since 2026. 10. 28.
 */
@Mojo(name = "initEnv", requiresProject = true, threadSafe = true)
public class InitEnvMojo extends AbstractMojo {

    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    private MavenProject project;

    @Parameter(defaultValue = "${project.basedir}", readonly = true)
    private File basedir;

    /**
     * 환경설정 프로파일 (dev, prod, all 등 또는 지정 안 할 시 루트 .env 단일 생성)
     */
    @Parameter(property = "profile")
    private String profile;

    /**
     * profile 파라미터의 별칭 (env)
     */
    @Parameter(property = "env")
    private String env;

    /**
     * 기존 파일이 존재할 경우 강제 덮어쓰기 여부
     */
    @Parameter(property = "force", defaultValue = "false")
    private boolean force;

    /**
     * force 파라미터의 별칭 (overwrite)
     */
    @Parameter(property = "overwrite", defaultValue = "false")
    private boolean overwrite;

    /**
     * 서비스 애플리케이션 이름 (토큰 치환용)
     */
    @Parameter(property = "appName")
    private String appName;

    /**
     * 서비스 HTTP 포트 (토큰 치환용)
     */
    @Parameter(property = "httpPort", defaultValue = "8443")
    private int httpPort = 8443;

    /**
     * 생성 대상 유형 (기본값: config, docker 지정 시 docker.profiles 에 생성)
     */
    @Parameter(property = "type")
    private String type;

    /**
     * InitEnvMojo 기본 생성자입니다.
     */
    public InitEnvMojo() {}

    /**
     * @see org.apache.maven.plugin.Mojo#execute()
     * @author 윤명준 (MJ Yun)
     * @since 2026. 10. 28.
     */
    @Override
    public void execute() throws MojoExecutionException {
        String resolvedProfile = (profile != null && !profile.isBlank()) ? profile
                : ((env != null && !env.isBlank()) ? env : null);
        boolean isForce = force || overwrite;

        String resolvedAppName = (appName != null && !appName.isBlank()) ? appName
                : (project != null ? project.getArtifactId() : "app");
        String version = (project != null && project.getVersion() != null) ? project.getVersion() : "unspecified";

        Map<String, Object> tokens = new HashMap<>();
        tokens.put("appName", resolvedAppName);
        tokens.put("httpPort", String.valueOf(httpPort));
        tokens.put("version", version);
        tokens.put("dockerImage", resolvedAppName + ":" + version);

        getLog().info("================================================================");
        getLog().info("⚙️  [Distribution Maven Plugin] 런타임 환경설정(.env) 파일 생성");

        try {
            // 1. 소스 템플릿 로드 (로컬 프로젝트 파일 우선 -> 클래스패스 템플릿 폴백)
            // 💡 SERVER_PORT=@httpPort@ 등의 토큰은 빌드/패키징 시점에 application.yml 또는 CLI 옵션에 의해 동적으로 치환되므로 원형을 유지합니다.
            String templateContent = loadEnvExampleTemplate();

            List<File> targetFiles = new ArrayList<>();

            if (resolvedProfile == null || resolvedProfile.isBlank()) {
                // 1. 프로파일 미지정 기본값: 프로젝트 루트의 .env 단일 생성
                targetFiles.add(new File(basedir, ".env"));
            } else if ("all".equalsIgnoreCase(resolvedProfile)) {
                // 2. all: 루트 .env 및 config.profiles 주요 환경별 파일 일괄 생성
                targetFiles.add(new File(basedir, ".env"));
                targetFiles.add(new File(basedir, "config.profiles/dev/.env-dev"));
                targetFiles.add(new File(basedir, "config.profiles/prod/.env-prod"));
            } else {
                // 3. 특정 프로파일 지정 (예: dev, prod 등) -> config.profiles/{profile}/.env-{profile} 단일 생성
                // (명시적으로 -Dtype=docker 지정 시에만 docker.profiles 에 생성)
                boolean isDockerTarget = "docker".equalsIgnoreCase(type);
                if (isDockerTarget) {
                    targetFiles.add(new File(basedir, "docker.profiles/" + resolvedProfile + "/.env-" + resolvedProfile));
                } else {
                    targetFiles.add(new File(basedir, "config.profiles/" + resolvedProfile + "/.env-" + resolvedProfile));
                }
            }

            int createdCount = 0;
            int skippedCount = 0;

            for (File targetFile : targetFiles) {
                if (targetFile.exists() && !isForce) {
                    getLog().info("   ⚠️ [SKIP] 이미 파일이 존재합니다: " + targetFile.getPath() + " (덮어쓰려면 -Dforce=true 옵션 사용)");
                    skippedCount++;
                } else {
                    if (targetFile.getParentFile() != null) {
                        targetFile.getParentFile().mkdirs();
                    }
                    Files.writeString(targetFile.toPath(), templateContent, StandardCharsets.UTF_8);
                    getLog().info("   ✅ [생성 완료] " + targetFile.getAbsolutePath());
                    createdCount++;
                }
            }

            getLog().info("----------------------------------------------------------------");
            getLog().info("📊 [결과] 생성: " + createdCount + "개, 스킵: " + skippedCount + "개");
            getLog().info("💡 [안내] 생성된 .env 파일에서 JVM 힙 메모리(JVM_XMS, JVM_XMX),");
            getLog().info("         서비스 포트(SERVER_PORT), 프로그램 인수(APP_ARGS) 등을 자유롭게 튜닝하세요.");
            getLog().info("================================================================");

        } catch (IOException e) {
            throw new MojoExecutionException(".env 파일 생성 실패: " + e.getMessage(), e);
        }
    }

    /**
     * 프로젝트 로컬 디렉토리 또는 내장 리소스에서 .env.example 템플릿 내용을 로드합니다.
     *
     * @return 로드된 .env.example 템플릿 문자열
     * @throws IOException 템플릿을 찾을 수 없거나 읽기 실패 시
     * @author 윤명준 (MJ Yun)
     * @since 2026. 10. 28.
     */
    private String loadEnvExampleTemplate() throws IOException {
        File[] candidates = new File[] { new File(basedir, "scripts/service/.env.example"),
                new File(basedir, "docker/.env.example"), new File(basedir, ".env.example") };
        for (File candidate : candidates) {
            if (candidate.exists() && candidate.isFile()) {
                getLog().info("📄 [Distribution] 로컬 템플릿 사용: " + candidate.getPath());
                return Files.readString(candidate.toPath(), StandardCharsets.UTF_8);
            }
        }

        InputStream stream = getClass().getClassLoader().getResourceAsStream("template/scripts/service/.env.example");
        if (stream == null) {
            throw new IOException("내장 .env.example 템플릿 리소스를 찾을 수 없습니다.");
        }
        try (stream) {
            getLog().info("📄 [Distribution] 플러그인 내장 템플릿 사용: template/scripts/service/.env.example");
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
