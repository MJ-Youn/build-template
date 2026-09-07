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
        var packageTaskProvider = project.getTasks().register("package", Zip.class, zip -> {
            zip.setGroup("distribution");
            zip.setDescription("표준 배포용 Zip 패키지를 생성합니다. (내장 스크립트 및 로컬 @Override 지원)");
            configurePackagingTask(project, zip, builtinExtractDir, extractTemplateTask, extension);
        });

        // 4. 'deployService' 태스크 등록 (원스탑 빌드 및 서비스 설치/구동)
        project.getTasks().register("deployService", task -> {
            task.setGroup("distribution");
            task.setDescription("패키지 빌드 후 Zip을 자동으로 풀어 install_service.sh를 실행하여 서비스를 배포/구동합니다.");
            task.dependsOn(packageTaskProvider);
            task.doLast(t -> {
                Zip zipTask = packageTaskProvider.get();
                File zipFile = zipTask.getArchiveFile().get().getAsFile();
                File unpackDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(), "distributions/unpacked");

                project.getLogger().lifecycle("================================================================");
                project.getLogger().lifecycle("🚀 [Distribution] 원스탑 서비스 배포(deployService) 시작");
                project.getLogger().lifecycle("   - 패키지 파일: {}", zipFile.getAbsolutePath());
                project.getLogger().lifecycle("   - 압축 해제 경로: {}", unpackDir.getAbsolutePath());
                project.getLogger().lifecycle("================================================================");

                // 1. 기존 폴더 정리 후 압축 해제
                project.delete(unpackDir);
                project.copy(spec -> {
                    spec.from(project.zipTree(zipFile));
                    spec.into(unpackDir);
                });

                // 2. deploy/install_service.sh 실행
                File installScript = new File(unpackDir, "deploy/install_service.sh");
                if (!installScript.exists()) {
                    throw new RuntimeException("deploy/install_service.sh 스크립트를 찾을 수 없습니다: " + installScript.getAbsolutePath());
                }
                installScript.setExecutable(true, false);

                try {
                    ProcessBuilder pb = new ProcessBuilder("./install_service.sh");
                    pb.directory(installScript.getParentFile());
                    pb.inheritIO();
                    Process process = pb.start();
                    int exitCode = process.waitFor();
                    if (exitCode != 0) {
                        throw new RuntimeException("install_service.sh 실행이 비정상 종료되었습니다 (코드: " + exitCode + ")");
                    }
                } catch (Exception e) {
                    throw new RuntimeException("서비스 설치 스크립트 실행 중 오류 발생: " + e.getMessage(), e);
                }
            });
        });

        // 5. 'distHelp' 태스크 등록 (배포 가이드 출력)
        project.getTasks().register("distHelp", task -> {
            task.setGroup("distribution");
            task.setDescription("배포 플러그인 사용 가이드 및 명령어 안내를 출력합니다.");
            task.doLast(t -> printGuide(project));
        });

        // 6. 'initDeployScript' 태스크 등록 (프로젝트 루트에 배포 자동화 쉘 스크립트 build_deploy.sh 생성)
        project.getTasks().register("initDeployScript", task -> {
            task.setGroup("distribution");
            task.setDescription("프로젝트 루트에 배포 자동화 쉘 스크립트(build_deploy.sh)를 생성합니다.");
            task.doLast(t -> {
                File targetFile = project.file("build_deploy.sh");
                InputStream stream = getClass().getClassLoader().getResourceAsStream("template/build_deploy.sh");
                if (stream == null) {
                    project.getLogger().error("❌ [Distribution] template/build_deploy.sh 템플릿을 찾을 수 없습니다.");
                    return;
                }
                try (stream) {
                    Files.copy(stream, targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                    targetFile.setExecutable(true, false);
                    project.getLogger().lifecycle("================================================================");
                    project.getLogger().lifecycle("✅ [Distribution] build_deploy.sh 가 프로젝트 루트에 생성되었습니다!");
                    project.getLogger().lifecycle("   - 파일 경로: {}", targetFile.getAbsolutePath());
                    project.getLogger().lifecycle("   - 사용법: ./build_deploy.sh -Penv=dev");
                    project.getLogger().lifecycle("================================================================");
                } catch (IOException e) {
                    throw new RuntimeException("build_deploy.sh 생성 실패: " + e.getMessage(), e);
                }
            });
        });
    }

    private void printGuide(Project project) {
        String msg = """
================================================================================
🚀 [Distribution Plugin] 빌드 및 배포 가이드
================================================================================
[기본 명령어]
  ./gradlew package -Penv=dev       : 개발 환경 배포 패키지(Zip) 생성
  ./gradlew package -Penv=prod      : 운영 환경 배포 패키지(Zip) 생성
  ./gradlew deployService -Penv=prod: 원스탑 배포 (빌드 + 압축해제 + 서비스 설치/구동)
  ./gradlew initDeployScript        : 프로젝트 루트에 build_deploy.sh 자동 생성
  ./build_deploy.sh -Penv=dev       : 쉘 스크립트 기반 원스탑 배포 (Git pull + deployService)

[환경 지정 옵션 (-Penv=...)]
  지정 시 config.profiles/{env}/ 내 설정 파일들이 패키지 config/ 로 오버레이됩니다.
================================================================================
""";
        project.getLogger().lifecycle(msg);
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
            project.getLogger().lifecycle("🚀 [Distribution] 배포 패키지 생성 시작");
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
            System.err.println("⚠️ [Distribution] template-manifest.txt 를 찾을 수 없습니다.");
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
