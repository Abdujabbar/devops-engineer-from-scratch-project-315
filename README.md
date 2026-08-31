# Project 315 Infrastructure

This repository contains only the Ansible infrastructure layer for deploying
the Docker image built by the application fork:

```text
https://github.com/Abdujabbar/project-devops-deploy
```

Application source code, frontend code, Gradle files, Dockerfile, and Docker
image publishing workflows belong to that fork. This repository keeps only
inventory, playbooks, roles, templates, and local Ansible tooling.

## Structure

```text
ansible.cfg
inventory/
playbook.yml
playbooks/
requirements.yml
roles/app_deploy/
```

`playbooks/bootstrap.yml` provisions the VM. `playbooks/deploy.yml` deploys an
immutable Docker image tag. `playbooks/rollback.yml` rolls the app back to the
recorded stable image tag.

## Requirements

- `uv`
- SSH access to the VM from `inventory/hosts.yml`
- An immutable image tag published by the application repository CI
- Vault values for PostgreSQL, registry credentials when needed, and S3 when
  the `prod` profile is enabled

Install Python tooling and Ansible Galaxy collections:

```bash
make collections
```

If your workstation needs a custom CA bundle, pass it explicitly:

```bash
make collections CA_CERT_FILE=/path/to/ca-bundle.pem
```

The Galaxy dependencies are declared in `requirements.yml`. Docker Compose
operations use `community.docker`; UFW uses `community.general`.

## Provision

```bash
make ansible-ping
make ansible-provision
```

Provisioning installs Docker Engine and the Compose plugin, grants the app user
access to Docker, and configures UFW to expose only SSH, HTTP, and HTTPS.

## Deploy

Deploy a CI-published immutable image tag:

```bash
make deploy IMAGE_TAG=<git-sha>
```

The deploy playbook renders `/opt/project-devops-deploy/compose.yml`, pulls the
selected application image plus Nginx/Certbot support images, checks external
PostgreSQL/S3 dependencies, runs the migration container, starts the app and
Nginx through Docker Compose, and waits for health checks.

After a successful health check, Ansible writes the deployed tag to:

```text
/opt/project-devops-deploy/stable-image-tag
```

Mutable tags such as `latest` are rejected by default so rollback stays
deterministic. For manual testing only, pass:

```bash
make deploy IMAGE_TAG=latest ANSIBLE_ARGS='-e allow_mutable_image_tag=true'
```

## Rollback

Roll back to the last recorded stable image:

```bash
make rollback
```

Or roll back to a specific immutable tag:

```bash
make rollback IMAGE_TAG=<previous-git-sha>
```

During a normal deploy, if migration, container startup, or health checks fail,
the deploy playbook automatically attempts to render the previous stable image
tag, pull it, start it, verify health, and persist it again as the current
stable tag.

Rollback is application-image rollback only. Database migrations are expected
to be forward-compatible.

## Secrets

Do not commit secrets. Create the encrypted Vault file from the example:

```bash
cp inventory/group_vars/app/vault.yml.example inventory/group_vars/app/vault.yml
.venv/bin/ansible-vault encrypt inventory/group_vars/app/vault.yml
```

Run playbooks that need Vault values with:

```bash
make deploy IMAGE_TAG=<git-sha> ANSIBLE_ARGS='--ask-vault-pass'
```
