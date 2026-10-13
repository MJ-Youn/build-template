package io.github.mj_youn.plugin;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.lang.reflect.Field;

import static org.junit.jupiter.api.Assertions.*;

/**
 * InitDockerMojo 테스트 클래스입니다.
 *
 * @author MJ Yun
 * @since 2026. 10. 12.
 */
class InitDockerMojoTest {

    @Test
    @DisplayName("InitDockerMojo 실행 시 Dockerfile, docker-compose.yml, .env.example 및 docker.profiles 샘플이 생성되어야 한다.")
    void testInitDocker(@TempDir File tempDir) throws Exception {
        InitDockerMojo mojo = new InitDockerMojo();

        Field basedirField = InitDockerMojo.class.getDeclaredField("basedir");
        basedirField.setAccessible(true);
        basedirField.set(mojo, tempDir);

        Field packageTypeField = InitDockerMojo.class.getDeclaredField("packageType");
        packageTypeField.setAccessible(true);
        packageTypeField.set(mojo, "jar");

        Field httpPortField = InitDockerMojo.class.getDeclaredField("httpPort");
        httpPortField.setAccessible(true);
        httpPortField.setInt(mojo, 8443);

        mojo.execute();

        File dockerfile = new File(tempDir, "docker/Dockerfile");
        File composeFile = new File(tempDir, "docker/docker-compose.yml");
        File envExample = new File(tempDir, "docker/.env.example");
        File devEnvFile = new File(tempDir, "docker.profiles/dev/.env-dev");
        File prodEnvFile = new File(tempDir, "docker.profiles/prod/.env-prod");

        File dockerignore = new File(tempDir, "docker/.dockerignore");
        File rootDockerignore = new File(tempDir, ".dockerignore");

        assertTrue(dockerfile.exists(), "docker/Dockerfile 파일이 생성되어야 합니다.");
        assertTrue(composeFile.exists(), "docker/docker-compose.yml 파일이 생성되어야 합니다.");
        assertTrue(envExample.exists(), "docker/.env.example 파일이 생성되어야 합니다.");
        assertTrue(dockerignore.exists(), "docker/.dockerignore 파일이 생성되어야 합니다.");
        assertTrue(rootDockerignore.exists(), ".dockerignore 파일이 생성되어야 합니다.");
        assertTrue(devEnvFile.exists(), "docker.profiles/dev/.env-dev 파일이 생성되어야 합니다.");
        assertTrue(prodEnvFile.exists(), "docker.profiles/prod/.env-prod 파일이 생성되어야 합니다.");
    }
}
