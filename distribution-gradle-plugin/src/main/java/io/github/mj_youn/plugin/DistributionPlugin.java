package io.github.mj_youn.plugin;

import org.apache.tools.ant.filters.ReplaceTokens;
import org.gradle.api.Plugin;
import org.gradle.api.Project;
import org.gradle.api.Task;
import org.gradle.api.file.DuplicatesStrategy;
import org.gradle.api.tasks.bundling.Zip;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 표준 배포 구조(deploy, bin, config, lib, docker)를 일관되게 패키징하고, 내장 스크립트 템플릿 제공 및 프로젝트별 파일
 * 단위 @Override를 지원하는 Gradle 플러그인입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
 */
public class DistributionPlugin implements Plugin<Project> {

    private static final String DEFAULT_ENV = "dev";
    private static final List<String> ENVIRONMENTS = List.of("dev", "prod", "local", "test", "stage");

    /**
     * DistributionPlugin 기본 생성자입니다.
     */
    public DistributionPlugin() {}

    @Override
    public void apply(Project project) {
        // 1. 배포 확장 설정(Extension) 등록 (옵션)
        DistributionExtension extension = project.getExtensions().create("distribution", DistributionExtension.class,
                project);

        // 2. 플러그인 내장 템플릿 자원을 임시 디렉토리에 추출하는 태스크 등록
        File builtinExtractDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(),
                "tmp/dist-template-builtin");

        Task extractTemplateTask = project.getTasks().create("extractBuiltinTemplate", task -> {
            task.setGroup("distribution");
            task.setDescription("플러그인 내장 배포 스크립트 및 도커 템플릿을 추출합니다.");
            task.doLast(t -> extractBuiltinResources(builtinExtractDir));
        });

        // 3. 'package' 태스크 등록 (표준 Zip 포맷)
        project.getTasks().register("package", Zip.class, zip -> {
            zip.setGroup("distribution");
            zip.setDescription("표준 배포용 Zip 패키지를 생성합니다. (내장 스크립트 및 로컬 @Override 지원)");
            configurePackagingTask(project, zip, builtinExtractDir, extractTemplateTask, extension);
        });
    }

    /**
     * Zip 패키징 태스크 설정
     */
    private void configurePackagingTask(Project project, Zip zipTask, File builtinExtractDir, Task extractTemplateTask,
            DistributionExtension extension) {

        zipTask.dependsOn(extractTemplateTask);

        // Spring Boot bootJar 태스크가 존재하면 의존성 연결
        Task bootJarTask = project.getTasks().findByName("bootJar");
        if (bootJarTask != null) {
            zipTask.dependsOn(bootJarTask);
        }

        // ⭐️ 핵심: 중복 파일 처리 전략 = EXCLUDE
        // 먼저 추가된 파일(로컬 프로젝트 파일)이 우선권을 가지며, 나중에 추가되는 파일(내장 템플릿)은 제외됨 (@Override 구현)
        zipTask.setDuplicatesStrategy(DuplicatesStrategy.EXCLUDE);

        String env = project.hasProperty("env") ? String.valueOf(project.property("env")) : DEFAULT_ENV;
        Map<String, Object> tokens = createReplaceTokens(project, extension);

        zipTask.doFirst(task -> {
            project.getLogger().lifecycle("================================================================");
            project.getLogger().lifecycle("🚀 [YM Tech Distribution] 배포 패키지 생성 시작");
            project.getLogger().lifecycle("   - 대상 프로젝트: {}", project.getName());
            project.getLogger().lifecycle("   - 활성 프로파일: {}", env);
            project.getLogger().lifecycle("   - 산출물 이름: {}", zipTask.getArchiveFileName().get());
            project.getLogger().lifecycle("================================================================");
        });

        // -------------------------------------------------------------
        // 1. [우선순위 1] 로컬 프로젝트의 오버라이드(@Override) 파일 적재
        // -------------------------------------------------------------
        File localDeployDir = project.file("scripts/deploy");
        if (localDeployDir.exists()) {
            zipTask.from(localDeployDir, spec -> {
                spec.into("deploy");
                spec.filePermissions(p -> p.unix(0755));
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        File localServiceDir = project.file("scripts/service");
        if (localServiceDir.exists()) {
            zipTask.from(localServiceDir, spec -> {
                spec.into("bin");
                spec.filePermissions(p -> p.unix(0755));
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        File localCommonDir = project.file("scripts/common");
        if (localCommonDir.exists()) {
            zipTask.from(localCommonDir, spec -> {
                spec.into("bin");
                spec.filePermissions(p -> p.unix(0755));
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
            zipTask.from(localCommonDir, spec -> {
                spec.into("deploy");
                spec.filePermissions(p -> p.unix(0755));
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        File localDockerDir = project.file("docker");
        if (localDockerDir.exists()) {
            zipTask.from(localDockerDir, spec -> {
                spec.into("docker");
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        // -------------------------------------------------------------
        // 2. [우선순위 2] 플러그인 내장 기본 템플릿 파일 적재 (로컬에 없는 것만 들어감)
        // -------------------------------------------------------------
        zipTask.from(new File(builtinExtractDir, "scripts/deploy"), spec -> {
            spec.into("deploy");
            spec.filePermissions(p -> p.unix(0755));
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });

        zipTask.from(new File(builtinExtractDir, "scripts/service"), spec -> {
            spec.into("bin");
            spec.filePermissions(p -> p.unix(0755));
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });

        zipTask.from(new File(builtinExtractDir, "scripts/common"), spec -> {
            spec.into("bin");
            spec.filePermissions(p -> p.unix(0755));
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });
        zipTask.from(new File(builtinExtractDir, "scripts/common"), spec -> {
            spec.into("deploy");
            spec.filePermissions(p -> p.unix(0755));
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });

        zipTask.from(new File(builtinExtractDir, "docker"), spec -> {
            spec.into("docker");
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });

        // -------------------------------------------------------------
        // 3. 환경별 설정 파일 (config.profiles/${env} -> config)
        // -------------------------------------------------------------
        File profileDir = project.file("config.profiles/" + env);
        if (profileDir.exists()) {
            zipTask.from(profileDir, spec -> {
                spec.into("config");
                spec.rename(name -> name.replace("-" + env, ""));
            });
        } else {
            // 하위 호환: config/${env}
            File legacyEnvDir = project.file("config/" + env);
            if (legacyEnvDir.exists()) {
                zipTask.from(legacyEnvDir, spec -> {
                    spec.into("config");
                    spec.rename(name -> name.replace("-" + env, ""));
                });
            }
        }

        // 공통 config 파일 (application.yml, log4j2.yml 등)
        File commonConfigDir = project.file("config");
        if (commonConfigDir.exists()) {
            zipTask.from(commonConfigDir, spec -> {
                spec.into("config");
                spec.exclude(ENVIRONMENTS);
                spec.exclude("**/*" + env + "*");
            });
        }

        // -------------------------------------------------------------
        // 4. 애플리케이션 라이브러리 및 JAR (build/libs/*.jar -> lib)
        // -------------------------------------------------------------
        File libsDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(), "libs");
        zipTask.from(libsDir, spec -> {
            spec.include("*.jar");
            spec.exclude("*plain.jar"); // Spring Boot 기본 plain jar 제외
            spec.into("lib");
        });
    }

    /**
     * 스크립트 및 도커 파일 치환용 토큰 맵 생성
     */
    private Map<String, Object> createReplaceTokens(Project project, DistributionExtension extension) {
        Map<String, Object> tokens = new HashMap<>();
        String appName = extension.getAppName() != null && !extension.getAppName().isBlank() ? extension.getAppName()
                : project.getName();
        String version = project.getVersion() != null ? project.getVersion().toString() : "unspecified";

        tokens.put("appName", appName);
        tokens.put("version", version);
        tokens.put("deployMode", "");
        tokens.put("dockerImage", appName + ":" + version);

        if (extension.getExtraTokens() != null) {
            tokens.putAll(extension.getExtraTokens());
        }
        return tokens;
    }

    /**
     * JAR 파일 내부 또는 클래스패스에서 template/ 자원을 파일 시스템으로 추출
     */
    private void extractBuiltinResources(File targetDir) {
        if (!targetDir.exists()) {
            targetDir.mkdirs();
        }

        InputStream manifestStream = getClass().getClassLoader().getResourceAsStream("template-manifest.txt");
        if (manifestStream == null) {
            System.err.println("⚠️ [YM Tech Distribution] template-manifest.txt 를 찾을 수 없습니다.");
            return;
        }

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
                    // 스크립트 파일 실행 권한 부여
                    if (outFile.getName().endsWith(".sh")) {
                        outFile.setExecutable(true, false);
                    }
                }
            }
        } catch (IOException e) {
            throw new RuntimeException("내장 템플릿 추출 실패: " + e.getMessage(), e);
        }
    }
}
