DOCKER_IMAGE ?= project-devops-deploy
DOCKER_TAG ?= local
APP_PORT ?= 8080
MANAGEMENT_PORT ?= 9090
DOCKER_RUN_ARGS ?=

help:
	@printf '%s\n' 'Available commands:'
	@printf '  %-18s %s\n' 'make help' 'Show this help message.'
	@printf '  %-18s %s\n' 'make test' 'Run backend tests with Gradle.'
	@printf '  %-18s %s\n' 'make run' 'Start the backend locally with Gradle.'
	@printf '  %-18s %s\n' 'make start' 'Alias for make run.'
	@printf '  %-18s %s\n' 'make build' 'Build and test the backend with Gradle.'
	@printf '  %-18s %s\n' 'make install' 'Resolve Gradle dependencies.'
	@printf '  %-18s %s\n' 'make lint' 'Check Java formatting with Spotless.'
	@printf '  %-18s %s\n' 'make lint-fix' 'Apply Java formatting with Spotless.'
	@printf '  %-18s %s\n' 'make update-gradle' 'Update the Gradle wrapper version.'
	@printf '  %-18s %s\n' 'make update-deps' 'Refresh dependency versions.'
	@printf '  %-18s %s\n' 'make docker-test' 'Run backend tests inside Docker with visible output.'
	@printf '  %-18s %s\n' 'make docker-build' 'Build the Docker image.'
	@printf '  %-18s %s\n' 'make docker-run' 'Run the Docker image on APP_PORT and MANAGEMENT_PORT.'
	@printf '\n%s\n' 'Docker variables:'
	@printf '  %-18s %s\n' 'DOCKER_IMAGE' 'Image name, default: project-devops-deploy.'
	@printf '  %-18s %s\n' 'DOCKER_TAG' 'Image tag, default: local.'
	@printf '  %-18s %s\n' 'APP_PORT' 'Host app port mapped to container 8080, default: 8080.'
	@printf '  %-18s %s\n' 'MANAGEMENT_PORT' 'Host actuator port mapped to container 9090, default: 9090.'
	@printf '  %-18s %s\n' 'DOCKER_RUN_ARGS' 'Extra docker run args, for example env vars.'
	@printf '\n%s\n' 'Examples:'
	@printf '  %s\n' 'make docker-run APP_PORT=8081 MANAGEMENT_PORT=9091'
	@printf '  %s\n' 'make docker-run DOCKER_RUN_ARGS="-e SPRING_PROFILES_ACTIVE=prod"'

test:
	./gradlew test

start: run

run:
	./gradlew bootRun

update-gradle:
	./gradlew wrapper --gradle-version 9.2.1

update-deps:
	./gradlew refreshVersions

install:
	./gradlew dependencies

build:
	./gradlew build

lint:
	./gradlew spotlessCheck

lint-fix:
	./gradlew spotlessApply

docker-test:
	docker build --progress=plain --target test --build-arg TEST_CACHEBUST=$$(date +%s) -t $(DOCKER_IMAGE):test .

docker-build:
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

docker-run:
	docker run --rm -p $(APP_PORT):8080 -p $(MANAGEMENT_PORT):9090 $(DOCKER_RUN_ARGS) $(DOCKER_IMAGE):$(DOCKER_TAG)

.PHONY: help test start run update-gradle update-deps install build lint lint-fix docker-test docker-build docker-run
