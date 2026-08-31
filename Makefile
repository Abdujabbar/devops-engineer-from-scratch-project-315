UV ?= uv
VENV_DIR ?= .venv
UV_PYTHON ?= python3.12
CA_CERT_FILE ?=
CA_CERT_ENV = $(if $(CA_CERT_FILE),SSL_CERT_FILE=$(CA_CERT_FILE) REQUESTS_CA_BUNDLE=$(CA_CERT_FILE),)
ANSIBLE ?= $(VENV_DIR)/bin/ansible
ANSIBLE_PLAYBOOK_CMD ?= $(VENV_DIR)/bin/ansible-playbook
ANSIBLE_GALAXY ?= $(VENV_DIR)/bin/ansible-galaxy
ANSIBLE_INVENTORY ?= inventory/hosts.yml
ANSIBLE_PLAYBOOK ?= playbooks/bootstrap.yml
DEPLOY_PLAYBOOK ?= playbooks/deploy.yml
ROLLBACK_PLAYBOOK ?= playbooks/rollback.yml
COLLECTIONS_PATH ?= .ansible/collections
ANSIBLE_GALAXY_ARGS ?=
IMAGE_TAG ?=
ANSIBLE_ARGS ?=

help:
	@printf '%s\n' 'Available commands:'
	@printf '  %-18s %s\n' 'make help' 'Show this help message.'
	@printf '  %-18s %s\n' 'make venv' 'Create .venv and sync Python tools with uv.'
	@printf '  %-18s %s\n' 'make collections' 'Install Ansible Galaxy collections.'
	@printf '  %-18s %s\n' 'make ansible-ping' 'Check SSH/Ansible connectivity to the VM.'
	@printf '  %-18s %s\n' 'make syntax-check' 'Validate Ansible playbook syntax.'
	@printf '  %-18s %s\n' 'make ansible-check' 'Dry-run the VM provisioning playbook.'
	@printf '  %-18s %s\n' 'make ansible-provision' 'Provision Docker, user permissions, and firewall on the VM.'
	@printf '  %-18s %s\n' 'make deploy' 'Deploy an immutable Docker image tag; requires IMAGE_TAG=<git-sha>.'
	@printf '  %-18s %s\n' 'make rollback' 'Roll back to the recorded stable image tag, or IMAGE_TAG=<git-sha>.'
	@printf '\n%s\n' 'Examples:'
	@printf '  %s\n' 'make deploy IMAGE_TAG=<git-sha>'
	@printf '  %s\n' 'make rollback'
	@printf '  %s\n' 'make rollback IMAGE_TAG=<previous-git-sha>'

venv:
	$(CA_CERT_ENV) $(UV) sync --python $(UV_PYTHON)

collections: venv
	$(CA_CERT_ENV) $(ANSIBLE_GALAXY) collection install -r requirements.yml -p $(COLLECTIONS_PATH) $(ANSIBLE_GALAXY_ARGS)

ansible-ping: collections
	$(ANSIBLE) $(ANSIBLE_ARGS) app -i $(ANSIBLE_INVENTORY) -m ping

syntax-check: collections
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_PLAYBOOK) --syntax-check
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(DEPLOY_PLAYBOOK) --syntax-check
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(ROLLBACK_PLAYBOOK) --syntax-check

ansible-check: collections
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_PLAYBOOK) --check --diff

ansible-provision: collections
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(ANSIBLE_PLAYBOOK)

deploy: collections
	@test -n "$(IMAGE_TAG)" || (printf '%s\n' 'Set IMAGE_TAG to an immutable CI tag, for example: make deploy IMAGE_TAG=<git-sha>' && exit 1)
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(DEPLOY_PLAYBOOK) -e image_tag=$(IMAGE_TAG)

rollback: collections
	$(ANSIBLE_PLAYBOOK_CMD) $(ANSIBLE_ARGS) -i $(ANSIBLE_INVENTORY) $(ROLLBACK_PLAYBOOK) $(if $(IMAGE_TAG),-e rollback_image_tag=$(IMAGE_TAG),)

.PHONY: help venv collections ansible-ping syntax-check ansible-check ansible-provision deploy rollback
