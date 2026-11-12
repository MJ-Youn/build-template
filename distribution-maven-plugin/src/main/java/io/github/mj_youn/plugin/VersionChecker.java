package io.github.mj_youn.plugin;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Properties;
import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 플러그인의 최신 릴리즈 버전을 백그라운드로 안전하게 확인하여 업데이트 알림을 제공하는 유틸리티 클래스입니다.
 * <p>
 * 메인 빌드 스레드를 전혀 지연시키지 않도록 로컬 캐싱(24시간) 및 백그라운드 비동기 조회 방식을 사용하며,
 * 오프라인이나 폐쇄망 환경에서도 0.5초 타임아웃 및 무중단 예외 격리(Silent Fail)를 보장합니다.
 * </p>
 *
 * @author 윤명준 (MJ Yun)
 * @since 2026. 11. 11.
 */
public final class VersionChecker {

    /** 기본 캐시 유지 시간: 24시간 (밀리초) */
    private static final long CACHE_TTL_MS = 24L * 60L * 60L * 1000L;

    /** 연결 및 읽기 타임아웃: 500ms (오프라인/폐쇄망 지연 방지) */
    private static final int NETWORK_TIMEOUT_MS = 500;

    /** Maven Central 원격 메타데이터 URL */
    private static final String MAVEN_CENTRAL_METADATA_URL =
            "https://repo1.maven.org/maven2/io/github/mj-youn/distribution-gradle-plugin/maven-metadata.xml";

    /** GitHub 최신 릴리즈 API URL */
    private static final String GITHUB_RELEASE_API_URL =
            "https://api.github.com/repos/MJ-Youn/build-template/releases/latest";

    private VersionChecker() {
    }

    /**
     * 현재 사용 중인 플러그인 버전과 최신 버전을 비교하여, 업데이트가 존재하는 경우 안내 메시지를 출력합니다.
     *
     * @param logger 알림 메시지를 출력할 로거 함수
     * @param currentVersion 현재 플러그인 버전 (예: "3.5.0")
     */
    public static void check(Consumer<String> logger, String currentVersion) {
        // 비활성화 옵션 확인 (-Ddistribution.checkUpdates=false 또는 환경변수 DISTRIBUTION_CHECK_UPDATES=false)
        if (isUpdateCheckDisabled()) {
            return;
        }

        try {
            File cacheFile = getCacheFile();
            Properties cache = loadCache(cacheFile);

            String cachedLatest = cache.getProperty("latest_version");
            long lastChecked = parseLongQuietly(cache.getProperty("last_check_time"), 0L);
            long now = System.currentTimeMillis();

            // 1. 캐시된 최신 버전이 있고, 현재 버전보다 높으면 알림 출력
            if (cachedLatest != null && !cachedLatest.isBlank() && isNewerVersion(currentVersion, cachedLatest)) {
                printUpdateNotice(logger, currentVersion, cachedLatest);
            }

            // 2. 캐시 만료 시 (24시간 경과 또는 최초 실행), 백그라운드 데몬 스레드에서 원격 비동기 갱신
            if (now - lastChecked > CACHE_TTL_MS) {
                Thread worker = new Thread(() -> refreshCacheAsync(cacheFile, currentVersion, logger), "distribution-version-checker");
                worker.setDaemon(true);
                worker.start();
            }
        } catch (Throwable ignored) {
            // 폐쇄망 또는 예외 상황 시 빌드 프로세스에 영향 없도록 무시
        }
    }

    /**
     * 원격 저장소에서 최신 버전을 조회하여 캐시 파일에 저장합니다.
     *
     * @param cacheFile 캐시 파일
     * @param currentVersion 현재 플러그인 버전
     * @param logger 로거 함수
     */
    private static void refreshCacheAsync(File cacheFile, String currentVersion, Consumer<String> logger) {
        try {
            String remoteVersion = fetchRemoteLatestVersion();
            if (remoteVersion != null && !remoteVersion.isBlank()) {
                Properties props = new Properties();
                props.setProperty("latest_version", remoteVersion);
                props.setProperty("last_check_time", String.valueOf(System.currentTimeMillis()));

                if (cacheFile.getParentFile() != null && !cacheFile.getParentFile().exists()) {
                    cacheFile.getParentFile().mkdirs();
                }
                try (FileOutputStream fos = new FileOutputStream(cacheFile)) {
                    props.store(fos, "Distribution Plugin Version Check Cache");
                }

                // 최초 캐시 생성 시 즉시 최신 버전 알림 가능 여부 확인
                if (isNewerVersion(currentVersion, remoteVersion)) {
                    printUpdateNotice(logger, currentVersion, remoteVersion);
                }
            }
        } catch (Throwable ignored) {
            // 네트워크 오류 또는 폐쇄망 환경 무시
        }
    }

    /**
     * 원격 저장소(Maven Central 또는 GitHub)에서 최신 버전 문자열을 조회합니다.
     *
     * @return 최신 버전 문자열 또는 null
     */
    private static String fetchRemoteLatestVersion() {
        // 커스텀 업데이트 URL 지원 (-Ddistribution.updateUrl=... 또는 환경변수 DISTRIBUTION_UPDATE_URL)
        String customUrl = System.getProperty("distribution.updateUrl", System.getenv("DISTRIBUTION_UPDATE_URL"));
        if (customUrl != null && !customUrl.isBlank()) {
            String version = fetchFromUrl(customUrl);
            if (version != null) {
                return version;
            }
        }

        // 1순위: Maven Central 메타데이터 조회
        String mcVersion = fetchFromUrl(MAVEN_CENTRAL_METADATA_URL);
        if (mcVersion != null) {
            return mcVersion;
        }

        // 2순위: GitHub 최신 릴리즈 API 조회
        return fetchFromUrl(GITHUB_RELEASE_API_URL);
    }

    /**
     * 지정된 URL에서 최신 버전 문자열을 파싱하여 반환합니다.
     *
     * @param endpoint URL 엔드포인트
     * @return 파싱된 최신 버전 또는 null
     */
    private static String fetchFromUrl(String endpoint) {
        try {
            URL url = URI.create(endpoint).toURL();
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(NETWORK_TIMEOUT_MS);
            conn.setReadTimeout(NETWORK_TIMEOUT_MS);
            conn.setRequestProperty("User-Agent", "Distribution-Plugin-Version-Checker");
            conn.setRequestProperty("Accept", "application/json, application/xml, text/xml");

            int responseCode = conn.getResponseCode();
            if (responseCode == 200) {
                try (InputStream in = conn.getInputStream()) {
                    String body = new String(in.readAllBytes(), StandardCharsets.UTF_8);
                    return parseVersionFromBody(body);
                }
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    /**
     * HTTP 응답 본문(XML 또는 JSON)에서 버전 문자열을 추출합니다.
     *
     * @param body 응답 본문 문자열
     * @return 추출된 버전 문자열 또는 null
     */
    static String parseVersionFromBody(String body) {
        if (body == null || body.isBlank()) {
            return null;
        }

        // 1. Maven metadata XML: <release>3.5.1</release> 또는 <latest>3.5.1</latest>
        Pattern xmlPattern = Pattern.compile("<(?:release|latest)>([0-9A-Za-z._-]+)</(?:release|latest)>");
        Matcher xmlMatcher = xmlPattern.matcher(body);
        if (xmlMatcher.find()) {
            return xmlMatcher.group(1).trim();
        }

        // 2. GitHub JSON: "tag_name": "v3.5.1" 또는 "3.5.1"
        Pattern jsonPattern = Pattern.compile("\"tag_name\"\\s*:\\s*\"[vV]?([0-9A-Za-z._-]+)\"");
        Matcher jsonMatcher = jsonPattern.matcher(body);
        if (jsonMatcher.find()) {
            return jsonMatcher.group(1).trim();
        }

        return null;
    }

    /**
     * 최신 버전(remoteVersion)이 현재 버전(currentVersion)보다 높은지 여부를 판단합니다.
     *
     * @param currentVersion 현재 버전 (예: "3.5.0")
     * @param remoteVersion 원격 최신 버전 (예: "3.5.1")
     * @return remoteVersion이 더 최신이면 true
     */
    public static boolean isNewerVersion(String currentVersion, String remoteVersion) {
        if (currentVersion == null || remoteVersion == null) {
            return false;
        }
        return compareVersions(currentVersion, remoteVersion) < 0;
    }

    /**
     * 두 버전 문자열을 비교합니다. (Semantic Versioning 기반)
     *
     * @param v1 버전 1
     * @param v2 버전 2
     * @return v1이 더 크면 양수, v2가 더 크면 음수, 같으면 0
     */
    public static int compareVersions(String v1, String v2) {
        String cleanV1 = v1.replaceAll("^[vV]", "").replaceAll("-SNAPSHOT$", "").trim();
        String cleanV2 = v2.replaceAll("^[vV]", "").replaceAll("-SNAPSHOT$", "").trim();

        String[] parts1 = cleanV1.split("[.\\-_]");
        String[] parts2 = cleanV2.split("[.\\-_]");

        int length = Math.max(parts1.length, parts2.length);
        for (int i = 0; i < length; i++) {
            int num1 = i < parts1.length ? parseNumberQuietly(parts1[i]) : 0;
            int num2 = i < parts2.length ? parseNumberQuietly(parts2[i]) : 0;
            if (num1 != num2) {
                return Integer.compare(num1, num2);
            }
        }
        return 0;
    }

    /**
     * 업데이트 알림 배너를 콘솔에 출력합니다.
     *
     * @param logger 로거 함수
     * @param current 현재 버전
     * @param latest 최신 버전
     */
    private static void printUpdateNotice(Consumer<String> logger, String current, String latest) {
        logger.accept("----------------------------------------------------------------");
        logger.accept(String.format("💡 [Distribution] 새로운 최신 버전이 출시되었습니다! (v%s ➡️ v%s)", current, latest));
        logger.accept(String.format("   - Gradle: id 'io.github.mj-youn.distribution' version '%s'", latest));
        logger.accept(String.format("   - Maven : <version>%s</version>", latest));
        logger.accept("   - 릴리즈 정보: https://github.com/MJ-Youn/build-template/releases");
        logger.accept("----------------------------------------------------------------");
    }

    /**
     * 업데이트 체크 비활성화 여부를 확인합니다.
     *
     * @return 비활성화 시 true
     */
    private static boolean isUpdateCheckDisabled() {
        String sysProp = System.getProperty("distribution.checkUpdates");
        if ("false".equalsIgnoreCase(sysProp)) {
            return true;
        }
        String envProp = System.getenv("DISTRIBUTION_CHECK_UPDATES");
        return "false".equalsIgnoreCase(envProp);
    }

    /**
     * 로컬 캐시 파일 객체를 반환합니다. (~/.distribution/version-cache.properties)
     *
     * @return 캐시 파일 객체
     */
    private static File getCacheFile() {
        String userHome = System.getProperty("user.home", ".");
        return new File(userHome, ".distribution/version-cache.properties");
    }

    /**
     * 캐시 파일을 로드합니다.
     *
     * @param file 캐시 파일
     * @return 로드된 Properties 객체
     */
    private static Properties loadCache(File file) {
        Properties props = new Properties();
        if (file.exists() && file.isFile()) {
            try (FileInputStream fis = new FileInputStream(file)) {
                props.load(fis);
            } catch (Throwable ignored) {
            }
        }
        return props;
    }

    private static int parseNumberQuietly(String s) {
        try {
            return Integer.parseInt(s.replaceAll("[^0-9]", ""));
        } catch (Exception e) {
            return 0;
        }
    }

    private static long parseLongQuietly(String s, long defaultValue) {
        try {
            return Long.parseLong(s);
        } catch (Exception e) {
            return defaultValue;
        }
    }
}

