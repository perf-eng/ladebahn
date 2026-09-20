package de.ladebahn;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;

@TestConfiguration(proxyBeanMethods = false)
public class TestcontainersConfiguration {

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>(
                DockerImageName.parse("ladebahn/postgres:16-postgis")
                        .asCompatibleSubstituteFor("postgres"))
                .withDatabaseName("ladebahn_test")
                .withUsername("ladebahn")
                .withPassword("ladebahn")
                .withReuse(true);
    }
}