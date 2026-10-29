package io.github.mjyoun.build_test;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * 빌드 템플릿 테스트용 Spring Boot 메인 애플리케이션 클래스입니다.
 *
 * @author 윤명준 (MJ Yun)
 * @since 2026. 09. 07.
 */
@SpringBootApplication
public class Application {

    /**
     * 애플리케이션 진입점 메인 메소드입니다.
     *
     * @param args 실행 명령행 인수
     */
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
