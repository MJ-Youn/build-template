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

        // 5. Extension DSL 프로퍼티 확인
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
}
