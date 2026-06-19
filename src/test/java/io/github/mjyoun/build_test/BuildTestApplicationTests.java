package io.github.mjyoun.build_test;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
class BuildTestApplicationTests {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void contextLoads() {}

	@Test
	void healthCheck() throws Exception {
		mockMvc.perform(get("/health")) //
				.andExpect(status().isOk()) //
				.andExpect(jsonPath("$.status").value("UP"));
	}

}
