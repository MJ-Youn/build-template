package io.github.mj_youn.plugin;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.lang.reflect.Field;
import java.nio.file.Files;

import static org.junit.jupiter.api.Assertions.*;

/**
 * InitEnvMojo 단위 테스트 클래스입니다.
 *
 * @author 윤명준 (MJ Yun)
 * @since 2026. 10. 28.
 */
class InitEnvMojoTest {

    @Test
    @DisplayName("InitEnvMojo 실행 시 .env.example을 기반으로 루트 .env 파일이 정상 생성되어야 한다.")
    void testInitEnvBasic(@TempDir File tempDir) throws Exception {
        InitEnvMojo mojo = new InitEnvMojo();

        setField(mojo, "basedir", tempDir);
        setField(mojo, "httpPort", 8443);
        setField(mojo, "appName", "test-app");

        mojo.execute();

        File rootEnv = new File(tempDir, ".env");
        assertTrue(rootEnv.exists(), "프로젝트 루트에 .env 파일이 생성되어야 합니다.");

        String content = Files.readString(rootEnv.toPath());
        assertTrue(content.contains("JVM_XMS"), "JVM_XMS 설정이 포함되어 있어야 합니다.");
        assertTrue(content.contains("SERVER_PORT=@httpPort@"), "SERVER_PORT는 빌드 시점 치환을 위해 @httpPort@ 원형을 유지해야 합니다.");
    }

    @Test
    @DisplayName("InitEnvMojo 실행 시 기존 파일이 존재하면 force=false일 때 스킵하고 force=true일 때 덮어써야 한다.")
    void testInitEnvForce(@TempDir File tempDir) throws Exception {
        InitEnvMojo mojo = new InitEnvMojo();

        setField(mojo, "basedir", tempDir);
        setField(mojo, "httpPort", 8443);
        setField(mojo, "appName", "test-app");

        File rootEnv = new File(tempDir, ".env");
        Files.writeString(rootEnv.toPath(), "CUSTOM_CONFIG=existing_value\n");

        // 1. force=false 로 실행
        setField(mojo, "force", false);
        mojo.execute();

        String contentWithoutForce = Files.readString(rootEnv.toPath());
        assertTrue(contentWithoutForce.contains("CUSTOM_CONFIG=existing_value"), "force=false 시 기존 내용이 보존되어야 합니다.");

        // 2. force=true 로 실행
        setField(mojo, "force", true);
        mojo.execute();

        String contentWithForce = Files.readString(rootEnv.toPath());
        assertTrue(contentWithForce.contains("JVM_XMS"), "force=true 시 템플릿 내용으로 덮어써져야 합니다.");
    }

    @Test
    @DisplayName("InitEnvMojo 실행 시 profile 옵션 지정 시 프로파일 디렉토리에 .env 파일이 생성되어야 한다.")
    void testInitEnvWithProfile(@TempDir File tempDir) throws Exception {
        InitEnvMojo mojo = new InitEnvMojo();

        setField(mojo, "basedir", tempDir);
        setField(mojo, "profile", "dev");
        setField(mojo, "httpPort", 8080);
        setField(mojo, "appName", "my-app");

        mojo.execute();

        File configProfileEnv = new File(tempDir, "config.profiles/dev/.env-dev");
        File dockerProfileEnv = new File(tempDir, "docker.profiles/dev/.env-dev");
        File rootEnv = new File(tempDir, ".env");

        assertTrue(configProfileEnv.exists(), "config.profiles/dev/.env-dev 파일이 생성되어야 합니다.");
        assertFalse(dockerProfileEnv.exists(), "기본 실행 시 docker.profiles 에는 생성되지 않아야 합니다.");
        assertFalse(rootEnv.exists(), "profile 지정 시 루트 .env 는 중복 생성되지 않아야 합니다.");
    }

    private void setField(Object target, String fieldName, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }
}
