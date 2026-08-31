# Repository Guidelines

## Project Structure

This repository contains only the Ansible infrastructure layer for deploying
`ghcr.io/abdujabbar/project-devops-deploy`.

- `inventory/`: hosts, group vars, and Vault example files.
- `playbooks/`: entrypoint playbooks for provisioning, deploy, and rollback.
- `roles/app_deploy/`: deployment tasks, templates, and files.
- `requirements.yml`: Ansible Galaxy collection dependencies.

## Commands

- `make venv`: create the local Python environment with `uv`.
- `make collections`: install Ansible Galaxy collections.
- `make ansible-ping`: check SSH/Ansible connectivity.
- `make syntax-check`: validate playbook syntax.
- `make ansible-provision`: install Docker, configure user permissions, and UFW.
- `make deploy IMAGE_TAG=<git-sha>`: deploy an immutable application image.
- `make rollback`: roll back to the recorded stable image tag.

## Style

Use YAML with two-space indentation. Prefer fully qualified collection names
such as `community.docker.docker_compose_v2` and `community.general.ufw`.
Keep tasks idempotent and reserve `ansible.builtin.command` for checks or
shell operations that do not have a practical module equivalent.

## Security

Do not commit secrets. Keep real Vault values in
`inventory/group_vars/app/vault.yml`; only `vault.yml.example` belongs in git.
Use immutable Docker image tags for production deploys so rollback is
deterministic.
