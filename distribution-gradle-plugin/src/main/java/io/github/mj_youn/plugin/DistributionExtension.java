package io.github.mj_youn.plugin;

import org.gradle.api.Project;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * DistributionPlugin의 빌드 설정 DSL 확장 클래스입니다.
 *
 * 사용 예시:
 * 
 * <pre>
 * distribution {
 *     appName = 'my-custom-service'
 *     packageType = 'tomcat' // 'jar' (기본값) 또는 'tomcat'
 *     tomcatVersion = '11.0.15'
 *     httpPort = 8083
 *     os = 'linux' // 'windows', 'all'
 *     token 'customKey', 'customValue'
 *     extraDir 'webapps'
 * }
 * </pre>
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
 */
public class DistributionExtension {

    private final Project project;
    private String appName;
    private String packageType = "jar";
    private String tomcatVersion = "11.0.15";
    private int httpPort = 443;
    private String os = "linux";
    private String dockerRegistry;
    private String dockerImageTag;
    private final Map<String, Object> extraTokens = new HashMap<>();
    private final List<String> extraDirs = new ArrayList<>();

    /**
     * DistributionExtension 생성자입니다.
     *
     * @param project
     *            Gradle 프로젝트 인스턴스
     */
    public DistributionExtension(Project project) {
        this.project = project;
        this.appName = project.getName();
    }

    /**
     * 패키징 및 스크립트 치환에 사용할 애플리케이션 이름을 반환합니다.
     *
     * @return 애플리케이션 이름 (기본값: project.name)
     */
    public String getAppName() {
        return appName;
    }

    /**
     * 패키징 및 스크립트 치환에 사용할 애플리케이션 이름을 설정합니다.
     *
     * @param appName
     *            설정할 애플리케이션 이름
     */
    public void setAppName(String appName) {
        this.appName = appName;
    }

    /**
     * 배포 패키지 유형('jar' 또는 'tomcat')을 반환합니다.
     *
     * @return 패키지 유형 (기본값: "jar")
     */
    public String getPackageType() {
        return packageType;
    }

    /**
     * 배포 패키지 유형을 설정합니다 ('jar' 또는 'tomcat').
     *
     * @param packageType
     *            설정할 패키지 유형
     */
    public void setPackageType(String packageType) {
        this.packageType = packageType;
    }

    /**
     * 현재 설정된 패키지 유형이 톰캣 배포 모드인지 여부를 확인합니다.
     *
     * @return 톰캣 배포 모드 여부
     */
    public boolean isTomcat() {
        return "tomcat".equalsIgnoreCase(packageType) || "war".equalsIgnoreCase(packageType);
    }

    /**
     * 톰캣 배포 시 사용할 기본 톰캣 버전을 반환합니다.
     *
     * @return 톰캣 버전 (기본값: "11.0.15")
     */
    public String getTomcatVersion() {
        return tomcatVersion;
    }

    /**
     * 톰캣 배포 시 사용할 톰캣 버전을 설정합니다.
     *
     * @param tomcatVersion
     *            톰캣 버전
     */
    public void setTomcatVersion(String tomcatVersion) {
        this.tomcatVersion = tomcatVersion;
    }

    /**
     * HTTP 서비스 포트 번호를 반환합니다.
     *
     * @return HTTP 포트 (기본값: 443)
     */
    public int getHttpPort() {
        return httpPort;
    }

    /**
     * HTTP 서비스 포트 번호를 설정합니다.
     *
     * @param httpPort
     *            HTTP 포트 번호
     */
    public void setHttpPort(int httpPort) {
        this.httpPort = httpPort;
    }

    /**
     * 스크립트 치환에 사용할 추가 사용자 정의 토큰 맵을 반환합니다.
     *
     * @return 추가 토큰 맵
     */
    public Map<String, Object> getExtraTokens() {
        return extraTokens;
    }

    /**
     * 스크립트 필터링(ReplaceTokens)에 사용할 커스텀 토큰을 추가합니다.
     *
     * @param key
     *            토큰 키
     * @param value
     *            토큰 값
     */
    public void token(String key, Object value) {
        this.extraTokens.put(key, value);
    }

    /**
     * 배포 패키지 루트에 함께 포함할 추가 디렉토리 목록을 반환합니다.
     *
     * @return 추가 디렉토리 목록
     */
    public List<String> getExtraDirs() {
        return extraDirs;
    }

    /**
     * 배포 패키지 루트에 함께 포함할 추가 디렉토리를 설정합니다.
     *
     * @param extraDirs
     *            추가 디렉토리 목록
     */
    public void setExtraDirs(List<String> extraDirs) {
        this.extraDirs.clear();
        if (extraDirs != null) {
            this.extraDirs.addAll(extraDirs);
        }
    }

    /**
     * 배포 패키지 루트에 함께 포함할 추가 디렉토리를 하나 추가합니다.
     *
     * @param extraDir
     *            추가 디렉토리 이름
     */
    public void extraDir(String extraDir) {
        if (extraDir != null && !extraDir.trim().isEmpty()) {
            this.extraDirs.add(extraDir.trim());
        }
    }

    /**
     * 배포 대상 운영체제('linux', 'windows', 'all')를 반환합니다.
     *
     * @return 대상 운영체제 (기본값: "linux")
     */
    public String getOs() {
        return os;
    }

    /**
     * 배포 대상 운영체제를 설정합니다 ('linux', 'windows', 'all').
     *
     * @param os
     *            설정할 대상 운영체제
     */
    public void setOs(String os) {
        this.os = os;
    }

    /**
     * Docker 원격 레지스트리 URL을 반환합니다.
     *
     * @return 원격 레지스트리 URL (예: my.registry.com/repo)
     */
    public String getDockerRegistry() {
        return dockerRegistry;
    }

    /**
     * Docker 원격 레지스트리 URL을 설정합니다.
     *
     * @param dockerRegistry 원격 레지스트리 URL
     */
    public void setDockerRegistry(String dockerRegistry) {
        this.dockerRegistry = dockerRegistry;
    }

    /**
     * Docker 이미지 태그를 반환합니다.
     *
     * @return Docker 이미지 태그 (기본값: null -> project.version 사용)
     */
    public String getDockerImageTag() {
        return dockerImageTag;
    }

    /**
     * Docker 이미지 태그를 설정합니다.
     *
     * @param dockerImageTag Docker 이미지 태그
     */
    public void setDockerImageTag(String dockerImageTag) {
        this.dockerImageTag = dockerImageTag;
    }
}
