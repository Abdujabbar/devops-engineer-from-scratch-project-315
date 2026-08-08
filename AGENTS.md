# Repository Guidelines

## Project Structure & Module Organization

This repository contains a Spring Boot backend at the root and a React Admin frontend in `frontend/`. Backend sources live in `src/main/java/io/hexlet/project_devops_deploy`, grouped by role: `controller`, `service`, `repository`, `model`, `dto`, `mapper`, `storage`, and `config`. Backend tests live in `src/test/java`. Runtime configuration is in `src/main/resources`, including `application.yml`, `application-prod.yml`, logging config, and `sample_images/`. Frontend code is in `frontend/src`; Vite public assets are in `frontend/public`.

## Build, Test, and Development Commands

Run backend commands from the repository root:

- `make run` or `./gradlew bootRun`: start the backend with the `dev` profile.
- `make test` or `./gradlew test`: run the JUnit test suite.
- `make build` or `./gradlew build`: compile, test, and package the app.
- `make lint` / `make lint-fix`: run or apply Spotless Java formatting.

Run frontend commands from `frontend/`:

- `make install`: install dependencies with `npm ci`.
- `make start`: start Vite at `http://localhost:5173`.
- `make build`: create the production bundle in `frontend/dist`.
- `make lint` / `make lint-fix`: run or fix ESLint issues.

## Coding Style & Naming Conventions

Java uses 4-space indentation enforced by Spotless with Eclipse formatting and import ordering. Keep packages under `io.hexlet.project_devops_deploy`; use PascalCase for classes, camelCase for methods and fields, and suffix Spring components consistently, for example `BulletinController`, `BulletinService`, and `BulletinRepository`. TypeScript/React code should follow ESLint and Prettier; use `.tsx` for React components and keep API helpers in focused modules such as `dataProvider.ts`.

## Testing Guidelines

Backend tests use JUnit 5 with Spring Boot and MockMvc. Name test classes after the unit or API surface under test, such as `BulletinControllerTest`, and follow the existing `testCreate` and `testUploadAndView` method pattern. Add or update tests when changing controller behavior, persistence rules, validation, file uploads, or storage selection. Run `make test` before opening a pull request.

## Commit & Pull Request Guidelines

Recent history uses short conventional-style prefixes such as `fix:`, `chore:`, and `ci:`. Prefer concise imperative subjects, for example `fix: handle missing bulletin image`. Pull requests should include a summary, commands run, linked issues when relevant, and screenshots or recordings for frontend changes. Call out configuration changes, new environment variables, or deployment impacts.

## Security & Configuration Tips

Do not commit secrets. Configure production database and S3-compatible storage through environment variables documented in `README.md` and `src/main/resources/application-prod.yml`. The `dev` profile uses H2 and local image storage; production-like behavior requires `SPRING_PROFILES_ACTIVE=prod` and external service settings.
