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
}
