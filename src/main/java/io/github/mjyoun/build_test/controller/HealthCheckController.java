package io.github.mjyoun.build_test.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 서비스 상태 확인을 위한 Health Check 컨트롤러
 *
 * @author 윤명준 (MJ Yune)
 * @since 2026-01-29
 */
@RestController
public class HealthCheckController {

    /**
     * 서비스 상태 확인 API
     *
     * @return "OK" 문자열
     */
    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}
