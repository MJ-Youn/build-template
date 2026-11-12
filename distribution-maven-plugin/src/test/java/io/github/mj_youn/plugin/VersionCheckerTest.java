package io.github.mj_youn.plugin;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class VersionCheckerTest {

    @Test
    @DisplayName("시맨틱 버전 비교 로직이 정상 동작해야 한다.")
    void testVersionComparison() {
        assertTrue(VersionChecker.isNewerVersion("3.5.0", "3.5.1"));
        assertTrue(VersionChecker.isNewerVersion("3.4.9", "3.5.0"));
        assertTrue(VersionChecker.isNewerVersion("3.5.0", "4.0.0"));
        assertTrue(VersionChecker.isNewerVersion("v3.5.0", "v3.5.1"));
        assertTrue(VersionChecker.isNewerVersion("3.5.0-SNAPSHOT", "3.5.1"));

        assertFalse(VersionChecker.isNewerVersion("3.5.1", "3.5.1"));
        assertFalse(VersionChecker.isNewerVersion("v3.5.1", "3.5.1"));

        assertFalse(VersionChecker.isNewerVersion("3.5.2", "3.5.1"));
        assertFalse(VersionChecker.isNewerVersion("4.0.0", "3.5.1"));
    }

    @Test
    @DisplayName("Maven metadata XML 및 GitHub JSON 본문에서 버전을 정확히 파싱해야 한다.")
    void testParseVersionFromBody() {
        String mavenXml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <metadata>
                  <groupId>io.github.mj-youn</groupId>
                  <artifactId>distribution-gradle-plugin</artifactId>
                  <versioning>
                    <latest>3.5.1</latest>
                    <release>3.5.1</release>
                  </versioning>
                </metadata>
                """;
        assertEquals("3.5.1", VersionChecker.parseVersionFromBody(mavenXml));

        String githubJson = """
                {
                  "url": "https://api.github.com/repos/MJ-Youn/build-template/releases/123",
                  "tag_name": "v3.5.1",
                  "name": "Release 3.5.1"
                }
                """;
        assertEquals("3.5.1", VersionChecker.parseVersionFromBody(githubJson));

        assertNull(VersionChecker.parseVersionFromBody(null));
        assertNull(VersionChecker.parseVersionFromBody(""));
        assertNull(VersionChecker.parseVersionFromBody("Not a version info"));
    }

    @Test
    @DisplayName("캐시에 최신 버전이 존재할 때 check() 메서드가 안내 배너를 출력해야 한다.")
    void testCheckOutputsNoticeWhenCacheHasNewerVersion() throws Exception {
        java.io.File cacheFile = new java.io.File(System.getProperty("user.home"), ".distribution/version-cache.properties");
        if (cacheFile.getParentFile() != null) {
            cacheFile.getParentFile().mkdirs();
        }
        java.util.Properties props = new java.util.Properties();
        props.setProperty("latest_version", "3.5.2");
        props.setProperty("last_check_time", String.valueOf(System.currentTimeMillis()));
        try (java.io.FileOutputStream fos = new java.io.FileOutputStream(cacheFile)) {
            props.store(fos, "test");
        }

        java.util.List<String> logs = new java.util.ArrayList<>();
        VersionChecker.check(logs::add, "3.5.0");

        assertFalse(logs.isEmpty(), "알림 배너가 출력되어야 합니다.");
        assertTrue(logs.stream().anyMatch(line -> line.contains("새로운 최신 버전이 출시되었습니다")), "최신 버전 알림 문구가 포함되어야 합니다.");
        assertTrue(logs.stream().anyMatch(line -> line.contains("v3.5.0 ➡️ v3.5.2")), "버전 변경 안내가 포함되어야 합니다.");
    }

    @Test
    @DisplayName("distribution.checkUpdates=false 설정 시 버전 체크가 비활성화되어야 한다.")
    void testCheckDisabled() {
        System.setProperty("distribution.checkUpdates", "false");
        try {
            java.util.List<String> logs = new java.util.ArrayList<>();
            VersionChecker.check(logs::add, "3.5.0");
            assertTrue(logs.isEmpty(), "비활성화 시 알림이 출력되지 않아야 합니다.");
        } finally {
            System.clearProperty("distribution.checkUpdates");
        }
    }
}

