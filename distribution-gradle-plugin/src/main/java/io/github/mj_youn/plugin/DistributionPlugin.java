package io.github.mj_youn.plugin;

import org.apache.tools.ant.filters.ReplaceTokens;
import org.gradle.api.Plugin;
import org.gradle.api.Project;
import org.gradle.api.Task;
import org.gradle.api.artifacts.Configuration;
import org.gradle.api.artifacts.Dependency;
import org.gradle.api.file.DuplicatesStrategy;
import org.gradle.api.tasks.TaskProvider;
import org.gradle.api.tasks.bundling.Zip;

import java.io.BufferedReader;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 표준 배포 구조(deploy, bin, config, lib, docker, webapps, tomcat)를 일관되게 패키징하고,
 * Executable JAR 및 Standalone Apache Tomcat 11 배포를 모두 지원하는 Gradle 플러그인입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
 * @version 2.0.1
 */
public class DistributionPlugin implements Plugin<Project> {

    private static final String DEFAULT_ENV = "dev";
    private static final List<String> ENVIRONMENTS = List.of("dev", "prod", "local", "test", "stage");

    public DistributionPlugin() {}

    @Override
    public void apply(Project project) {
        // 1. 배포 확장 설정(Extension) 등록
        DistributionExtension extension = project.getExtensions().create("distribution", DistributionExtension.class,
                project);

        // 2. 플러그인 내장 템플릿 자원을 임시 디렉토리에 추출하는 태스크 등록
        File builtinExtractDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(),
                "tmp/dist-template-builtin");

        Task extractTemplateTask = project.getTasks().create("extractBuiltinTemplate", task -> {
            task.setGroup("distribution");
            task.setDescription("플러그인 내장 배포 스크립트 및 도커/톰캣 템플릿을 추출합니다.");
            task.doLast(t -> extractBuiltinResources(builtinExtractDir));
        });

        // 3. 'package' 태스크 등록 (기본 설정 또는 CLI -Ptype= / -PpackageType= 옵션 적용)
        var packageTaskProvider = project.getTasks().register("package", Zip.class, zip -> {
            zip.setGroup("distribution");
            zip.setDescription("표준 배포용 Zip 패키지를 생성합니다. (CLI -Ptype=tomcat 또는 DSL packageType 지원)");
            configurePackagingTask(project, zip, builtinExtractDir, extractTemplateTask, extension, null);
        });

        // 4. 'packageJar' 태스크 등록 (명시적 JAR 패키징)
        var packageJarTaskProvider = project.getTasks().register("packageJar", Zip.class, zip -> {
            zip.setGroup("distribution");
            zip.setDescription("Spring Boot Executable JAR 기반 배포 Zip 패키지를 생성합니다.");
            configurePackagingTask(project, zip, builtinExtractDir, extractTemplateTask, extension, "jar");
        });

        // 5. 'packageTomcat' 태스크 등록 (명시적 Standalone Tomcat 패키징)
        var packageTomcatTaskProvider = project.getTasks().register("packageTomcat", Zip.class, zip -> {
            zip.setGroup("distribution");
            zip.setDescription("Standalone Apache Tomcat 11 기반 Exploded WAR 및 톰캣 설정이 포함된 Zip 패키지를 생성합니다.");
            configurePackagingTask(project, zip, builtinExtractDir, extractTemplateTask, extension, "tomcat");
        });

        // 6. 원스탑 배포 태스크 등록 (deployService, deployJar, deployTomcat)
        registerDeployTask(project, "deployService", "기본 배포 패키지를 빌드 및 배포/구동합니다.", packageTaskProvider);
        registerDeployTask(project, "deployJar", "JAR 기반 배포 패키지를 빌드 및 배포/구동합니다.", packageJarTaskProvider);
        registerDeployTask(project, "deployTomcat", "Tomcat 기반 배포 패키지를 빌드 및 배포/구동합니다.", packageTomcatTaskProvider);

        // 7. 'distHelp' 태스크 등록 (배포 가이드 출력)
        project.getTasks().register("distHelp", task -> {
            task.setGroup("distribution");
            task.setDescription("배포 플러그인 사용 가이드 및 명령어 안내를 출력합니다.");
            task.doLast(t -> printGuide(project));
        });

        // 8. 'initDeployScript' 태스크 등록
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

    private void registerDeployTask(Project project, String taskName, String description, TaskProvider<Zip> zipTaskProvider) {
        project.getTasks().register(taskName, task -> {
            task.setGroup("distribution");
            task.setDescription(description);
            task.dependsOn(zipTaskProvider);
            task.doLast(t -> {
                Zip zipTask = zipTaskProvider.get();
                File zipFile = zipTask.getArchiveFile().get().getAsFile();
                File unpackDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(), "distributions/unpacked");

                project.getLogger().lifecycle("================================================================");
                project.getLogger().lifecycle("🚀 [Distribution] 원스탑 서비스 배포({}) 시작", taskName);
                project.getLogger().lifecycle("   - 패키지 파일: {}", zipFile.getAbsolutePath());
                project.getLogger().lifecycle("   - 압축 해제 경로: {}", unpackDir.getAbsolutePath());
                project.getLogger().lifecycle("================================================================");

                project.delete(unpackDir);
                project.copy(spec -> {
                    spec.from(project.zipTree(zipFile));
                    spec.into(unpackDir);
                });

                File installScript = new File(unpackDir, "deploy/install_service.sh");
                if (!installScript.exists()) {
                    throw new RuntimeException("deploy/install_service.sh 스크립트를 찾을 수 없습니다: " + installScript.getAbsolutePath());
                }
                installScript.setExecutable(true, false);

                try {
                    List<String> command = new ArrayList<>();
                    boolean isWindows = System.getProperty("os.name", "").toLowerCase().contains("win");
                    boolean isRoot = "root".equals(System.getProperty("user.name"));

                    if (!isWindows && !isRoot) {
                        command.add("sudo");
                    }
                    command.add("./install_service.sh");

                    ProcessBuilder pb = new ProcessBuilder(command);
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
    }

    private void printGuide(Project project) {
        String msg = """
================================================================================
🚀 [Distribution Plugin 2.0.1] 빌드 및 배포 가이드
================================================================================

[📦 JAR 모드 명령어 (Executable JAR 배포)]
  ./gradlew packageJar -Penv=dev     : JAR 기반 배포 패키지(Zip) 생성
  ./gradlew packageJar -Penv=prod    : JAR 기반 운영 패키지(Zip) 생성
  ./gradlew deployJar -Penv=prod     : JAR 기반 원스탑 배포 (빌드 + 설치)

[🐱 Tomcat 모드 명령어 (Standalone Apache Tomcat 배포)]
  ./gradlew packageTomcat -Penv=dev  : Tomcat 배포 패키지(Zip) 생성 (webapps/ROOT 포함)
  ./gradlew packageTomcat -Penv=prod : Tomcat 운영 패키지(Zip) 생성
  ./gradlew deployTomcat -Penv=prod  : Tomcat 원스탑 배포 (빌드 + 설치)

[⚡ 기본 명령어 (DSL packageType 설정 기반)]
  ./gradlew package -Penv=dev        : 기본 설정(packageType) 기반 패키징
  ./gradlew deployService -Penv=dev  : 기본 설정 기반 원스탑 배포

[🎛️ CLI 파라미터 옵션]
  -Penv=dev|prod|local|test|stage    : 배포 환경 프로파일 지정
                                       config.profiles/{env}/ 의 설정 파일이
                                       패키지 config/ 로 오버레이됩니다.
  -Ptype=jar|tomcat                  : 배포 유형 CLI 오버라이드
  -PpackageType=jar|tomcat           : 배포 유형 CLI 오버라이드 (packageType alias)
  -Pport=8443                        : HTTP 서비스 포트 지정 (기본값: DSL httpPort)
  -PtomcatVersion=11.0.15            : Apache Tomcat 버전 지정

[🛠️ DSL 설정 (build.gradle)]
  distribution {
      appName     = 'my-service'     // 서비스 이름 (기본값: rootProject.name)
      packageType = 'jar'            // 기본 배포 유형: 'jar' 또는 'tomcat'
      httpPort    = 8080             // 서비스 포트 (기본값: 8080)
      tomcatVersion = '11.0.15'     // Tomcat 버전 (Tomcat 모드 전용)
  }

[🔧 유틸리티]
  ./gradlew initDeployScript         : 프로젝트 루트에 build_deploy.sh 자동 생성
  ./gradlew distHelp                 : 이 도움말 출력
  ./build_deploy.sh                  : 쉘 스크립트 기반 원스탑 배포

================================================================================
""";
        project.getLogger().lifecycle(msg);
    }

    /**
     * Zip 패키징 태스크 설정
     */
    private void configurePackagingTask(Project project, Zip zipTask, File builtinExtractDir, Task extractTemplateTask,
            DistributionExtension extension, String explicitType) {

        zipTask.dependsOn(extractTemplateTask);

        // 패키지 타입 결정 (명시적 인자 -> CLI -Ptype= / -PpackageType= -> DSL extension)
        String packageType = resolvePackageType(project, extension, explicitType);
        boolean isTomcat = "tomcat".equalsIgnoreCase(packageType) || "war".equalsIgnoreCase(packageType);

        // Spring Boot 빌드 태스크 의존성 연결
        Task bootJarTask = project.getTasks().findByName("bootJar");
        Task bootWarTask = project.getTasks().findByName("bootWar");

        File explodedWebappsDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(), "exploded-webapps/ROOT");

        if (isTomcat) {
            // Tomcat 사전 조건 검증 태스크 등록/실행
            zipTask.doFirst(task -> verifyTomcatPrerequisites(project));

            if (bootWarTask != null) {
                // bootWar의 archiveFileName을 기본적으로 'ROOT.war'로 보장
                try {
                    bootWarTask.setProperty("archiveFileName", "ROOT.war");
                } catch (Exception ignored) {}
                zipTask.dependsOn(bootWarTask);
            }
        } else {
            if (bootJarTask != null) {
                zipTask.dependsOn(bootJarTask);
            }
        }

        zipTask.setDuplicatesStrategy(DuplicatesStrategy.EXCLUDE);
        // 프로퍼티(-P...)나 토큰 변경 시 항상 패키징이 실행되도록 설정
        zipTask.getOutputs().upToDateWhen(t -> false);

        String env = project.hasProperty("env") ? String.valueOf(project.property("env")) : DEFAULT_ENV;
        Map<String, Object> tokens = createReplaceTokens(project, extension, packageType);

        zipTask.doFirst(task -> {
            project.getLogger().lifecycle("================================================================");
            project.getLogger().lifecycle("🚀 [Distribution 2.0.1] 배포 패키지 생성 시작");
            project.getLogger().lifecycle("   - 대상 프로젝트: {}", project.getName());
            project.getLogger().lifecycle("   - 배포 유형: {} ({})", packageType.toUpperCase(), isTomcat ? "Standalone Tomcat" : "Executable JAR");
            project.getLogger().lifecycle("   - 활성 프로파일: {}", env);
            project.getLogger().lifecycle("   - HTTP 서비스 포트: {}", tokens.get("httpPort"));
            project.getLogger().lifecycle("   - 산출물 이름: {}", zipTask.getArchiveFileName().get());
            project.getLogger().lifecycle("================================================================");

            // Tomcat 모드인 경우 WAR 압축 해제 실행
            if (isTomcat) {
                File warFile = null;
                File libsDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(), "libs");
                if (libsDir.exists()) {
                    File[] wars = libsDir.listFiles((dir, name) -> name.endsWith(".war"));
                    if (wars != null && wars.length > 0) {
                        warFile = wars[0];
                    }
                }
                if (warFile != null && warFile.exists()) {
                    project.getLogger().lifecycle("📦 [Distribution] 외장 톰캣 배포를 위해 WAR 압축을 해제합니다: {}", warFile.getName());
                    project.delete(explodedWebappsDir);
                    final File finalWarFile = warFile;
                    project.copy(spec -> {
                        spec.from(project.zipTree(finalWarFile));
                        spec.into(explodedWebappsDir);
                    });
                }
            }
        });

        // 1. [우선순위 1] 로컬 프로젝트의 오버라이드(@Override) 파일 적재
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

        File localTomcatDir = project.file("tomcat");
        if (localTomcatDir.exists()) {
            zipTask.from(localTomcatDir, spec -> {
                spec.into("tomcat");
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        // 2. [우선순위 2] 플러그인 내장 기본 템플릿 파일 적재 (로컬에 없는 것만 들어감)
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

        // 톰캣 설정 템플릿 포함
        if (isTomcat) {
            zipTask.from(new File(builtinExtractDir, "tomcat"), spec -> {
                spec.into("tomcat");
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
            // Exploded WAR 포함 (webapps/ROOT)
            zipTask.from(explodedWebappsDir, spec -> {
                spec.into("webapps/ROOT");
            });
        }

        // 3. 환경별 설정 파일 (config.profiles/${env} -> config)
        File profileDir = project.file("config.profiles/" + env);
        if (profileDir.exists()) {
            zipTask.from(profileDir, spec -> {
                spec.into("config");
                spec.rename(name -> name.replace("-" + env, ""));
            });
        } else {
            File legacyEnvDir = project.file("config/" + env);
            if (legacyEnvDir.exists()) {
                zipTask.from(legacyEnvDir, spec -> {
                    spec.into("config");
                    spec.rename(name -> name.replace("-" + env, ""));
                });
            }
        }

        File commonConfigDir = project.file("config");
        if (commonConfigDir.exists()) {
            zipTask.from(commonConfigDir, spec -> {
                spec.into("config");
                spec.exclude(ENVIRONMENTS);
                spec.exclude("**/*" + env + "*");
            });
        }

        // 4. 애플리케이션 라이브러리 및 JAR (build/libs/*.jar -> libs)
        //    Tomcat 모드에서는 WAR가 webapps/ROOT에 Explode되므로 libs/ 불필요
        if (!isTomcat) {
            File libsDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(), "libs");
            if (bootJarTask != null) {
                zipTask.from(project.files(libsDir).builtBy(bootJarTask), spec -> {
                    spec.include("*.jar");
                    spec.exclude("*plain.jar");
                    spec.into("libs");
                });
            } else {
                zipTask.from(libsDir, spec -> {
                    spec.include("*.jar");
                    spec.exclude("*plain.jar");
                    spec.into("libs");
                });
            }
        }

        zipTask.doLast(task -> {
            File archive = zipTask.getArchiveFile().get().getAsFile();
            long sizeInMb = archive.length() / (1024 * 1024);
            project.getLogger().lifecycle("================================================================");
            project.getLogger().lifecycle("✅ [Distribution 2.0.1] 배포 패키지 생성 완료!");
            project.getLogger().lifecycle("   - 산출물 경로: {}", archive.getAbsolutePath());
            project.getLogger().lifecycle("   - 파일 크기  : {} MB ({} bytes)", sizeInMb, archive.length());
            project.getLogger().lifecycle("================================================================");
        });

        // 5. 추가 복제 디렉토리 (EXTRA_DIRS / extraDirs)
        Set<String> extraDirsToCopy = new LinkedHashSet<>(extension.getExtraDirs());
        List<File> envFiles = List.of(
            project.file("config.profiles/" + env + "/.env"),
            project.file("config/" + env + "/.env"),
            project.file(".env"),
            project.file("scripts/service/.env")
        );
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
                                if (!d.trim().isEmpty()) extraDirsToCopy.add(d.trim());
                            }
                        }
                    }
                } catch (Exception ignored) {}
            }
        }
        for (String dirName : extraDirsToCopy) {
            File extraDir = project.file(dirName);
            if (extraDir.exists() && extraDir.isDirectory()) {
                zipTask.from(extraDir, spec -> {
                    spec.into(dirName);
                });
            }
        }
    }

    private String resolvePackageType(Project project, DistributionExtension extension, String explicitType) {
        if (explicitType != null && !explicitType.isBlank()) {
            return explicitType.toLowerCase();
        }
        if (project.hasProperty("type")) {
            return String.valueOf(project.property("type")).toLowerCase();
        }
        if (project.hasProperty("packageType")) {
            return String.valueOf(project.property("packageType")).toLowerCase();
        }
        return extension.getPackageType() != null ? extension.getPackageType().toLowerCase() : "jar";
    }

    /**
     * 외장 톰캣 배포 시 사전 필수 조건 검증
     */
    private void verifyTomcatPrerequisites(Project project) {
        // 1. Gradle 'war' 플러그인 확인
        if (!project.getPluginManager().hasPlugin("war")) {
            String msg = """

================================================================================
❌ [Distribution Plugin - Tomcat 사전 조건 검증 실패]
--------------------------------------------------------------------------------
외장 톰캣 배포(packageType='tomcat')를 위해서는 Gradle 'war' 플러그인이 필수입니다.
build.gradle의 plugins 블록에 id 'war' 를 추가해 주세요.

[해결 방법 예시 - build.gradle]
--------------------------------------------------------------------------------
plugins {
    id 'java'
    id 'war' // <-- 추가 필요
    id 'org.springframework.boot' version '...'
    ...
}
================================================================================
""";
            project.getLogger().error(msg);
            throw new RuntimeException("Tomcat 사전 조건 검증 실패: 'war' 플러그인이 선언되지 않았습니다.");
        }

        // 2. SpringBootServletInitializer 상속 확인
        File srcDir = project.file("src/main/java");
        if (srcDir.exists()) {
            boolean foundSpringBootApp = false;
            boolean extendsServletInitializer = false;
            File springBootAppFile = null;

            try {
                List<File> javaFiles = new ArrayList<>();
                findJavaFiles(srcDir, javaFiles);

                for (File file : javaFiles) {
                    String content = Files.readString(file.toPath(), StandardCharsets.UTF_8);
                    if (content.contains("@SpringBootApplication")) {
                        foundSpringBootApp = true;
                        springBootAppFile = file;
                        if (content.contains("SpringBootServletInitializer") && content.contains("extends")) {
                            extendsServletInitializer = true;
                            break;
                        }
                    }
                }
            } catch (Exception e) {
                project.getLogger().warn("⚠️ [Distribution] Tomcat 사전 검증 중 소스 파일 읽기 실패: " + e.getMessage());
            }

            if (foundSpringBootApp && !extendsServletInitializer) {
                String appName = springBootAppFile != null ? springBootAppFile.getName().replace(".java", "") : "Application";
                String msg = String.format("""

================================================================================
❌ [Distribution Plugin - Tomcat 사전 조건 검증 실패]
--------------------------------------------------------------------------------
외장 톰캣 배포(packageType='tomcat')를 위해서는 메인 스프링 부트 애플리케이션 클래스가
'org.springframework.boot.web.servlet.support.SpringBootServletInitializer'를
반드시 상속(extends)해야 합니다.

[검증 실패 파일]
  %s

[해결 방법 예시 - %s.java]
--------------------------------------------------------------------------------
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;

@SpringBootApplication
public class %s extends SpringBootServletInitializer {

    @Override
    protected SpringApplicationBuilder configure(SpringApplicationBuilder builder) {
        return builder.sources(%s.class);
    }

    public static void main(String[] args) {
        SpringApplication.run(%s.class, args);
    }
}
================================================================================
""", springBootAppFile != null ? springBootAppFile.getAbsolutePath() : "src/main/java",
appName, appName, appName, appName);

                project.getLogger().error(msg);
                throw new RuntimeException("Tomcat 사전 조건 검증 실패: " + appName + " 클래스가 SpringBootServletInitializer를 상속하지 않았습니다.");
            }
        }

        // 3. providedRuntime 설정 권고 점검
        Configuration providedRuntimeConfig = project.getConfigurations().findByName("providedRuntime");
        boolean hasProvidedTomcat = false;
        if (providedRuntimeConfig != null) {
            for (Dependency dep : providedRuntimeConfig.getAllDependencies()) {
                if (dep.getName() != null && dep.getName().contains("tomcat")) {
                    hasProvidedTomcat = true;
                    break;
                }
            }
        }
        if (!hasProvidedTomcat) {
            project.getLogger().warn("""
--------------------------------------------------------------------------------
⚠️ [Distribution Plugin - Tomcat 의존성 설정 권고]
외장 톰캣 배포 시 내장 톰캣과의 클래스로더 충돌을 방지하기 위해 
build.gradle에 providedRuntime 'org.springframework.boot:spring-boot-starter-tomcat' 
또는 providedRuntime 'org.apache.tomcat.embed:tomcat-embed-core' 설정을 권장합니다.
--------------------------------------------------------------------------------
""");
        }

        // 4. docker/Dockerfile 설정 점검
        File dockerfile = project.file("docker/Dockerfile");
        if (dockerfile.exists() && dockerfile.isFile()) {
            try {
                String dfContent = Files.readString(dockerfile.toPath(), StandardCharsets.UTF_8);
                if (!dfContent.contains("catalina.sh") && !dfContent.toLowerCase().contains("tomcat")) {
                    project.getLogger().warn("""
--------------------------------------------------------------------------------
⚠️ [Distribution Plugin - Dockerfile 점검 권고]
현재 Tomcat 배포 모드이지만 docker/Dockerfile에서 'catalina.sh run' 또는 Tomcat 베이스 설정이 감지되지 않았습니다.
외장 톰캣 컨테이너 구동을 위해 docker/Dockerfile의 베이스 이미지와 ENTRYPOINT 설정을 확인해 주세요.
--------------------------------------------------------------------------------
""");
                }
            } catch (Exception ignored) {}
        }
    }

    private void findJavaFiles(File dir, List<File> result) {
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isDirectory()) {
                findJavaFiles(f, result);
            } else if (f.getName().endsWith(".java")) {
                result.add(f);
            }
        }
    }

    private int resolveHttpPort(Project project, DistributionExtension extension) {
        if (project.hasProperty("httpPort")) {
            try {
                return Integer.parseInt(String.valueOf(project.property("httpPort")));
            } catch (NumberFormatException ignored) {}
        }
        if (project.hasProperty("port")) {
            try {
                return Integer.parseInt(String.valueOf(project.property("port")));
            } catch (NumberFormatException ignored) {}
        }
        return extension.getHttpPort();
    }

    /**
     * 스크립트 및 도커 파일 치환용 토큰 맵 생성
     */
    private Map<String, Object> createReplaceTokens(Project project, DistributionExtension extension, String packageType) {
        Map<String, Object> tokens = new HashMap<>();
        String appName = extension.getAppName() != null && !extension.getAppName().isBlank() ? extension.getAppName()
                : project.getName();
        String version = project.getVersion() != null ? project.getVersion().toString() : "unspecified";

        tokens.put("appName", appName);
        tokens.put("version", version);
        tokens.put("deployMode", "");
        tokens.put("dockerImage", appName + ":" + version);
        tokens.put("appType", packageType);
        tokens.put("tomcatVersion", extension.getTomcatVersion() != null ? extension.getTomcatVersion() : "11.0.15");
        tokens.put("httpPort", String.valueOf(resolveHttpPort(project, extension)));

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
