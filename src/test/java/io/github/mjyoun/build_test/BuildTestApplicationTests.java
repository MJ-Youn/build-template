package io.github.mjyoun.build_test;

import io.github.mjyoun.build_test.controller.HealthCheckController;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class BuildTestApplicationTests {

	@Autowired
	private HealthCheckController healthCheckController;

	@Test
	void contextLoads() {
		assertThat(healthCheckController).isNotNull();
	}

}
