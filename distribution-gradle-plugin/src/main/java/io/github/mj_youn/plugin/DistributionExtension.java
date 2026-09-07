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
 *     token 'customKey', 'customValue'
 * }
 * </pre>
 *
 * @author MJ Yun
 * @since 2026. 09. 07.
 */
public class DistributionExtension {

    private final Project project;
    private String appName;
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
     */
    public List<String> getExtraDirs() {
        return extraDirs;
    }

    /**
     * 배포 패키지 루트에 함께 포함할 추가 디렉토리를 설정합니다.
     */
    public void setExtraDirs(List<String> extraDirs) {
        this.extraDirs.clear();
        if (extraDirs != null) {
            this.extraDirs.addAll(extraDirs);
        }
    }

    /**
     * 배포 패키지 루트에 함께 포함할 추가 디렉토리를 추가합니다.
     */
    public void extraDir(String dir) {
        this.extraDirs.add(dir);
    }
}
