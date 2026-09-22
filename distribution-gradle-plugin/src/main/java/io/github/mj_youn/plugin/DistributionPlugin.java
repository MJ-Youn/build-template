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
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import org.apache.tools.zip.ZipEntry;
import org.apache.tools.zip.ZipOutputStream;
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
 * 표준 배포 구조(deploy, bin, config, lib, docker, webapps, tomcat)를 일관되게 패키징하고, Executable JAR 및
 * Standalone Apache Tomcat 11 배포를 모두 지원하는 Gradle 플러그인입니다.
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

        // 7. 'packageDocker' 태스크 등록 (Strategy 1 - 오프라인/폐쇄망용 Docker 이미지 tar 추출 + Zip 패키징)
        project.getTasks().register("packageDocker", task -> {
            task.setGroup("distribution");
            task.setDescription("Docker 이미지를 빌드하고 배포용 스크립트와 함께 Zip으로 패키징합니다. (Strategy 1 - 오프라인/폐쇄망용)");
            task.dependsOn(packageTaskProvider);
            task.doLast(t -> executePackageDocker(project, extension, packageTaskProvider));
        });

        // 8. 'packageDockerRemote' 태스크 등록 (Strategy 2 - 레지스트리 Push 및 배포 패키지/가이드 생성)
        var packageDockerRemoteProvider = project.getTasks().register("packageDockerRemote", task -> {
            task.setGroup("distribution");
            task.setDescription("Docker 이미지를 빌드하고 원격 레지스트리에 Push합니다. (Strategy 2 - CI/CD 파이프라인용)");
            task.dependsOn(packageTaskProvider);
            task.doLast(t -> executePackageDockerRemote(project, extension, packageTaskProvider));
        });

        // 기존 가이드 및 호환성을 위한 'dockerBuildRemote' 별칭 태스크 등록
        project.getTasks().register("dockerBuildRemote", task -> {
            task.setGroup("distribution");
            task.setDescription("Docker 이미지를 빌드하고 원격 레지스트리에 Push합니다. ('packageDockerRemote' 별칭)");
            task.dependsOn(packageDockerRemoteProvider);
        });

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

                // Windows용 build_deploy.bat 생성
                File batTargetFile = project.file("build_deploy.bat");
                InputStream batStream = getClass().getClassLoader().getResourceAsStream("template/build_deploy.bat");
                if (batStream != null) {
                    try (batStream) {
                        Files.copy(batStream, batTargetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                        project.getLogger()
                                .lifecycle("✅ [Distribution] build_deploy.bat (Windows용)이 프로젝트 루트에 생성되었습니다!");
                        project.getLogger().lifecycle("   - 파일 경로: {}", batTargetFile.getAbsolutePath());
                        project.getLogger().lifecycle("   - 사용법: build_deploy.bat dev");
                        project.getLogger()
                                .lifecycle("================================================================");
                    } catch (IOException e) {
                        project.getLogger().warn("⚠️ [Distribution] build_deploy.bat 생성 실패: {}", e.getMessage());
                    }
                }
            });
        });

        // 9. 'initDocker' 태스크 등록 (배포 유형에 맞는 Dockerfile & docker-compose.yml 생성)
        project.getTasks().register("initDocker", task -> {
            task.setGroup("distribution");
            task.setDescription(
                    "프로젝트의 docker/ 디렉토리에 배포 유형(JAR 또는 Tomcat)에 맞는 샘플 Dockerfile 및 docker-compose.yml을 생성합니다.");
            task.doLast(t -> {
                String packageType = resolvePackageType(project, extension, null);
                Map<String, Object> tokens = createReplaceTokens(project, extension, packageType);
                initDockerFiles(project, packageType, tokens);
            });
        });

        // 10. 'showDocker' 태스크 등록 (JAR vs Tomcat Dockerfile 차이점 콘솔 출력)
        project.getTasks().register("showDocker", task -> {
            task.setGroup("distribution");
            task.setDescription("JAR 배포와 Tomcat 배포의 Docker 컨테이너 구조 및 Dockerfile 차이점을 콘솔에서 확인합니다.");
            task.doLast(t -> printDockerComparisonGuide(project));
        });
    }

    private void registerDeployTask(Project project, String taskName, String description,
            TaskProvider<Zip> zipTaskProvider) {
        project.getTasks().register(taskName, task -> {
            task.setGroup("distribution");
            task.setDescription(description);
            task.dependsOn(zipTaskProvider);
            task.doLast(t -> {
                Zip zipTask = zipTaskProvider.get();
                File zipFile = zipTask.getArchiveFile().get().getAsFile();
                File unpackDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(),
                        "distributions/unpacked");

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
                    throw new RuntimeException(
                            "deploy/install_service.sh 스크립트를 찾을 수 없습니다: " + installScript.getAbsolutePath());
                }
                installScript.setExecutable(true, false);

                try {
                    List<String> command = new ArrayList<>();
                    boolean isWindows = System.getProperty("os.name", "").toLowerCase().contains("win");
                    boolean isRoot = "root".equals(System.getProperty("user.name"));
                    // 기본 배포는 일반 사용자(User) 모드
                    // -Psudo, -Proot, -Psystem 또는 환경변수 SUDO=true, ROOT_MODE=true 등이 지정되었을 때만 시스템(root/sudo) 모드로 전환
                    boolean isSudoMode = project.hasProperty("sudo") || project.hasProperty("root")
                            || project.hasProperty("system")
                            || "true".equalsIgnoreCase(System.getenv("SUDO"))
                            || "true".equalsIgnoreCase(System.getenv("SUDO_MODE"))
                            || "true".equalsIgnoreCase(System.getenv("ROOT_MODE"));

                    if (!isWindows && !isRoot && isSudoMode) {
                        command.add("sudo");
                    }
                    command.add("./install_service.sh");
                    if (isSudoMode) {
                        command.add("--sudo");
                    }

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
                🚀 [Distribution Plugin 3.1.0] 빌드 및 배포 가이드
                ================================================================================

                [📦 JAR 모드 명령어 (Executable JAR 배포)]
                  ./gradlew packageJar -Penv=dev     : JAR 기반 배포 패키지(Zip) 생성
                  ./gradlew packageJar -Penv=prod    : JAR 기반 운영 패키지(Zip) 생성
                  ./gradlew deployJar -Penv=prod     : JAR 기반 원스탑 배포 (기본: 일반 사용자 모드, sudo 불필요)
                  ./gradlew deployJar -Penv=prod -Psudo : JAR 기반 시스템 모드 원스탑 배포 (sudo 필요, /opt 배포)

                [🐱 Tomcat 모드 명령어 (Standalone Apache Tomcat 배포)]
                  ./gradlew packageTomcat -Penv=dev  : Tomcat 배포 패키지(Zip) 생성 (webapps/ROOT 포함)
                  ./gradlew packageTomcat -Penv=prod : Tomcat 운영 패키지(Zip) 생성
                  ./gradlew deployTomcat -Penv=prod  : Tomcat 원스탑 배포 (기본: 일반 사용자 모드, sudo 불필요)
                  ./gradlew deployTomcat -Penv=prod -Psudo : Tomcat 시스템 모드 원스탑 배포 (sudo 필요)

                [⚡ 기본 명령어 (DSL packageType 설정 기반)]
                  ./gradlew package -Penv=dev        : 기본 설정(packageType) 기반 패키징
                  ./gradlew deployService -Penv=dev  : 기본 설정 기반 원스탑 배포 (기본: 일반 사용자 모드)
                  ./gradlew deployService -Penv=dev -Psudo : 시스템 모드 기반 원스탑 배포 (sudo 필요)

                [🐳 Docker 배포 명령어 (Strategy 1 & 2)]
                  ./gradlew packageDocker -Penv=prod            : Docker 이미지 빌드 후 .tar 추출 + Zip 패키징 (Strategy 1: 오프라인/폐쇄망용)
                  ./gradlew packageDockerRemote -Penv=prod -PdockerRegistry=my.reg.com/repo : Docker 이미지 빌드 & 원격 레지스트리 Push (Strategy 2: CI/CD용)
                  (별칭: ./gradlew dockerBuildRemote -Penv=prod -PdockerRegistry=...)

                [🎛️ CLI 파라미터 옵션]
                  -Psudo, -Proot                     : 시스템 모드로 배포 (sudo 필요, /opt 및 /etc/systemd 배포)
                  -Puser                             : 일반 사용자 모드로 배포 (기본값이므로 생략 가능)
                  -Penv=dev|prod|local|test|stage    : 배포 환경 프로파일 지정
                                                       config.profiles/{env}/ 의 설정 파일이
                                                       패키지 config/ 로 오버레이됩니다.
                  -Pos=linux|windows|all             : 배포 대상 운영체제 지정 (기본값: linux)
                                                       linux  : *.sh 스크립트만 포함 (*.bat 제외)
                                                       windows: *.bat 스크립트만 포함 (*.sh 제외)
                                                       all    : *.sh 및 *.bat 스크립트 모두 포함
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
                  ./gradlew initDocker               : 배포 유형(기본 설정)에 맞는 Dockerfile & docker-compose 생성
                  ./gradlew initDocker -Ptype=jar    : JAR 배포용 Dockerfile 생성 (libs/ + bin/start.sh)
                  ./gradlew initDocker -Ptype=tomcat : Tomcat 배포용 Dockerfile 생성 (Apache Tomcat + webapps/ROOT)
                  ./gradlew showDocker               : JAR vs Tomcat Dockerfile 구조 및 차이점 콘솔 출력
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

        File explodedWebappsDir = new File(project.getLayout().getBuildDirectory().getAsFile().get(),
                "exploded-webapps/ROOT");

        if (isTomcat) {
            // Tomcat 사전 조건 검증 태스크 등록/실행
            zipTask.doFirst(task -> verifyTomcatPrerequisites(project));

            if (bootWarTask != null) {
                // bootWar의 archiveFileName을 기본적으로 'ROOT.war'로 보장
                try {
                    bootWarTask.setProperty("archiveFileName", "ROOT.war");
                } catch (Exception ignored) {
                }
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
        String targetOs = resolveTargetOs(project, extension);
        Map<String, Object> tokens = createReplaceTokens(project, extension, packageType);

        zipTask.doFirst(task -> {
            project.getLogger().lifecycle("================================================================");
            project.getLogger().lifecycle("🚀 [Distribution 3.1.0] 배포 패키지 생성 시작");
            project.getLogger().lifecycle("   - 대상 프로젝트    : {}", project.getName());
            project.getLogger().lifecycle("   - 배포 유형       : {} ({})", packageType.toUpperCase(),
                    isTomcat ? "Standalone Tomcat" : "Executable JAR");
            project.getLogger().lifecycle("   - 활성 프로파일    : {}", env);
            project.getLogger().lifecycle("   - 타겟 OS        : {} (옵션: -Pos=linux|windows|all, 기본값: linux)", targetOs.toUpperCase());
            project.getLogger().lifecycle("   - HTTP 서비스 포트 : {}", tokens.get("httpPort"));
            project.getLogger().lifecycle("   - 산출물 이름      : {}", zipTask.getArchiveFileName().get());
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
                    project.getLogger().lifecycle("📦 [Distribution] 외장 톰캣 배포를 위해 WAR 압축을 해제합니다: {}",
                            warFile.getName());
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
                applyOsScriptFilter(spec, targetOs);
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        File localServiceDir = project.file("scripts/service");
        if (localServiceDir.exists()) {
            zipTask.from(localServiceDir, spec -> {
                spec.into("bin");
                spec.filePermissions(p -> p.unix(0755));
                applyOsScriptFilter(spec, targetOs);
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        File localCommonDir = project.file("scripts/common");
        if (localCommonDir.exists()) {
            zipTask.from(localCommonDir, spec -> {
                spec.into("bin");
                spec.filePermissions(p -> p.unix(0755));
                applyOsScriptFilter(spec, targetOs);
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
            zipTask.from(localCommonDir, spec -> {
                spec.into("deploy");
                spec.filePermissions(p -> p.unix(0755));
                applyOsScriptFilter(spec, targetOs);
                spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
            });
        }

        File localDockerDir = project.file("docker");
        if (localDockerDir.exists()) {
            zipTask.from(localDockerDir, spec -> {
                spec.into("docker");
                spec.exclude("*-jar*", "*-tomcat*");
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
            applyOsScriptFilter(spec, targetOs);
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });

        zipTask.from(new File(builtinExtractDir, "scripts/service"), spec -> {
            spec.into("bin");
            spec.filePermissions(p -> p.unix(0755));
            applyOsScriptFilter(spec, targetOs);
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });

        zipTask.from(new File(builtinExtractDir, "scripts/common"), spec -> {
            spec.into("bin");
            spec.filePermissions(p -> p.unix(0755));
            applyOsScriptFilter(spec, targetOs);
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });
        zipTask.from(new File(builtinExtractDir, "scripts/common"), spec -> {
            spec.into("deploy");
            spec.filePermissions(p -> p.unix(0755));
            applyOsScriptFilter(spec, targetOs);
            spec.filter(Map.of("tokens", tokens), ReplaceTokens.class);
        });

        zipTask.from(new File(builtinExtractDir, "docker"), spec -> {
            spec.into("docker");
            spec.exclude("*-jar*", "*-tomcat*");
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
            project.getLogger().lifecycle("✅ [Distribution 3.1.0] 배포 패키지 생성 완료!");
            project.getLogger().lifecycle("   - 산출물 경로: {}", archive.getAbsolutePath());
            project.getLogger().lifecycle("   - 파일 크기  : {} MB ({} bytes)", sizeInMb, archive.length());
            project.getLogger().lifecycle("================================================================");
        });

        // 5. 추가 복제 디렉토리 (EXTRA_DIRS / extraDirs)
        Set<String> extraDirsToCopy = new LinkedHashSet<>(extension.getExtraDirs());
        List<File> envFiles = List.of(project.file("config.profiles/" + env + "/.env"),
                project.file("config/" + env + "/.env"), project.file(".env"), project.file("scripts/service/.env"));
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
                                    extraDirsToCopy.add(d.trim());
                            }
                        }
                    }
                } catch (Exception ignored) {
                }
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

    /**
     * 배포 대상 운영체제를 결정합니다. (CLI -Pos= / -PtargetOs= -> DSL extension.os -> 기본값 "linux")
     */
    private String resolveTargetOs(Project project, DistributionExtension extension) {
        if (project.hasProperty("os")) {
            return String.valueOf(project.property("os")).trim().toLowerCase();
        }
        if (project.hasProperty("targetOs")) {
            return String.valueOf(project.property("targetOs")).trim().toLowerCase();
        }
        String extOs = extension.getOs();
        if (extOs != null && !extOs.trim().isEmpty()) {
            return extOs.trim().toLowerCase();
        }
        return "linux";
    }

    /**
     * 타겟 OS에 따라 불필요한 스크립트 확장자를 제외합니다.
     */
    private void applyOsScriptFilter(org.gradle.api.file.CopySpec spec, String targetOs) {
        if ("linux".equals(targetOs)) {
            spec.exclude("**/*.bat");
        } else if ("windows".equals(targetOs) || "win".equals(targetOs)) {
            spec.exclude("**/*.sh");
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
                String appName = springBootAppFile != null ? springBootAppFile.getName().replace(".java", "")
                        : "Application";
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
                        """, springBootAppFile != null ? springBootAppFile.getAbsolutePath() : "src/main/java", appName,
                        appName, appName, appName);

                project.getLogger().error(msg);
                throw new RuntimeException(
                        "Tomcat 사전 조건 검증 실패: " + appName + " 클래스가 SpringBootServletInitializer를 상속하지 않았습니다.");
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
            } catch (Exception ignored) {
            }
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

    private int resolveHttpPort(Project project, DistributionExtension extension) {
        if (project.hasProperty("httpPort")) {
            try {
                return Integer.parseInt(String.valueOf(project.property("httpPort")));
            } catch (NumberFormatException ignored) {
            }
        }
        if (project.hasProperty("port")) {
            try {
                return Integer.parseInt(String.valueOf(project.property("port")));
            } catch (NumberFormatException ignored) {
            }
        }
        return extension.getHttpPort();
    }

    /**
     * 스크립트 및 도커 파일 치환용 토큰 맵 생성
     */
    private Map<String, Object> createReplaceTokens(Project project, DistributionExtension extension,
            String packageType) {
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

    /**
     * Docker 관련 템플릿(Dockerfile, docker-compose.yml)을 프로젝트의 docker/ 디렉토리에 생성합니다.
     *
     * @param project
     *            Gradle 프로젝트 인스턴스
     * @param packageType
     *            배포 유형 ("jar" 또는 "tomcat")
     * @param tokens
     *            토큰 치환 맵
     */
    private void initDockerFiles(Project project, String packageType, Map<String, Object> tokens) {
        boolean isTomcat = "tomcat".equalsIgnoreCase(packageType) || "war".equalsIgnoreCase(packageType);
        File dockerDir = project.file("docker");
        if (!dockerDir.exists()) {
            dockerDir.mkdirs();
        }

        try {
            // 1. 배포 타입에 맞는 주 Dockerfile 및 docker-compose.yml 생성
            String activeDockerTemplate = isTomcat ? "template/docker/Dockerfile-tomcat"
                    : "template/docker/Dockerfile-jar";
            String activeComposeTemplate = isTomcat ? "template/docker/docker-compose-tomcat.yml"
                    : "template/docker/docker-compose-jar.yml";

            File activeDockerFile = new File(dockerDir, "Dockerfile");
            File activeComposeFile = new File(dockerDir, "docker-compose.yml");

            copyTemplateResource(activeDockerTemplate, activeDockerFile, tokens);
            copyTemplateResource(activeComposeTemplate, activeComposeFile, tokens);

            project.getLogger().lifecycle("================================================================");
            project.getLogger().lifecycle("🐳 [Distribution] Docker 설정 생성 완료 (배포 유형: {})", packageType.toUpperCase());
            project.getLogger().lifecycle("   - 생성된 Dockerfile     : {}", activeDockerFile.getAbsolutePath());
            project.getLogger().lifecycle("   - 생성된 docker-compose : {}", activeComposeFile.getAbsolutePath());
            project.getLogger().lifecycle("================================================================");

            // 생성 직후 터미널에 두 형식의 차이점 요약 가이드 즉시 출력
            printDockerComparisonGuide(project);

        } catch (IOException e) {
            throw new RuntimeException("Docker 템플릿 생성 실패: " + e.getMessage(), e);
        }
    }

    /**
     * 클래스패스 템플릿 리소스를 읽어 토큰을 치환한 후 대상 파일에 저장합니다.
     *
     * @param resourcePath
     *            클래스패스 리소스 경로
     * @param targetFile
     *            저장할 대상 파일
     * @param tokens
     *            치환할 키-값 맵
     * @throws IOException
     *             입출력 예외 발생 시
     */
    private void copyTemplateResource(String resourcePath, File targetFile, Map<String, Object> tokens)
            throws IOException {
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

    /**
     * JAR 배포 vs Tomcat 배포의 Dockerfile 아키텍처 비교 가이드를 콘솔에 출력합니다.
     *
     * @param project
     *            Gradle 프로젝트 인스턴스
     */
    private void printDockerComparisonGuide(Project project) {
        String guide = """
                ================================================================================
                🐳 [Distribution 3.1.0] JAR vs Tomcat Dockerfile 아키텍처 비교 가이드
                ================================================================================

                ┌─────────────────┬──────────────────────────────────┬──────────────────────────────────┐
                │ 비교 항목       │ 📦 JAR 모드 (Executable JAR)     │ 🐱 Tomcat 모드 (Standalone Tomcat)│
                ├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
                │ 베이스 이미지   │ eclipse-temurin:25-jdk-alpine    │ eclipse-temurin:25-jdk-alpine +  │
                │                 │                                  │ Apache Tomcat 바이너리 자동 설치 │
                ├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
                │ 빌드 산출물     │ build/libs/*.jar                 │ build/exploded-webapps/ROOT/     │
                │                 │ (Spring Boot 실행 가능 단일 JAR) │ (또는 ROOT.war)                  │
                ├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
                │ 컨테이너 복사   │ COPY libs/ /app/libs/            │ COPY webapps/ROOT/ .../webapps/ROOT/
                │                 │ COPY config/ /app/config/        │ COPY tomcat/conf/ .../conf/      │
                │                 │ COPY bin/ /app/bin/              │ COPY tomcat/bin/setenv.sh .../   │
                │                 │                                  │ COPY config/ .../config/         │
                ├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
                │ 실행 엔트리포인트│ ENTRYPOINT ["/app/bin/start.sh"] │ ENTRYPOINT ["catalina.sh", "run"]│
                ├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
                │ 주요 볼륨 마운트│ -v ./config:/app/config          │ -v ./webapps/ROOT:.../ROOT       │
                │                 │ -v ./log:/log                    │ -v ./tomcat/conf:.../conf        │
                │                 │                                  │ -v ./config:.../config           │
                │                 │                                  │ -v ./log/tomcat:.../logs         │
                ├─────────────────┼──────────────────────────────────┼──────────────────────────────────┤
                │ 주요 용도 및 장점│ 경량 마이크로서비스, 빠른 기동,   │ 엔터프라이즈 레거시 호환, JNDI/Datasource,
                │                 │ 단일 패키지 배포 표준            │ 외부 설정 동적 튜닝, Exploded 무중단 갱신
                └─────────────────┴──────────────────────────────────┴──────────────────────────────────┘

                [💡 사용 명령어]
                  1. 현재 설정 기반 생성 : ./gradlew initDocker
                  2. JAR 배포용 강제 생성 : ./gradlew initDocker -Ptype=jar
                  3. Tomcat용 강제 생성  : ./gradlew initDocker -Ptype=tomcat
                  4. 본 비교 가이드 재출력: ./gradlew showDocker
                ================================================================================
                """;
        project.getLogger().lifecycle(guide);
    }

    /**
     * Docker 이미지 빌드 및 오프라인 배포용 Zip 패키지를 생성합니다. (Strategy 1)
     */
    private void executePackageDocker(Project project, DistributionExtension extension,
            TaskProvider<Zip> zipTaskProvider) {
        DockerBuildContext ctx = buildDockerImageInternal(project, extension, zipTaskProvider, false);
        File buildDir = project.getLayout().getBuildDirectory().getAsFile().get();
        File dockerDistDir = new File(buildDir, "tmp/docker-dist");
        project.delete(dockerDistDir);
        dockerDistDir.mkdirs();

        String env = project.hasProperty("env") ? String.valueOf(project.property("env")) : DEFAULT_ENV;
        File tarFile = new File(dockerDistDir, ctx.appName + ".tar");

        // 1. docker save 실행
        project.getLogger().lifecycle("💾 [Distribution] Docker 이미지 tar 저장 중 (docker save) -> {}", tarFile.getAbsolutePath());
        List<String> saveCmd = List.of("docker", "save", "-o", tarFile.getAbsolutePath(), ctx.fullImageName);
        runProcess(project, saveCmd, dockerDistDir, "Docker 이미지 저장");

        // 2. docker context 내 스크립트 및 설정 복제 (Dockerfile, dev/prod 제외하고 docker-compose.yml만 복사)
        copyDockerComposeOnly(ctx.dockerContextDir, dockerDistDir);
        copyDirIfExists(new File(ctx.dockerContextDir, "config"), new File(dockerDistDir, "config"));
        copyDirIfExists(new File(ctx.dockerContextDir, "bin"), new File(dockerDistDir, "bin"));
        copyDirIfExists(new File(ctx.dockerContextDir, "deploy"), new File(dockerDistDir, "deploy"));

        // 3. Zip 압축
        File distributionsDir = new File(buildDir, "distributions");
        distributionsDir.mkdirs();
        File outputZip = new File(distributionsDir, ctx.appName + "-docker-" + env + ".zip");
        if (outputZip.exists()) {
            outputZip.delete();
        }

        project.getLogger().lifecycle("🗜️ [Distribution] 오프라인 배포용 Zip 패키지 생성 중: {}", outputZip.getAbsolutePath());
        createTarAndZipArchive(dockerDistDir, outputZip);

        project.delete(ctx.dockerContextDir);
        project.delete(dockerDistDir);

        long sizeMb = outputZip.length() / (1024 * 1024);
        project.getLogger().lifecycle("================================================================");
        project.getLogger().lifecycle("✅ [Distribution 3.1.0] packageDocker 생성 완료 (Strategy 1 - 오프라인 패키지)");
        project.getLogger().lifecycle("   - 산출물 경로: {}", outputZip.getAbsolutePath());
        project.getLogger().lifecycle("   - 파일 크기  : {} MB ({} bytes)", sizeMb, outputZip.length());
        project.getLogger().lifecycle("   - 배포 방법  : 서버에 zip 전송 -> unzip -> sudo ./deploy/install_service.sh");
        project.getLogger().lifecycle("================================================================");
    }

    /**
     * Docker 이미지를 빌드하고 원격 레지스트리에 Push합니다. (Strategy 2)
     */
    private void executePackageDockerRemote(Project project, DistributionExtension extension,
            TaskProvider<Zip> zipTaskProvider) {
        DockerBuildContext ctx = buildDockerImageInternal(project, extension, zipTaskProvider, true);

        // 1. docker push 실행
        project.getLogger().lifecycle("☁️ [Distribution] Docker 이미지 Push 시작 -> {}", ctx.fullImageName);
        List<String> pushCmd = List.of("docker", "push", ctx.fullImageName);
        runProcess(project, pushCmd, null, "Docker 이미지 Push");
        project.getLogger().lifecycle("✅ [Distribution] Docker 이미지 Push 완료!");

        // 2. 서버 배포용 dist 준비 (build/distributions/docker-dist)
        File buildDir = project.getLayout().getBuildDirectory().getAsFile().get();
        File dockerDistDir = new File(buildDir, "distributions/docker-dist");
        project.delete(dockerDistDir);
        dockerDistDir.mkdirs();

        // Dockerfile, dev/prod 제외하고 docker-compose.yml만 복사
        copyDockerComposeOnly(ctx.dockerContextDir, dockerDistDir);
        copyDirIfExists(new File(ctx.dockerContextDir, "config"), new File(dockerDistDir, "config"));
        copyDirIfExists(new File(ctx.dockerContextDir, "bin"), new File(dockerDistDir, "bin"));
        copyDirIfExists(new File(ctx.dockerContextDir, "deploy"), new File(dockerDistDir, "deploy"));

        // 원격 레지스트리 전체 이미지명으로 스크립트 및 compose 파일 내용 업데이트
        updateDockerImageInDir(dockerDistDir, ctx.appName + ":" + ctx.tag, ctx.fullImageName);

        // DEPLOY-GUIDE.md 작성
        File guideFile = new File(dockerDistDir, "DEPLOY-GUIDE.md");
        String guideContent = String.format("""
                # %s 배포 가이드 (Strategy 2 - Remote Registry)

                - Docker 이미지: %s
                - 배포 파일 경로: %s

                ## 배포 절차
                1. docker-dist 디렉토리를 서버로 복사:
                   scp -r %s/ user@your-server:/home/user/docker-dist
                2. 서버 접속 후 Private Registry 로그인 (필요 시):
                   docker login %s
                3. 자동 설치 및 실행 (Systemd 서비스 등록 포함 — 권장):
                   cd /home/user/docker-dist
                   sudo ./deploy/install_service.sh
                   * install_service.sh 실행 시 원격 레지스트리에서 이미지를 자동으로 pull 받습니다.
                4. 또는 수동 실행 (docker compose 직접 기동):
                   cd /home/user/docker-dist
                   docker compose -f docker/docker-compose.yml up -d
                """, ctx.appName, ctx.fullImageName, dockerDistDir.getAbsolutePath(),
                dockerDistDir.getAbsolutePath(), ctx.registry);

        try {
            Files.writeString(guideFile.toPath(), guideContent, StandardCharsets.UTF_8);
        } catch (IOException ignored) {}

        project.delete(ctx.dockerContextDir);

        // 콘솔 배포 가이드 박스 출력
        printRemoteDeployBanner(project, ctx, dockerDistDir);
    }

    /**
     * Docker 이미지 빌드 공통 내부 로직을 수행합니다.
     */
    private DockerBuildContext buildDockerImageInternal(Project project, DistributionExtension extension,
            TaskProvider<Zip> zipTaskProvider, boolean requireRegistry) {
        Zip zipTask = zipTaskProvider.get();
        File zipFile = zipTask.getArchiveFile().get().getAsFile();
        if (!zipFile.exists()) {
            throw new RuntimeException("배포 패키지 파일이 존재하지 않습니다: " + zipFile.getAbsolutePath());
        }

        File buildDir = project.getLayout().getBuildDirectory().getAsFile().get();
        File dockerContextDir = new File(buildDir, "tmp/docker-build");
        project.delete(dockerContextDir);
        dockerContextDir.mkdirs();

        // 1. 배포 Zip 아카이브 압축 해제
        project.getLogger().lifecycle("================================================================");
        project.getLogger().lifecycle("🐳 [Distribution] Docker 빌드 컨텍스트 준비 중: {}", dockerContextDir.getAbsolutePath());
        project.copy(spec -> {
            spec.from(project.zipTree(zipFile));
            spec.into(dockerContextDir);
        });

        // 2. 패키지 타입 및 토큰 치환 준비
        String packageType = resolvePackageType(project, extension, null);
        boolean isTomcat = "tomcat".equalsIgnoreCase(packageType) || "war".equalsIgnoreCase(packageType);
        Map<String, Object> tokens = createReplaceTokens(project, extension, packageType);

        // 3. Dockerfile 준비
        File dockerFile = new File(dockerContextDir, "docker/Dockerfile");
        if (!dockerFile.exists()) {
            File localDockerfile = project.file("docker/Dockerfile");
            if (localDockerfile.exists()) {
                try {
                    Files.copy(localDockerfile.toPath(), dockerFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
                } catch (Exception e) {
                    project.getLogger().warn("⚠️ [Distribution] 로컬 Dockerfile 복사 실패: " + e.getMessage());
                }
            }
        }
        if (!dockerFile.exists()) {
            String templateName = isTomcat ? "template/docker/Dockerfile-tomcat" : "template/docker/Dockerfile-jar";
            try {
                copyTemplateResource(templateName, dockerFile, tokens);
            } catch (IOException e) {
                throw new RuntimeException("기본 Dockerfile 템플릿 생성 실패: " + e.getMessage(), e);
            }
        }

        // 4. docker-compose.yml 준비
        File composeFile = new File(dockerContextDir, "docker/docker-compose.yml");
        if (!composeFile.exists()) {
            String composeTemplate = isTomcat ? "template/docker/docker-compose-tomcat.yml"
                    : "template/docker/docker-compose-jar.yml";
            try {
                copyTemplateResource(composeTemplate, composeFile, tokens);
            } catch (IOException ignored) {}
        }

        // 5. 이미지명 및 태그 계산
        String appName = extension.getAppName() != null && !extension.getAppName().isBlank() ? extension.getAppName()
                : project.getName();
        String tag = project.hasProperty("dockerImageTag") ? String.valueOf(project.property("dockerImageTag"))
                : (extension.getDockerImageTag() != null && !extension.getDockerImageTag().isBlank()
                        ? extension.getDockerImageTag()
                        : (project.getVersion() != null ? project.getVersion().toString() : "latest"));

        String rawRegistry = project.hasProperty("dockerRegistry") ? String.valueOf(project.property("dockerRegistry"))
                : (extension.getDockerRegistry() != null ? extension.getDockerRegistry() : "");
        String registry = cleanRegistryUrl(rawRegistry);

        if (requireRegistry && (registry == null || registry.isBlank())) {
            throw new RuntimeException("""
                    ❌ [Distribution] Docker Registry 설정이 필요합니다.
                       - CLI 옵션 예시: ./gradlew packageDockerRemote -Penv=prod -PdockerRegistry=my.reg.com/repo
                       - build.gradle DSL: distribution { dockerRegistry = 'my.reg.com/repo' }
                    """);
        }

        String fullImageName = (registry != null && !registry.isBlank())
                ? registry + "/" + appName + ":" + tag
                : appName + ":" + tag;

        // 6. docker build 실행
        project.getLogger().lifecycle("🔨 [Distribution] Docker 이미지 빌드 시작 -> {}", fullImageName);
        List<String> buildCmd = List.of(
                "docker", "build",
                "--build-arg", "APP_NAME=" + appName,
                "-t", fullImageName,
                "-f", dockerFile.getAbsolutePath(),
                dockerContextDir.getAbsolutePath()
        );

        runProcess(project, buildCmd, dockerContextDir, "Docker 이미지 빌드");
        project.getLogger().lifecycle("✨ [Distribution] Docker 이미지 빌드 성공: {}", fullImageName);

        return new DockerBuildContext(dockerContextDir, appName, tag, registry, fullImageName, packageType);
    }

    private void runProcess(Project project, List<String> command, File workDir, String taskDesc) {
        try {
            project.getLogger().lifecycle("▶️ [Distribution] 실행 명령어: {}", String.join(" ", command));
            ProcessBuilder pb = new ProcessBuilder(command);
            if (workDir != null && workDir.exists()) {
                pb.directory(workDir);
            }
            pb.inheritIO();
            Process process = pb.start();
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                throw new RuntimeException(taskDesc + " 실패 (종료 코드: " + exitCode + ")");
            }
        } catch (Exception e) {
            throw new RuntimeException(taskDesc + " 중 오류 발생: " + e.getMessage(), e);
        }
    }

    private void createTarAndZipArchive(File sourceDir, File zipFile) {
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zipFile))) {
            zos.setEncoding("UTF-8");
            addDirToZip(zos, sourceDir, sourceDir);
        } catch (IOException e) {
            throw new RuntimeException("Docker 배포 Zip 생성 실패: " + e.getMessage(), e);
        }
    }

    private void addDirToZip(ZipOutputStream zos, File currentFile, File rootDir) throws IOException {
        if (currentFile.isDirectory()) {
            File[] children = currentFile.listFiles();
            if (children != null) {
                for (File child : children) {
                    addDirToZip(zos, child, rootDir);
                }
            }
        } else {
            String relativePath = rootDir.toPath().relativize(currentFile.toPath()).toString().replace('\\', '/');
            ZipEntry entry = new ZipEntry(relativePath);
            if (currentFile.getName().endsWith(".sh")) {
                entry.setUnixMode(0755);
            } else {
                entry.setUnixMode(0644);
            }
            zos.putNextEntry(entry);
            try (FileInputStream fis = new FileInputStream(currentFile)) {
                fis.transferTo(zos);
            }
            zos.closeEntry();
        }
    }

    private void copyDirIfExists(File src, File dest) {
        if (src == null || !src.exists()) return;
        if (src.isDirectory()) {
            dest.mkdirs();
            File[] files = src.listFiles();
            if (files != null) {
                for (File f : files) {
                    copyDirIfExists(f, new File(dest, f.getName()));
                }
            }
        } else {
            if (dest.getParentFile() != null) dest.getParentFile().mkdirs();
            try {
                Files.copy(src.toPath(), dest.toPath(), StandardCopyOption.REPLACE_EXISTING);
                if (src.getName().endsWith(".sh")) {
                    dest.setExecutable(true, false);
                }
            } catch (IOException ignored) {}
        }
    }

    private void copyDockerComposeOnly(File dockerContextDir, File destDistDir) {
        File targetDockerDir = new File(destDistDir, "docker");
        targetDockerDir.mkdirs();
        File composeSrc = new File(dockerContextDir, "docker/docker-compose.yml");
        if (composeSrc.exists()) {
            try {
                Files.copy(composeSrc.toPath(), new File(targetDockerDir, "docker-compose.yml").toPath(),
                        StandardCopyOption.REPLACE_EXISTING);
            } catch (IOException ignored) {}
        }
    }

    private void printRemoteDeployBanner(Project project, DockerBuildContext ctx, File distDir) {
        String msg = String.format("""

                ╔══════════════════════════════════════════════════════════════════╗
                ║  ✅  Docker 이미지 Push 완료 (Strategy 2)                       ║
                ╠══════════════════════════════════════════════════════════════════╣
                ║  🖼️   이미지   : %s
                ║  📂  배포파일 : %s
                ║  📄  가이드   : %s/DEPLOY-GUIDE.md
                ╠══════════════════════════════════════════════════════════════════╣
                ║  🚀 서버 배포 순서 (운영 서버에서 실행)                         ║
                ╠══════════════════════════════════════════════════════════════════╣
                ║  [1] 배포 파일 서버 전송
                ║      scp -r %s/ user@your-server:/home/user/docker-dist
                ║
                ║  [2] Registry 로그인 (Private Registry 인증 필요 시)
                ║      docker login %s
                ║
                ║  [3] 자동 설치 (이미지 자동 Pull + Systemd 서비스 등록 — 권장)
                ║      cd /home/user/docker-dist
                ║      sudo ./deploy/install_service.sh
                ║
                ║  [4] 수동 실행 (필요 시 직접 docker compose 실행)
                ║      cd /home/user/docker-dist
                ║      docker compose -f docker/docker-compose.yml up -d
                ║
                ║  💡 상세 가이드: %s/DEPLOY-GUIDE.md
                ╚══════════════════════════════════════════════════════════════════╝
                """, ctx.fullImageName, distDir.getAbsolutePath(), distDir.getAbsolutePath(),
                distDir.getAbsolutePath(), ctx.registry, distDir.getAbsolutePath());
        project.getLogger().lifecycle(msg);
    }

    private String cleanRegistryUrl(String raw) {
        if (raw == null) return "";
        String reg = raw.trim().replaceAll("^https?://", "");
        if (reg.endsWith("/")) {
            reg = reg.substring(0, reg.length() - 1);
        }
        return reg;
    }

    private void updateDockerImageInDir(File dir, String oldImage, String newImage) {
        if (dir == null || !dir.exists()) return;
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File file : files) {
            if (file.isDirectory()) {
                updateDockerImageInDir(file, oldImage, newImage);
            } else {
                String name = file.getName();
                if (name.endsWith(".sh") || name.endsWith(".bat") || name.endsWith(".yml") || name.endsWith(".yaml")
                        || name.endsWith(".env") || name.endsWith(".md") || name.endsWith(".conf")) {
                    try {
                        String content = Files.readString(file.toPath(), StandardCharsets.UTF_8);
                        String updated = content.replace(oldImage, newImage).replace("@dockerImage@", newImage);
                        if (!content.equals(updated)) {
                            Files.writeString(file.toPath(), updated, StandardCharsets.UTF_8);
                        }
                    } catch (Exception ignored) {}
                }
            }
        }
    }

    private static class DockerBuildContext {
        final File dockerContextDir;
        final String appName;
        final String tag;
        final String registry;
        final String fullImageName;
        final String packageType;

        DockerBuildContext(File dockerContextDir, String appName, String tag, String registry,
                String fullImageName, String packageType) {
            this.dockerContextDir = dockerContextDir;
            this.appName = appName;
            this.tag = tag;
            this.registry = registry;
            this.fullImageName = fullImageName;
            this.packageType = packageType;
        }
    }
}
