package io.github.mj_youn.plugin;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.lang.reflect.Field;

import static org.junit.jupiter.api.Assertions.*;

class InitDeployScriptMojoTest {

    @Test
    @DisplayName("InitDeployScriptMojo는 지정된 OS 옵션에 따라 필요한 스크립트만 생성해야 한다.")
    void testInitDeployScriptByOs(@TempDir File tempDir) throws Exception {
        InitDeployScriptMojo mojo = new InitDeployScriptMojo();

        Field basedirField = InitDeployScriptMojo.class.getDeclaredField("basedir");
        basedirField.setAccessible(true);
        basedirField.set(mojo, tempDir);

        Field osField = InitDeployScriptMojo.class.getDeclaredField("os");
        osField.setAccessible(true);

        // 1. Windows 옵션 지정 시 build_deploy.bat만 생성
        osField.set(mojo, "windows");
        mojo.execute();

        File batFile = new File(tempDir, "build_deploy.bat");
        File shFile = new File(tempDir, "build_deploy.sh");
        assertTrue(batFile.exists(), "build_deploy.bat 파일이 생성되어야 합니다.");
        assertFalse(shFile.exists(), "build_deploy.sh 파일은 생성되지 않아야 합니다.");

        // 2. Linux 옵션 지정 시 build_deploy.sh만 생성
        batFile.delete();
        osField.set(mojo, "linux");
        mojo.execute();

        assertTrue(shFile.exists(), "build_deploy.sh 파일이 생성되어야 합니다.");
        assertFalse(batFile.exists(), "build_deploy.bat 파일은 생성되지 않아야 합니다.");
        assertTrue(shFile.canExecute(), "build_deploy.sh 파일에 실행 권한이 부여되어야 합니다.");

        // 3. all 옵션 지정 시 둘 다 생성
        osField.set(mojo, "all");
        mojo.execute();

        assertTrue(shFile.exists(), "build_deploy.sh 파일이 생성되어야 합니다.");
        assertTrue(batFile.exists(), "build_deploy.bat 파일이 생성되어야 합니다.");
    }
}
