package de.ladebahn;

import org.springframework.boot.SpringApplication;

public class TestLadebahnApplication {

	public static void main(String[] args) {
		SpringApplication.from(LadebahnApplication::main).with(TestcontainersConfiguration.class).run(args);
	}

}
