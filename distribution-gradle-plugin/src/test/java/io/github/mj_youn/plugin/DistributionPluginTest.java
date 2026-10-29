package io.github.mj_youn.plugin;

import org.gradle.api.Project;
import org.gradle.api.Task;
import org.gradle.testfixtures.ProjectBuilder;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class DistributionPluginTest {

    @Test
    @DisplayName("Distribution 플러그인 적용 시 핵심 배포 태스크가 정상 등록되어야 한다.")
    void testPluginTaskRegistration() {
        Project project = ProjectBuilder.builder().build();
        project.getPlugins().apply("java");
        project.getPlugins().apply("io.github.mj-youn.distribution");

        // 1. 기존 package 태스크 확인
        Task packageTask = project.getTasks().findByName("package");
        assertNotNull(packageTask, "package 태스크가 등록되어 있어야 합니다.");

        // 2. 신규 Docker 배포 태스크 2개 확인
        Task packageDockerTask = project.getTasks().findByName("packageDocker");
        assertNotNull(packageDockerTask, "packageDocker 태스크가 등록되어 있어야 합니다.");

        Task packageDockerRemoteTask = project.getTasks().findByName("packageDockerRemote");
        assertNotNull(packageDockerRemoteTask, "packageDockerRemote 태스크가 등록되어 있어야 합니다.");

        // 3. 호환성 별칭 태스크 확인
        Task dockerBuildRemoteTask = project.getTasks().findByName("dockerBuildRemote");
        assertNotNull(dockerBuildRemoteTask, "dockerBuildRemote 별칭 태스크가 등록되어 있어야 합니다.");

        // 4. 독립 dockerBuild 태스크는 노출되지 않아야 함 (사용자 요청 사항)
        Task dockerBuildTask = project.getTasks().findByName("dockerBuild");
        assertNull(dockerBuildTask, "독립적인 dockerBuild 태스크는 등록되지 않아야 합니다.");

        // 5. 신규 환경변수 생성 태스크 확인
        assertNotNull(project.getTasks().findByName("initEnv"), "initEnv 태스크가 등록되어 있어야 합니다.");
        assertNotNull(project.getTasks().findByName("initApplicationEnv"), "initApplicationEnv 태스크가 등록되어 있어야 합니다.");

        // 6. Extension DSL 프로퍼티 확인
        DistributionExtension extension = project.getExtensions().findByType(DistributionExtension.class);
        assertNotNull(extension, "distribution extension이 존재해야 합니다.");

        extension.setDockerRegistry("my-registry.com/team");
        extension.setDockerImageTag("v1.2.3");
        assertEquals("my-registry.com/team", extension.getDockerRegistry());
        assertEquals("v1.2.3", extension.getDockerImageTag());
    }

    @Test
    @DisplayName("initDeployScript 태스크는 OS 및 옵션에 따라 필요한 배포 스크립트만 생성해야 한다.")
    void testInitDeployScriptByOs() {
        Project project = ProjectBuilder.builder().build();
        project.getPlugins().apply("java");
        project.getPlugins().apply("io.github.mj-youn.distribution");

        Task initTask = project.getTasks().findByName("initDeployScript");
        assertNotNull(initTask, "initDeployScript 태스크가 등록되어 있어야 합니다.");

        // 1. Windows 옵션 지정 시 build_deploy.bat만 생성
        project.getExtensions().getExtraProperties().set("os", "windows");
        initTask.getActions().get(0).execute(initTask);

        java.io.File batFile = project.file("build_deploy.bat");
        java.io.File shFile = project.file("build_deploy.sh");
        assertTrue(batFile.exists(), "build_deploy.bat 파일이 생성되어야 합니다.");
        assertFalse(shFile.exists(), "build_deploy.sh 파일은 생성되지 않아야 합니다.");

        // 2. Linux/Unix 옵션 지정 시 build_deploy.sh만 생성
        batFile.delete();
        project.getExtensions().getExtraProperties().set("os", "linux");
        initTask.getActions().get(0).execute(initTask);

        assertTrue(shFile.exists(), "build_deploy.sh 파일이 생성되어야 합니다.");
        assertFalse(batFile.exists(), "build_deploy.bat 파일은 생성되지 않아야 합니다.");
        assertTrue(shFile.canExecute(), "build_deploy.sh 파일에 실행 권한이 부여되어야 합니다.");

        // 3. all 옵션 지정 시 둘 다 생성
        project.getExtensions().getExtraProperties().set("os", "all");
        initTask.getActions().get(0).execute(initTask);

        assertTrue(shFile.exists(), "build_deploy.sh 파일이 생성되어야 합니다.");
        assertTrue(batFile.exists(), "build_deploy.bat 파일이 생성되어야 합니다.");
    }

    @Test
    @DisplayName("initDocker 태스크는 Dockerfile, docker-compose.yml, .env.example 및 docker.profiles 샘플을 정상 생성해야 한다.")
    void testInitDocker() {
        Project project = ProjectBuilder.builder().build();
        project.getPlugins().apply("java");
        project.getPlugins().apply("io.github.mj-youn.distribution");

        Task initDockerTask = project.getTasks().findByName("initDocker");
        assertNotNull(initDockerTask, "initDocker 태스크가 등록되어 있어야 합니다.");

        initDockerTask.getActions().get(0).execute(initDockerTask);

        java.io.File dockerfile = project.file("docker/Dockerfile");
        java.io.File composeFile = project.file("docker/docker-compose.yml");
        java.io.File envExample = project.file("docker/.env.example");
        java.io.File devEnvFile = project.file("docker.profiles/dev/.env-dev");
        java.io.File prodEnvFile = project.file("docker.profiles/prod/.env-prod");

        assertTrue(dockerfile.exists(), "docker/Dockerfile 파일이 생성되어야 합니다.");
        assertTrue(composeFile.exists(), "docker/docker-compose.yml 파일이 생성되어야 합니다.");
        assertTrue(envExample.exists(), "docker/.env.example 파일이 생성되어야 합니다.");
        assertTrue(project.file("docker/.dockerignore").exists(), "docker/.dockerignore 파일이 생성되어야 합니다.");
        assertTrue(project.file(".dockerignore").exists(), ".dockerignore 파일이 생성되어야 합니다.");
        assertTrue(devEnvFile.exists(), "docker.profiles/dev/.env-dev 파일이 생성되어야 합니다.");
        assertTrue(prodEnvFile.exists(), "docker.profiles/prod/.env-prod 파일이 생성되어야 합니다.");
    }

    @Test
    @DisplayName("initEnv 태스크는 Docker Compose용 .env 파일을 정상 생성해야 한다.")
    void testInitEnv() throws Exception {
        Project project = ProjectBuilder.builder().build();
        project.getPlugins().apply("java");
        project.getPlugins().apply("io.github.mj-youn.distribution");

        Task initEnvTask = project.getTasks().findByName("initEnv");
        assertNotNull(initEnvTask, "initEnv 태스크가 등록되어 있어야 합니다.");

        // 1. 프로파일 미지정 시 루트 .env 생성
        initEnvTask.getActions().get(0).execute(initEnvTask);

        java.io.File rootEnv = project.file(".env");
        assertTrue(rootEnv.exists(), "프로젝트 루트에 .env 파일이 생성되어야 합니다.");
        String content = java.nio.file.Files.readString(rootEnv.toPath());
        assertTrue(content.contains("APP_UID"), "Docker 실행을 위한 APP_UID 설정이 포함되어 있어야 합니다.");
        assertTrue(content.contains("HTTP_PORT"), "HTTP_PORT 설정이 포함되어 있어야 합니다.");

        // 2. profile 옵션 지정 시 docker.profiles/{profile}/.env-{profile} 생성
        project.getExtensions().getExtraProperties().set("profile", "dev");
        initEnvTask.getActions().get(0).execute(initEnvTask);

        java.io.File dockerProfileEnv = project.file("docker.profiles/dev/.env-dev");
        java.io.File configProfileEnv = project.file("config.profiles/dev/.env-dev");
        assertTrue(dockerProfileEnv.exists(), "docker.profiles/dev/.env-dev 파일이 생성되어야 합니다.");
        assertFalse(configProfileEnv.exists(), "initEnv 실행 시 config.profiles에는 생성되지 않아야 합니다.");
    }

    @Test
    @DisplayName("initApplicationEnv 태스크는 Spring Boot 런타임용 application.env 파일을 정상 생성해야 한다.")
    void testInitApplicationEnv() throws Exception {
        Project project = ProjectBuilder.builder().build();
        project.getPlugins().apply("java");
        project.getPlugins().apply("io.github.mj-youn.distribution");

        Task initAppEnvTask = project.getTasks().findByName("initApplicationEnv");
        assertNotNull(initAppEnvTask, "initApplicationEnv 태스크가 등록되어 있어야 합니다.");

        // 1. 프로파일 미지정 시 기본 config.profiles/dev/application-dev.env 생성
        initAppEnvTask.getActions().get(0).execute(initAppEnvTask);

        java.io.File devAppEnv = project.file("config.profiles/dev/application-dev.env");
        assertTrue(devAppEnv.exists(), "config.profiles/dev/application-dev.env 파일이 생성되어야 합니다.");

        String content = java.nio.file.Files.readString(devAppEnv.toPath());
        assertTrue(content.contains("JVM_XMS"), "JVM_XMS 설정이 포함되어 있어야 합니다.");
        assertTrue(content.contains("JVM_XMX"), "JVM_XMX 설정이 포함되어 있어야 합니다.");
        assertTrue(content.contains("APP_ARGS"), "APP_ARGS 설정이 포함되어 있어야 합니다.");

        // 2. profile=prod 지정 시 config.profiles/prod/application-prod.env 생성
        project.getExtensions().getExtraProperties().set("profile", "prod");
        initAppEnvTask.getActions().get(0).execute(initAppEnvTask);

        java.io.File prodAppEnv = project.file("config.profiles/prod/application-prod.env");
        assertTrue(prodAppEnv.exists(), "config.profiles/prod/application-prod.env 파일이 생성되어야 합니다.");
    }
}
