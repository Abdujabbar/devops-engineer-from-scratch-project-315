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

- `playbook.yml`: root entrypoint that imports `playbooks/bootstrap.yml`.
- `playbooks/bootstrap.yml`: provisions the VM for Docker-based deployments.
- `playbooks/deploy.yml`: deploys a selected immutable application image tag.
- `playbooks/rollback.yml`: rolls the application back to the recorded stable
  image tag.
- `roles/app_deploy/`: renders Compose/Nginx/Systemd configs, validates inputs,
  runs preflight checks, runs migration, starts services, configures TLS, and
  reports status.

The Hexlet workflow in `.github/workflows/hexlet-check.yml` is intentionally
kept here because this is the project repository checked by Hexlet. Runtime
directories such as `.ansible/` and `.venv/` are ignored by both `.gitignore`
and `.dockerignore` so they are not committed and do not break the checker
Docker build context.

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

The same `CA_CERT_FILE` is passed to both `uv` and `ansible-galaxy`. The Galaxy
dependencies are declared in `requirements.yml`. Docker Compose operations use
`community.docker`; UFW uses `community.general`.

If your local `~/.netrc` has permissive permissions and `ansible-galaxy` refuses
to run, either restrict that file to owner-only permissions or run the local
check with:

```bash
NETRC=/dev/null make syntax-check
```

## Provision

```bash
make ansible-ping
make ansible-provision
```

Provisioning installs Docker Engine and the Compose plugin, grants the app user
access to Docker, and configures UFW to expose only SSH, HTTP, and HTTPS.

The application and Actuator ports are not exposed publicly. In the rendered
Compose file they are bound to localhost on the VM:

```text
127.0.0.1:8080:8080
127.0.0.1:9090:9090
```

Public traffic goes through the Nginx container on ports `80` and `443`.

The current inventory points to the Yandex Cloud VM as user `abdu`:

```text
yc-vm ansible_host=158.160.15.192
```

The default Nginx server name is `hexlet.chickenkiller.com`.

## Deploy

Deploy a CI-published immutable image tag:

```bash
make deploy IMAGE_TAG=<git-sha>
```

The deploy playbook:

1. Validates required image/database/storage inputs.
2. Renders `/opt/project-devops-deploy/compose.yml`, `app.env`, Nginx config,
   and Certbot renewal systemd units.
3. Pulls the selected application image plus Nginx/Certbot support images.
4. Checks Yandex Managed PostgreSQL readiness.
5. Checks Yandex Object Storage write/read access when the `prod` profile is
   enabled.
6. Runs the migration container.
7. Starts the app and Nginx through Docker Compose.
8. Waits for the app readiness endpoint and Nginx proxy endpoint.
9. Issues a Let's Encrypt certificate when one is missing and enables renewal.

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

The first successful immutable deploy creates the stable tag file. Before that,
manual rollback is not possible unless you pass `IMAGE_TAG=<previous-git-sha>`.

## Secrets

Do not commit secrets. Create the encrypted Vault file from the example:

```bash
make venv
cp inventory/group_vars/app/vault.yml.example inventory/group_vars/app/vault.yml
.venv/bin/ansible-vault encrypt inventory/group_vars/app/vault.yml
```

At minimum, set these Vault values before deploy:

```yaml
vault_postgres_host: "<managed-postgres-host>"
vault_postgres_username: "<postgres-user>"
vault_postgres_password: "<postgres-password>"
vault_postgres_database: "bulletins"
vault_spring_profiles: "prod"
vault_s3_bucket: "project-devops-deploy-images"
vault_s3_region: "ru-central1"
vault_s3_endpoint: "https://storage.yandexcloud.net"
vault_s3_access_key: "<key-id>"
vault_s3_secret_key: "<secret>"
vault_letsencrypt_email: "admin@example.com"
```

Registry credentials are optional for public images. If the GHCR image is
private, set:

```yaml
vault_registry_username: "<github-user>"
vault_registry_password: "<github-token>"
```

Run playbooks that need Vault values with:

```bash
make deploy IMAGE_TAG=<git-sha> ANSIBLE_ARGS='--ask-vault-pass'
```

To edit encrypted values later:

```bash
.venv/bin/ansible-vault edit inventory/group_vars/app/vault.yml
```

## Validation

Run syntax checks before pushing infrastructure changes:

```bash
make syntax-check
```

If your workstation does not trust the Galaxy certificate chain, use the
explicit local override:

```bash
NETRC=/dev/null make syntax-check ANSIBLE_GALAXY_ARGS=--ignore-certs
```
