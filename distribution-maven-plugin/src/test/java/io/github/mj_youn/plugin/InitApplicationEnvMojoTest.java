package io.github.mj_youn.plugin;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.lang.reflect.Field;
import java.nio.file.Files;

import static org.junit.jupiter.api.Assertions.*;

/**
 * InitApplicationEnvMojo 단위 테스트 클래스입니다.
 *
 * @author 윤명준 (MJ Yun)
 * @since 2026. 10. 29.
 */
class InitApplicationEnvMojoTest {

    @Test
    @DisplayName("InitApplicationEnvMojo 실행 시 Spring Boot 런타임용 application.env 파일이 정상 생성되어야 한다.")
    void testInitApplicationEnvBasic(@TempDir File tempDir) throws Exception {
        InitApplicationEnvMojo mojo = new InitApplicationEnvMojo();

        setField(mojo, "basedir", tempDir);
        setField(mojo, "httpPort", 8443);
        setField(mojo, "appName", "test-app");

        mojo.execute();

        File appEnv = new File(tempDir, "config.profiles/dev/application-dev.env");
        assertTrue(appEnv.exists(), "config.profiles/dev/application-dev.env 파일이 생성되어야 합니다.");

        String content = Files.readString(appEnv.toPath());
        assertTrue(content.contains("JVM_XMS"), "JVM_XMS 설정이 포함되어 있어야 합니다.");
        assertTrue(content.contains("JVM_XMX"), "JVM_XMX 설정이 포함되어 있어야 합니다.");
        assertTrue(content.contains("APP_ARGS"), "APP_ARGS 설정이 포함되어 있어야 합니다.");
    }

    @Test
    @DisplayName("InitApplicationEnvMojo 실행 시 profile=prod 지정 시 application-prod.env 파일이 생성되어야 한다.")
    void testInitApplicationEnvWithProfile(@TempDir File tempDir) throws Exception {
        InitApplicationEnvMojo mojo = new InitApplicationEnvMojo();

        setField(mojo, "basedir", tempDir);
        setField(mojo, "profile", "prod");
        setField(mojo, "httpPort", 8080);
        setField(mojo, "appName", "my-app");

        mojo.execute();

        File prodAppEnv = new File(tempDir, "config.profiles/prod/application-prod.env");
        File devAppEnv = new File(tempDir, "config.profiles/dev/application-dev.env");

        assertTrue(prodAppEnv.exists(), "config.profiles/prod/application-prod.env 파일이 생성되어야 합니다.");
        assertFalse(devAppEnv.exists(), "profile=prod 지정 시 dev 파일은 생성되지 않아야 합니다.");
    }

    private void setField(Object target, String fieldName, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }
}
