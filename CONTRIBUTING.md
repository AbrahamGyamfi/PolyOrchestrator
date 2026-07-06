# Contributing to BusinessConnect

Thank you for contributing to BusinessConnect. This guide covers everything you need to get a working development environment, follow the project's conventions, and get a pull request merged.

---

## Table of Contents

- [Development Setup](#development-setup)
- [Working on Individual Services](#working-on-individual-services)
- [Code Style](#code-style)
- [Branch Naming](#branch-naming)
- [Commit Messages](#commit-messages)
- [Pull Request Requirements](#pull-request-requirements)
- [Adding a New Service](#adding-a-new-service)
- [Testing Requirements](#testing-requirements)
- [Database Changes](#database-changes)
- [Dependency Management](#dependency-management)

---

## Development Setup

### Prerequisites

- **Node.js** 22 or newer (`node --version`)
- **Docker** 24+ and Docker Compose v2 (`docker compose version`)
- **Git** 2.40+

### 1. Clone the repository

```bash
git clone <repo-url>
cd businessConnect
```

### 2. Start the full local stack

```bash
docker compose up --build
```

This builds all service images and starts all 8 services (postgres, redis, auth-service, business-service, review-service, inquiry-service, gateway, frontend) in the correct dependency order.

Open http://localhost:3000 when all services report healthy.

### 3. Run database migrations

Migrations run automatically via the `migrate` service the first time the stack starts. To run them manually:

```bash
docker compose run --rm migrate
```

### 4. Verify the stack is healthy

```bash
# All services should show "healthy"
docker compose ps

# Spot-check the gateway
curl http://localhost:4000/health
```

---

## Working on Individual Services

You do not need to run the full Docker stack to work on a single backend service. You can run any service directly with Node.js while the infrastructure services (postgres, redis) run in Docker.

### Run infrastructure only

```bash
docker compose up postgres redis
```

### Run a service with hot reload

```bash
cd services/auth-service
npm install
npm run dev   # tsx watch src/index.ts — restarts on every save
```

Copy the relevant environment variables from `docker-compose.yml` into your shell or a `.env` file before running. For example, for `auth-service`:

```bash
export DATABASE_URL=postgres://postgres:postgres@localhost:5434/church_platform
export REDIS_URL=redis://localhost:6380
export BETTER_AUTH_SECRET=change-me-in-production
export GATEWAY_URL=http://localhost:4000
export FRONTEND_URL=http://localhost:3000
export PORT=4001
```

> PostgreSQL is exposed on port **5434** and Redis on **6380** from Docker Compose (to avoid conflicts with local installations).

### Frontend development

The frontend uses Vite with hot module replacement. It expects a running gateway at `http://localhost:4000`.

```bash
# Start infrastructure and all backend services
docker compose up postgres redis auth-service business-service review-service inquiry-service gateway

# In a separate terminal, start the frontend dev server
cd frontend
npm install
npm run dev
```

Open http://localhost:5173 (Vite's default port).

---

## Code Style

The project uses **ESLint** and **Prettier** to enforce consistent style across all TypeScript services.

### Configuration files

- **ESLint**: `.eslintrc.json` at the project root — uses `@typescript-eslint`, `plugin:import/recommended`.
- **Prettier**: `.prettierrc` at the project root — `singleQuote: true`, `printWidth: 100`, `trailingComma: "es5"`, `tabWidth: 2`.

### Running lint and format

```bash
# Lint a service (from the service directory)
cd services/auth-service
npm run lint

# Type-check (catches TypeScript errors without building)
npm run typecheck

# Format a single file with Prettier (from any directory)
npx prettier --write services/auth-service/src/index.ts

# Format all TypeScript files in a service
npx prettier --write "services/auth-service/src/**/*.ts"
```

### Key lint rules

| Rule                                   | Setting  | Why                                                   |
|----------------------------------------|----------|-------------------------------------------------------|
| `@typescript-eslint/no-explicit-any`   | `warn`   | Prefer typed alternatives where possible              |
| `@typescript-eslint/no-unused-vars`    | `error`  | Dead variables indicate bugs or incomplete refactors  |
| `@typescript-eslint/no-floating-promises` | `error` | Unhandled promise rejections cause silent failures   |
| `import/order`                         | `error`  | Consistent import grouping: builtin → external → internal |
| `eqeqeq`                               | `error`  | No loose equality comparisons (`==`)                  |
| `no-console`                           | `warn`   | Use `pino` logger; console is allowed only for `warn`/`error` |

All services use `pino` for structured JSON logging. Do not add `console.log` calls — use `logger.info`, `logger.warn`, or `logger.error` instead.

### TypeScript configuration

Each service has its own `tsconfig.json` with `strict: true`. The compiler target is `ES2022` and module resolution is `Node16`. All exported functions must have their parameter and return types explicitly annotated when the inferred type is not obvious.

---

## Branch Naming

Branches must follow this pattern:

```
<type>/<short-description>
```

| Type       | When to use                                           |
|------------|-------------------------------------------------------|
| `feature/` | New functionality that did not previously exist       |
| `fix/`     | Bug fix for broken or incorrect behaviour             |
| `docs/`    | Documentation-only change                            |
| `refactor/`| Code restructuring with no behaviour change           |
| `test/`    | Adding or improving tests                             |
| `chore/`   | Maintenance tasks (dependency updates, tooling, CI)   |

**Examples:**

```
feature/business-analytics-dashboard
fix/session-expiry-redis-ttl
docs/eks-deployment-guide
refactor/gateway-route-registration
test/business-service-bookings-endpoint
chore/upgrade-drizzle-0.45
```

Keep descriptions short (2–4 words), hyphen-separated, lowercase. Do not include ticket numbers in the branch name — put them in the commit message or PR description.

---

## Commit Messages

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification.

### Format

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

### Types

| Type       | When to use                                           |
|------------|-------------------------------------------------------|
| `feat`     | A new feature visible to users or operators           |
| `fix`      | A bug fix                                             |
| `docs`     | Documentation changes only                           |
| `test`     | Adding or correcting tests                            |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `chore`    | Maintenance (dependencies, config, CI scripts)        |
| `perf`     | Performance improvement                               |
| `ci`       | Changes to CI/CD configuration files and scripts      |

### Scope

Use the service or directory name as the scope: `auth-service`, `gateway`, `business-service`, `frontend`, `terraform`, `k8s`, `docs`.

### Examples

```
feat(business-service): add pagination to /api/businesses endpoint

Adds limit/offset query parameters. Defaults to limit=20, offset=0.
Returns a total count alongside the results for client-side pagination.

fix(auth-service): prevent session token from expiring on every request

The updateAge was incorrectly set to the same value as expiresIn,
causing a Redis write on every authenticated request. Reduced to 24h.

docs(README): add ECS vs EKS benchmark results table

refactor(gateway): extract route registration into a separate function

chore(deps): upgrade drizzle-orm to 0.45.2

test(inquiry-service): add health check and inquiries route tests
```

### Rules

- The short description must be in the **imperative mood**, lowercase, no trailing period.
- The body (if present) explains **why**, not just what. Reference issue numbers here.
- Breaking changes must include `BREAKING CHANGE:` in the footer.
- Keep the subject line under 72 characters.

---

## Pull Request Requirements

### Before opening a PR

1. **Tests pass**: Run `npm test` in every service you modified. New features must include tests.
2. **Lint passes**: Run `npm run lint` and `npm run typecheck` in each affected service. Fix all errors before opening the PR.
3. **No secrets**: Check that no credentials, API keys, or sensitive values appear in any committed file. Review `terraform.tfvars`, `.env` files, and Kubernetes secrets.
4. **Self-review**: Read through your own diff before requesting review. Remove debug logs, commented-out code, and TODO comments that belong in issues.

### PR description

Every PR must include:

- **What**: A one-sentence summary of what changed.
- **Why**: The motivation — what problem does this solve, or what requirement does it fulfil?
- **How to test**: Step-by-step instructions for a reviewer to verify the change locally.
- **Screenshots** (if the change affects the UI).

Do not open a PR with only "fix bug" or "update code" as the description. A reviewer who doesn't know your context needs enough information to understand whether the change is correct.

### Review process

- At least one approval is required before merging.
- Address all review comments before merging (or explicitly mark them as "won't fix" with justification).
- Squash commits that are fixups or "address review comments" before the final merge if the branch has many small commits.
- PRs that break the CI (tests, lint, typecheck) will not be merged until they are green.

### Merging

Use **Squash and Merge** for feature and fix branches so the main branch has one clean commit per logical change. Use **Merge Commit** for long-running branches where individual commit history is meaningful.

---

## Adding a New Service

Follow this checklist when adding a microservice to BusinessConnect.

### 1. Create the service directory

```bash
mkdir -p services/my-service/src/__tests__
```

### 2. Bootstrap Node.js / TypeScript

Copy `package.json`, `tsconfig.json`, and `vitest.config.ts` from an existing service (for example, `review-service`) and update the `name` field and any service-specific dependencies.

```bash
cd services/my-service
npm install
```

### 3. Implement the service

Every service must include:

- `src/index.ts` — Express app with:
  - `helmet()` middleware
  - `rateLimit({ windowMs: 15 * 60 * 1000, max: 100, ... })` middleware
  - `GET /health` endpoint returning `{ status: 'ok', service: 'my-service', uptime: ..., timestamp: ... }`
  - Graceful shutdown: listen for `SIGTERM` and call `server.close()`
  - Structured JSON logging with `pino` and `pino-http`
- `src/__tests__/health.test.ts` — at minimum, a health check test

### 4. Write the Dockerfile

Copy the Dockerfile from an existing service. Ensure:

- Multi-stage build: `builder` stage compiles TypeScript; `runner` stage is a clean Alpine image
- `addgroup` and `adduser` create a non-root `appuser`
- `dumb-init` is installed and used as `ENTRYPOINT`
- `USER appuser` is set before `EXPOSE` and `CMD`
- A `HEALTHCHECK` instruction is present

### 5. Add to docker-compose.yml

```yaml
my-service:
  build:
    context: ./services/my-service
    network: host
  ports:
    - '<port>:<port>'
  environment:
    DATABASE_URL: postgres://postgres:postgres@postgres:5432/church_platform
    AUTH_SERVICE_URL: http://auth-service:4001
    PORT: '<port>'
  depends_on:
    auth-service:
      condition: service_healthy
  healthcheck:
    test: ['CMD-SHELL', 'wget -qO- http://localhost:<port>/health || exit 1']
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 15s
```

### 6. Register routes in the gateway

Open `services/gateway/src/index.ts` and add a proxy for your new service:

```typescript
const MY_SERVICE_URL = process.env.MY_SERVICE_URL ?? 'http://my-service:<port>'

app.use(createProxyMiddleware({ pathFilter: '/api/my-resource', target: MY_SERVICE_URL, changeOrigin: true }))
```

Add the corresponding environment variable to the gateway's `environment` block in `docker-compose.yml`.

### 7. Create the ECR repository

Add your service to the ECR module in `terraform/ecr.tf`:

```hcl
locals {
  service_names = [
    "auth-service", "business-service", "review-service",
    "inquiry-service", "gateway", "frontend", "migrate",
    "my-service"   # add this line
  ]
}
```

### 8. Add the ECS task definition and service

Follow the pattern in `terraform/ecs.tf`. Add:
- A task definition resource (`aws_ecs_task_definition.my_service`)
- A service resource (`aws_ecs_service.my_service`)
- A Cloud Map service entry by adding `"my-service"` to `local.discovery_services`
- An auto-scaling target and policy in `terraform/autoscaling.tf`

### 9. Create Kubernetes manifests

Create `k8s/my-service/01-deployment.yaml` and `k8s/my-service/02-service.yaml` following the patterns in the existing service directories. Add a corresponding HPA in `k8s/hpa/my-service-hpa.yaml`.

### 10. Update the gateway environment in k8s manifests

Add `MY_SERVICE_URL` to `k8s/01-configmap.yaml` and reference it in the gateway deployment manifest.

### 11. Add the build context to 01-build-push.sh

```bash
["${ROOT}/services/my-service"]="${PROJECT}/my-service"
```

### 12. Write tests

At a minimum, write health check tests. If the service has business logic, add unit tests for that logic. Run `npm test` and confirm all tests pass before opening a PR.

---

## Testing Requirements

| Scenario                   | Requirement                                             |
|----------------------------|---------------------------------------------------------|
| Bug fix                    | Add a test that would have caught the bug               |
| New endpoint               | Test the happy path and at least one error path (401, 404, 400) |
| New middleware              | Test that unauthorized requests are rejected           |
| Refactoring                | Existing tests must still pass; no regression          |
| Documentation change       | No tests required                                       |

### Test isolation

- Mock the database with `vi.mock('../db/index.js', ...)` — tests must not connect to a real database.
- Mock external service calls (for example, calls to auth-service from business-service) using `vi.mock` or `vi.spyOn`.
- Each test file should be independently runnable without any state from previous tests.

### Coverage

There is currently no enforced coverage threshold, but aim for meaningful coverage of business logic rather than hitting an arbitrary percentage number. Cover edge cases (empty results, invalid input, missing auth headers) in addition to the happy path.

---

## Database Changes

All schema changes go through Drizzle Kit. The canonical schema is in `migrate/schema.ts`.

```bash
# Push schema changes to a local database (dev only — never run against production directly)
cd migrate
npm run db:push

# Generate a migration file (for production-style versioned migrations)
npm run db:generate

# Apply generated migrations
npm run db:migrate
```

When modifying the schema:

1. Edit `migrate/schema.ts`.
2. If the service that owns the table also declares the schema locally (for example, `services/business-service/src/db/schema.ts`), keep them in sync.
3. Run `db:push` locally and verify the application still works end-to-end.
4. Include the schema change in the same PR as the code that uses it.
5. If the migration is destructive (drops a column or table), coordinate with the team before merging.

---

## Dependency Management

- Use exact versions for all runtime dependencies (no `^` or `~` prefix) to ensure reproducible builds.
- Use the `^` prefix only for `devDependencies` that are not part of the compiled output.
- Before adding a new dependency, check whether an existing dependency in the project already covers the need.
- Run `npm audit` before opening a PR. Address any high or critical severity vulnerabilities.
- Avoid dependencies with large transitive dependency trees for lightweight services.
