package io.github.mj_youn.plugin;

import org.apache.maven.plugins.annotations.Mojo;

/**
 * Maven 배포 플러그인의 사용 가이드 및 명령어 안내를 출력하는 Goal (distHelp alias)입니다.
 *
 * @author MJ Yun
 * @since 2026. 09. 09.
 */
@Mojo(name = "distHelp", requiresProject = false, threadSafe = true)
public class DistHelpMojo extends HelpMojo {

    /**
     * DistHelpMojo 기본 생성자입니다.
     */
    public DistHelpMojo() {
        super();
    }
}
