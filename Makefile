DOCKER_IMAGE ?= project-devops-deploy
DOCKER_TAG ?= local
APP_PORT ?= 8080
MANAGEMENT_PORT ?= 9090
DOCKER_RUN_ARGS ?=
UV ?= uv
VENV_DIR ?= .venv
ANSIBLE ?= $(VENV_DIR)/bin/ansible
ANSIBLE_PLAYBOOK_CMD ?= $(VENV_DIR)/bin/ansible-playbook
ANSIBLE_INVENTORY ?= inventory/hosts.yml
ANSIBLE_PLAYBOOK ?= playbooks/bootstrap.yml
DEPLOY_PLAYBOOK ?= playbooks/deploy.yml
IMAGE_TAG ?= latest
ANSIBLE_ARGS ?=
UV_LOCK := $(wildcard uv.lock)

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
	@printf '  %-18s %s\n' 'make venv' 'Create .venv and sync Python tools with uv.'
	@printf '  %-18s %s\n' 'make ansible-ping' 'Check SSH/Ansible connectivity to the VM.'
	@printf '  %-18s %s\n' 'make ansible-check' 'Dry-run the VM provisioning playbook.'
	@printf '  %-18s %s\n' 'make ansible-provision' 'Provision Docker, user permissions, and firewall on the VM.'
	@printf '  %-18s %s\n' 'make deploy' 'Pull and run the Docker image on the VM.'
	@printf '  %-18s %s\n' 'make rollback' 'Deploy a previous image tag; requires IMAGE_TAG=<tag>.'
	@printf '\n%s\n' 'Docker variables:'
	@printf '  %-18s %s\n' 'DOCKER_IMAGE' 'Image name, default: project-devops-deploy.'
	@printf '  %-18s %s\n' 'DOCKER_TAG' 'Image tag, default: local.'
	@printf '  %-18s %s\n' 'APP_PORT' 'Host app port mapped to container 8080, default: 8080.'
	@printf '  %-18s %s\n' 'MANAGEMENT_PORT' 'Host actuator port mapped to container 9090, default: 9090.'
	@printf '  %-18s %s\n' 'DOCKER_RUN_ARGS' 'Extra docker run args, for example env vars.'
	@printf '\n%s\n' 'Examples:'
	@printf '  %s\n' 'make docker-run APP_PORT=8081 MANAGEMENT_PORT=9091'
	@printf '  %s\n' 'make docker-run DOCKER_RUN_ARGS="-e SPRING_PROFILES_ACTIVE=prod"'
	@printf '  %s\n' 'make deploy IMAGE_TAG=latest'
	@printf '  %s\n' 'make rollback IMAGE_TAG=<previous-git-sha>'

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

$(VENV_DIR)/.requirements-installed: pyproject.toml $(UV_LOCK)
	$(UV) sync
	touch $(VENV_DIR)/.requirements-installed

venv: $(VENV_DIR)/.requirements-installed

ansible-ping: venv
	$(ANSIBLE) app -i $(ANSIBLE_INVENTORY) -m ping

ansible-check: venv
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_PLAYBOOK) --check --diff

ansible-provision: venv
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_PLAYBOOK)

deploy: venv
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(DEPLOY_PLAYBOOK) -e image_tag=$(IMAGE_TAG)

rollback: venv
	@test "$(IMAGE_TAG)" != "latest" || (printf '%s\n' 'Set IMAGE_TAG to a previous immutable tag, for example: make rollback IMAGE_TAG=<previous-git-sha>' && exit 1)
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(DEPLOY_PLAYBOOK) -e image_tag=$(IMAGE_TAG)

.PHONY: help test start run update-gradle update-deps install build lint lint-fix docker-test docker-build docker-run venv ansible-ping ansible-check ansible-provision deploy rollback
