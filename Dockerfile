# syntax=docker/dockerfile:1

FROM eclipse-temurin:21-jdk-alpine AS gradle-base

WORKDIR /workspace

COPY gradlew settings.gradle.kts build.gradle.kts versions.properties ./
COPY gradle ./gradle

RUN chmod +x gradlew

COPY src ./src

FROM gradle-base AS test
ARG TEST_CACHEBUST=manual
RUN --mount=type=cache,target=/root/.gradle \
    echo "Running tests: ${TEST_CACHEBUST}" \
    && ./gradlew test --no-daemon --console=plain

FROM gradle-base AS build
RUN --mount=type=cache,target=/root/.gradle ./gradlew bootJar --no-daemon \
    && cp "$(find build/libs -maxdepth 1 -type f -name '*.jar' ! -name '*-plain.jar' | head -n 1)" app.jar

FROM eclipse-temurin:21-jre-alpine AS runtime

WORKDIR /app

RUN addgroup -S app && adduser -S app -G app

ENV SPRING_PROFILES_ACTIVE=dev
ENV JAVA_OPTS=""

EXPOSE 8080 9090

COPY --from=build /workspace/app.jar app.jar

USER app

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
