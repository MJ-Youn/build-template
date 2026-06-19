package io.github.mjyoun.build_test.controller;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

/**
 * HealthCheckController에 대한 통합 테스트
 */
@SpringBootTest
class HealthCheckControllerTest {

    @Test
    @DisplayName("Health Check API는 OK를 반환해야 한다")
    void healthCheckReturnsOk() throws Exception {
        mockMvc.perform(get("/health")) //
                .andExpect(status().isOk()) //
                .andExpect(content().string("OK"));
    }

    @Autowired
    private MockMvc mockMvc;
}
