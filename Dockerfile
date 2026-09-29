# Ladebahn app image. Built by the "Deploy to demo server" GitHub Action and published
# to ghcr.io/perf-eng/ladebahn:<commit>. The server only downloads it.

# ---- build ----
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src

# Dependencies first, in their own layer: changing Java code doesn't re-download them
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon || true

COPY src ./src
RUN ./gradlew bootJar --no-daemon

# ---- runtime ----
FROM eclipse-temurin:21-jre
WORKDIR /app

# Pinned, like everything else we measure with (was "latest")
ARG OTEL_AGENT_VERSION=2.31.1
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar /app/otel-agent.jar

COPY --from=build /src/build/libs/ladebahn-0.0.1-SNAPSHOT.jar /app/app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-javaagent:/app/otel-agent.jar", "-XX:MaxRAMPercentage=60", "-jar", "/app/app.jar"]
