# Project DevOps Deploy

[![CI](https://github.com/Abdujabbar/project-devops-deploy/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Abdujabbar/project-devops-deploy/actions/workflows/ci.yml)

Project DevOps Deploy is a bulletin board application with a Spring Boot backend and a React Admin frontend. The backend exposes bulletin CRUD APIs, image upload endpoints, Swagger UI, and Actuator health/metrics endpoints. The default `dev` profile uses an in-memory H2 database and seeded sample data so the service is usable immediately after startup.

## Expected Docker Artifact

The deployment artifact for this fork is a Docker image built from the repository `Dockerfile`. Build and run it from the repository root:

```bash
make docker-build
make docker-run
```

By default this creates and runs `project-devops-deploy:local`, exposing the application at `http://localhost:8080` and Actuator endpoints at `http://localhost:9090`.

On successful pushes to `main`, CI publishes the image to GitHub Container Registry as `ghcr.io/abdujabbar/project-devops-deploy:latest` and `ghcr.io/abdujabbar/project-devops-deploy:<git-sha>`.

## VM Provisioning

The Yandex Cloud VM is described in `inventory/hosts.yml`. Provision it with Ansible from the repository root:

```bash
make ansible-ping
make ansible-provision
```

The Ansible commands use `uv` to create a local `.venv` and install the Python tools from `pyproject.toml`, so a global Ansible installation is not required. `uv sync` uses `CA_CERT_FILE`, which defaults to `~/Downloads/CA.pem`; override it if the Yandex CA bundle is stored elsewhere. If `inventory/group_vars/app/vault.yml` exists and is encrypted, pass Vault options through `ANSIBLE_ARGS`, for example `make ansible-ping ANSIBLE_ARGS='--ask-vault-pass'`.

The playbook at `playbooks/bootstrap.yml` installs Docker Engine, the Docker Compose plugin, base utilities, adds the `abdu` user to the `docker` group, and enables UFW with only SSH, HTTP/HTTPS, app port `8080`, and management port `9090` allowed. The playbook is intended to be idempotent, so repeated `make ansible-provision` runs should keep the server in the same expected state.

The deployment host is also available through DNS:

| Hostname | Record | Target |
|----------|--------|--------|
| `hexlet.chickenkiller.com` | `A` | `158.160.15.192` |

After deployment, Nginx serves the app through the domain. Port `80` is used for Let's Encrypt validation and redirects to HTTPS after the certificate is issued:

```text
https://hexlet.chickenkiller.com
```

## Deployment

Deploy the published Docker image to the VM with:

```bash
make deploy
```

This runs `playbooks/deploy.yml`, pulls `ghcr.io/abdujabbar/project-devops-deploy:latest`, renders `/opt/project-devops-deploy/compose.yml`, checks the Yandex Managed PostgreSQL endpoint, runs the schema migration step, and restarts the app through Docker Compose. Runtime data is stored under `/opt/project-devops-deploy/data`, and application log mounts are prepared under `/opt/project-devops-deploy/logs`.

The same Compose deployment starts an `nginx:1.29-alpine` reverse proxy on host ports `80` and `443`. Nginx forwards traffic to the internal `app:8080` service, caches static assets for 30 days, caches `/api/files/raw` for 10 minutes, caches `/api/files/view` for 2 minutes, and bypasses caching for uploads and non-GET requests. Cache files live under `/opt/project-devops-deploy/nginx-cache`.

Let's Encrypt certificates are issued with a Certbot container using the webroot challenge under `/opt/project-devops-deploy/certbot-www`. Certificates are stored under `/opt/project-devops-deploy/letsencrypt`, mounted read-only into Nginx, and renewed by the host systemd timer `project-devops-deploy-certbot-renew.timer`. The renewal service reloads Nginx after `certbot renew`. Set `vault_letsencrypt_email` in Vault if you want Let's Encrypt expiry notices; if it is blank, Certbot registers without email. HTTPS uses TLS 1.2/1.3 only, disables session tickets, and redirects all ordinary HTTP traffic to HTTPS after the first certificate is available.

Check HTTPS and renewal after deployment:

```bash
curl -I http://hexlet.chickenkiller.com
curl -fsS https://hexlet.chickenkiller.com/api/bulletins
ssh -i ~/.ssh/abdu abdu@158.160.15.192 'systemctl list-timers project-devops-deploy-certbot-renew.timer'
ssh -i ~/.ssh/abdu abdu@158.160.15.192 'sudo systemctl start project-devops-deploy-certbot-renew.service'
```

PostgreSQL is expected to run in Yandex Managed PostgreSQL, not as a container on the VM. Configure the MDB security group so PostgreSQL is reachable only from the deployment VM, preferably through private network access. The VM firewall still exposes only SSH, HTTP/HTTPS, `8080`, and `9090`; database port `6432` is not opened publicly on the VM. During deploy, Ansible copies the bundled Yandex Cloud CA certificate to `/opt/project-devops-deploy/root.crt` and mounts it into the app containers for verified TLS connections.

### Yandex Object Storage

Production image uploads use Yandex Object Storage through the S3-compatible API. Keep the bucket private; the backend returns short-lived presigned URLs, so public bucket read access is not required.

Create the bucket and service-account key from an authenticated YC CLI session:

```bash
BUCKET="project-devops-deploy-images"
SA_NAME="project-devops-deploy-s3"

yc storage bucket create "$BUCKET" --default-storage-class standard
yc iam service-account create --name "$SA_NAME"
SA_ID="$(yc iam service-account list --format json | jq -r ".[] | select(.name == \"$SA_NAME\") | .id")"
```

Grant the app service account bucket-level `storage.uploader` access in the Yandex Cloud console: Object Storage → bucket → Security → Access bindings → Assign roles → service account `$SA_NAME` → `storage.uploader`. This gives the application object read/upload permissions without delete or bucket configuration rights. See the official docs for [bucket creation](https://yandex.cloud/en/docs/storage/operations/buckets/create), [bucket IAM bindings](https://yandex.cloud/en/docs/storage/operations/buckets/iam-access), and [Object Storage roles](https://yandex.cloud/en/docs/storage/security/).

Generate the static S3 key and save the output immediately; YC shows the secret only once:

```bash
yc iam access-key create \
  --service-account-name "$SA_NAME" \
  --description "project-devops-deploy object storage"
```

Store the resulting `key_id` and `secret` in Ansible Vault:

```yaml
vault_spring_profiles: "prod"
vault_letsencrypt_email: "admin@example.com"
vault_s3_bucket: "project-devops-deploy-images"
vault_s3_region: "ru-central1"
vault_s3_endpoint: "https://storage.yandexcloud.net"
vault_s3_access_key: "<key_id>"
vault_s3_secret_key: "<secret>"
vault_s3_cdn_url: ""
```

If you later move deploys into GitHub Actions, store the same values as repository secrets with `gh secret set`, but do not commit them to the repository.

Before the first PostgreSQL-backed deploy, create the encrypted Vault file and set the Managed PostgreSQL connection values:

```bash
make venv
cp inventory/group_vars/app/vault.yml.example inventory/group_vars/app/vault.yml
# Fill vault_postgres_host, vault_postgres_username, vault_postgres_password.
# Fill vault_s3_* values when using the prod profile.
.venv/bin/ansible-vault encrypt inventory/group_vars/app/vault.yml
```

Then deploy with Vault enabled:

```bash
make deploy ANSIBLE_ARGS='--ask-vault-pass'
```

Deploy a specific immutable build by passing the Git SHA tag published by CI:

```bash
make deploy IMAGE_TAG=<git-sha>
```

Rollback uses the same predictable tag strategy:

```bash
make rollback IMAGE_TAG=<previous-git-sha>
```

Do not put secrets in plain repository files. To edit encrypted registry/database/S3 values later, use:

```bash
make venv
.venv/bin/ansible-vault edit inventory/group_vars/app/vault.yml
```

Run deploys that need Vault values with `ANSIBLE_ARGS='--ask-vault-pass'` or `ANSIBLE_ARGS='--vault-password-file .vault-password'`. The `.vault-password` file and real `vault.yml` are ignored by git.

At minimum, deployment requires PostgreSQL values (`vault_postgres_host`, `vault_postgres_username`, `vault_postgres_password`) in the encrypted Vault file. The application container receives the generated datasource and S3 variables through `/opt/project-devops-deploy/app.env`. By default Ansible runs the app with `SPRING_PROFILES_ACTIVE=dev`, while still overriding the datasource to Yandex Managed PostgreSQL. Set `vault_spring_profiles: "prod"` when Object Storage is configured. The deploy playbook validates object storage credentials by writing and reading `bulletins/.deploy-check` before starting the app. The JDBC URL uses port `6432`, `sslmode=verify-full`, `sslrootcert=/app/root.crt`, and `targetServerType=master`, which matches Yandex MDB PostgreSQL access for Java.

If deploy fails at the database readiness check with `password authentication failed`, the VM is already reaching Yandex Managed PostgreSQL. Check the encrypted Vault values against the MDB cluster: `vault_postgres_username`, `vault_postgres_password`, and `vault_postgres_database` must match an existing PostgreSQL user/database, and the user must have access to that database. Reset the MDB user password or update Vault with `.venv/bin/ansible-vault edit inventory/group_vars/app/vault.yml`, then rerun deploy with `ANSIBLE_ARGS='--ask-vault-pass'`.

> **Fork policy**: this upstream repository is read-only. We do not review or merge pull requests and we do not accept infrastructure changes (Dockerfiles, Ansible roles, CI/CD workflows, etc.). To experiment or extend the project, fork it and work inside your own repository.

API documentation is available via Swagger UI at `http://localhost:8080/swagger-ui/index.html`.

## Project layout

- Backend (Spring Boot) lives in the repository root.
- Frontend (React Admin + Vite) is located in `frontend/`.
- Shared static assets for the backend are served from `src/main/resources/static` (populated by the frontend build when needed).

Keep this structure in mind when running commands—backend tooling (`gradlew`, `make run`, tests) run from the root, frontend tooling (`npm`, `vite`) runs from `frontend/`.

## Environment variables

Key variables are read directly by Spring Boot (see `src/main/resources/application.yml` and `application-prod.yml` for defaults):

| Variable                     | Description                                                   | Default                                      |
|------------------------------|---------------------------------------------------------------|----------------------------------------------|
| `SPRING_PROFILES_ACTIVE`     | Active Spring profile (`dev`, `prod`, etc.)                   | `dev`                                        |
| `SPRING_DATASOURCE_URL`      | JDBC URL for PostgreSQL in `prod`                             | `jdbc:postgresql://localhost:5432/bulletins` |
| `SPRING_DATASOURCE_USERNAME` | DB username                                                   | `postgres`                                   |
| `SPRING_DATASOURCE_PASSWORD` | DB password                                                   | `postgres`                                   |
| `STORAGE_S3_BUCKET`          | Bucket name for bulletin images                               | empty                                        |
| `STORAGE_S3_REGION`          | Region for the S3-compatible storage                          | empty                                        |
| `STORAGE_S3_ENDPOINT`        | S3-compatible endpoint for YC Object Storage                  | `https://storage.yandexcloud.net`           |
| `STORAGE_S3_ACCESSKEY`       | Access key ID                                                 | empty                                        |
| `STORAGE_S3_SECRETKEY`       | Secret key                                                    | empty                                        |
| `STORAGE_S3_CDNURL`          | Optional public CDN prefix                                    | empty                                        |
| `MANAGEMENT_SERVER_PORT`     | Port for Spring Actuator endpoints (health, metrics, etc.)    | `9090`                                       |
| `JAVA_OPTS`                  | Extra JVM parameters (heap, `-Dspring.profiles.active`, etc.) | empty                                        |

All other variables supported by Spring Boot can be overridden the same way; check the application configuration files if you need to confirm a property name.

## Requirements

- JDK 21+.
- Gradle 9.2.1.
- PostgreSQL only if you run the `prod` profile with an external database.
- Make.
- uv for VM provisioning tools.
- NodeJS 20+

## Running

### Backend (local dev profile)

1. Install prerequisites from the **Requirements** section.
2. From the repository root start the backend:

    ```bash
    make run
    ```

3. Explore the API:
   - `GET http://localhost:8080/api/bulletins`
   - `GET http://localhost:8080/api/bulletins?page=1&perPage=9&sort=createdAt&order=DESC&state=PUBLISHED&search=laptop`
   - Swagger UI: `http://localhost:8080/swagger-ui/index.html`

`/api/bulletins` accepts pagination (`page`, `perPage`), sorting (`sort`, `order`) and filters (`state`, `search`). Filters are processed via JPA Specifications so the same contract is available to the React Admin frontend.

### Frontend (development build)

1. Open a second terminal and move into the frontend directory:

    ```bash
    cd frontend
    make install   # npm install
    make start     # Vite dev server on http://localhost:5173
    ```

2. The dev server proxies `/api` requests to `http://localhost:8080`, so keep the backend running.

### Production profile on a single host

1. Export the environment variables from the table above (DB access, S3 storage, `JAVA_OPTS`, etc.). The defaults in `application-prod.yml` show the exact property names if you need to double-check.
2. Build and launch the backend:

    ```bash
    make build
    java -jar build/libs/project-devops-deploy-0.0.1-SNAPSHOT.jar
    ```

3. Serve the frontend either from the same JVM (see **Build and serve from the Java app**) or deploy it separately (any static hosting/CDN works once `frontend/dist` is uploaded).

`JAVA_OPTS` can be used to control heap size, GC, or add any `-D` system properties without editing the manifest.

### Useful commands

See [Makefile](./Makefile)

## Frontend

### Development

1. Install Node.js 24 LTS (or newer) and npm.
2. Install dependencies and start the Vite dev server:

    ```bash
    cd frontend
    make install
    make start
    ```

3. The dev server proxies `/api` requests to `http://localhost:8080`, so keep the backend running via `make run` (or `./gradlew bootRun`) in another terminal.

### Image upload flow

1. Upload files via `POST /api/files/upload` (multipart form field named `file`).
2. The response contains `key` and a temporary `url`. Persist the `key` in the `imageKey` field when creating or updating bulletins; the backend stores only that identifier.
3. When you need a fresh link, call `GET /api/files/view?key=...` to receive a new URL (the backend issues presigned links on demand).

### Build and serve from the Java app

1. Build the production bundle:

    ```bash
    cd frontend
    make install      # run once
    make build    # outputs to frontend/dist
    ```

2. Copy the compiled assets into Spring Boot’s static resources (served from `src/main/resources/static`):

    ```bash
    rm -rf src/main/resources/static
    mkdir -p src/main/resources/static
    cp -R frontend/dist/* src/main/resources/static/
    ```

3. Restart the backend (`make run`) and open `http://localhost:8080/` — the React app will now be served directly by the Java application.

### Running in Docker

Pass JVM flags via `JAVA_OPTS`:

```bash
docker run --rm -p 8080:8080 \
  -e JAVA_OPTS="-Xms256m -Xmx512m -Dspring.profiles.active=prod" \
  ...
```

Useful JVM options:

- `-Xms/-Xmx` — set memory limits inside the container.
- `-XX:+UseContainerSupport` / `-XX:ActiveProcessorCount` (these respect cgroup limits by default).
- `-Dspring.profiles.active=prod` — switch the profile without recompiling.
- `-Dlogging.level.root=INFO` or Spring environment variables (`SPRING_DATASOURCE_URL`, `STORAGE_S3_BUCKET`, etc.) — configure external services.

## Monitoring / management ports

- Application traffic still uses port `8080` by default. Actuator endpoints (health, metrics, Prometheus scrape, logfile) listen on `MANAGEMENT_SERVER_PORT` (defaults to `9090` for every profile). Override it via env vars when you need a different port.
- If your deployment does **not** include Prometheus/Grafana yet, you can ignore the management port entirely; the application starts normally even if nothing scrapes `/actuator`. Simply avoid publishing the management port in Docker/Kubernetes until you need it.
- When monitoring is enabled, expose both ports, e.g. `docker run -p 8080:8080 -p 9090:9090 ...` and point Prometheus to `http://<host>:9090/actuator/prometheus`.
- Health probes are available at `/actuator/health/liveness` and `/actuator/health/readiness`; Grafana/Loki integrations should use the same port/env variable.

## Actuator endpoints (local check)

With the app running locally (`make run`), the management port defaults to `http://localhost:9090`. Useful URLs:

- `http://localhost:9090/actuator` — index of exposed endpoints.
- `http://localhost:9090/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` — readiness/liveness probes.
- `http://localhost:9090/actuator/metrics` and `http://localhost:9090/actuator/metrics/http.server.requests` — raw Micrometer metrics.
- `http://localhost:9090/actuator/prometheus` — Prometheus scrape output (open in browser or `curl` to confirm it renders).
- `http://localhost:9090/actuator/logfile` — current application log (same JSON that goes to stdout).

Override the host/port with `MANAGEMENT_SERVER_PORT` if you changed it; no Prometheus or Grafana instance is needed just to inspect these endpoints.

## Logging

- The backend ships with `src/main/resources/logback-spring.xml`, which writes structured JSON events to `stdout`. Every record contains `timestamp`, `app`, `environment`, `instance`, `logger`, `thread`, message arguments, MDC, and stack traces so Promtail/Loki (or any log shipper) can parse them without extra processing.
- No extra variables are required, but you can supply a different configuration via Spring Boot’s standard options (`LOGGING_CONFIG`, `logging.config`, or by overriding `logback-spring.xml` on the classpath).
- Container runtimes should forward `stdout`/`stderr` to your logging pipeline. Avoid redirecting logs to files unless your platform explicitly demands it.

## Image Upload Checks

### Local (dev profile, H2 + temp storage)

1. Start backend: `make run` (uses in-memory H2 and local filesystem storage under `/tmp/bulletin-images`).
2. Start frontend dev server: `cd frontend && npm install && npm run dev`.
3. In React Admin:
    - Create a bulletin or edit an existing one.
    - Use the “Upload image” field; after save, the image preview should load via the generated `imageUrl`.
4. Verify backend log: look for `Stored image` entries or check `/tmp/bulletin-images` for a new file. Refresh the bulletin show page to ensure the presigned/local URL still renders.

### Production / S3

1. Ensure Vault contains `vault_spring_profiles: "prod"` and the `vault_s3_*` values from the Object Storage section.
2. Deploy backend: `make deploy ANSIBLE_ARGS='--ask-vault-pass'`.
3. Upload a small file through the deployed API:

    ```bash
    printf 's3 smoke test\n' >/tmp/s3-smoke.txt
    curl -sS -F file=@/tmp/s3-smoke.txt https://hexlet.chickenkiller.com/api/files/upload | tee /tmp/s3-upload.json
    KEY="$(jq -r .key /tmp/s3-upload.json)"
    URL="$(jq -r .url /tmp/s3-upload.json)"
    ```

4. Confirm the presigned URL works:

    ```bash
    curl -fsSL "$URL"
    curl -sS "https://hexlet.chickenkiller.com/api/files/view?key=$KEY" | jq .
    ```

5. Confirm the object exists in YC Object Storage:

    ```bash
    AWS_ACCESS_KEY_ID="<key_id>" \
    AWS_SECRET_ACCESS_KEY="<secret>" \
    aws --endpoint-url=https://storage.yandexcloud.net \
      s3api head-object \
      --bucket project-devops-deploy-images \
      --key "$KEY" \
      --region ru-central1
    ```
