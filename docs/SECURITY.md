# Security Guide

This document describes the security model for BusinessConnect — how authentication and sessions work, how the network is secured, how secrets are managed, and what to do if credentials are compromised.

---

## Table of Contents

- [Authentication Flow](#authentication-flow)
- [Session Management](#session-management)
- [Docker Security](#docker-security)
- [Network Security](#network-security)
- [Secrets Management](#secrets-management)
- [Rate Limiting](#rate-limiting)
- [Helmet.js HTTP Security Headers](#helmetjs-http-security-headers)
- [Incident Response: Compromised Credentials](#incident-response-compromised-credentials)
- [Dependency Security](#dependency-security)
- [Known Limitations and Recommended Improvements](#known-limitations-and-recommended-improvements)

---

## Authentication Flow

BusinessConnect uses [better-auth](https://www.better-auth.com/) for authentication. The auth-service owns all authentication logic — no other service implements token signing or session creation.

### Signup and login

```
Browser → Gateway (:4000) → Auth Service (:4001)
                                    │
                              better-auth handler
                                    │
                         ┌──────────┴──────────┐
                         │                     │
                    PostgreSQL              Redis
                  (user, session,         (session
                  account tables)          cache)
```

1. The browser sends `POST /api/auth/sign-in/email` (or `/sign-up/email`) to the gateway.
2. The gateway proxies the request to `auth-service` at `/api/auth/*`.
3. better-auth verifies credentials, creates a session record in PostgreSQL, and writes the session to Redis as a secondary fast lookup.
4. better-auth sets a `Set-Cookie` header with an opaque session token (`HttpOnly`, `SameSite=Lax`). The cookie is returned to the browser via the gateway response.
5. The browser stores the cookie automatically. No JWT or token is ever exposed to JavaScript.

### Session validation on protected routes

Each backend service (business-service, review-service, inquiry-service) performs session validation inline using the `requireAuth` middleware:

```typescript
// services/business-service/src/middleware/requireAuth.ts
export async function requireAuth(req, res, next) {
  const response = await fetch(`${AUTH_SERVICE_URL}/api/auth/get-session`, {
    headers: { cookie: req.headers.cookie ?? '' },
  })
  const session = await response.json()
  if (!session?.user?.id) {
    return res.status(401).json({ message: 'Unauthorized' })
  }
  req.userId = session.user.id
  next()
}
```

The session cookie is forwarded from the original browser request. The auth-service looks up the session in Redis (fast path) or PostgreSQL (fallback) and returns the user object. If the session is not found or has expired, the request is rejected with 401.

This design means:
- Each protected request makes one internal HTTP call to auth-service.
- No service other than auth-service has access to session secrets or the ability to forge sessions.
- Session revocation is immediate — deleting the session from Redis and PostgreSQL makes it invalid on the next request.

### Session configuration

```typescript
session: {
  expiresIn: 60 * 60 * 24 * 7,   // 7 days absolute expiry
  updateAge: 60 * 60 * 24,        // refresh TTL after 24 hours of activity
}
```

Sessions expire 7 days after creation. The expiry is extended by one day on each request where the last refresh was more than 24 hours ago, up to the absolute 7-day limit.

---

## Session Management

### Redis as secondary storage

Redis stores session data for fast lookup. The integration uses better-auth's `secondaryStorage` API:

- `get(key)` — Redis `GET`
- `set(key, value, ttl?)` — Redis `SET` with optional `EX` (seconds)
- `delete(key)` — Redis `DEL`

If `REDIS_URL` is not set (for example in local development without Redis), better-auth falls back to PostgreSQL-only session lookups. In production, Redis should always be present.

### Forcing session invalidation

To invalidate all sessions for a specific user (for example, after a credential compromise):

```sql
-- Connect to PostgreSQL
DELETE FROM session WHERE "userId" = '<user-id>';
```

To invalidate all sessions for all users:

```sql
DELETE FROM session;
```

After deleting from PostgreSQL, Redis keys will become orphaned but will expire naturally via their TTL. To force immediate expiry, flush the Redis instance:

```bash
# WARNING: this clears all Redis data, including sessions for all users
redis-cli FLUSHALL
```

In production, prefer `FLUSHDB` if BusinessConnect is the only application using the Redis instance, or target individual keys with `DEL` using the session token as the key prefix.

---

## Docker Security

Every service Dockerfile follows these principles:

### Non-root user

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
...
USER appuser
```

The container process runs as `appuser` (UID/GID assigned by Alpine). It cannot write to the filesystem outside of explicitly mounted volumes. The application binary and `node_modules` are owned by root and readable but not writable by `appuser`.

### dumb-init as PID 1

```dockerfile
RUN apk add --no-cache dumb-init
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/index.js"]
```

`dumb-init` is a minimal init system that:
- Properly forwards signals (SIGTERM, SIGINT) to the Node.js process.
- Reaps zombie processes that `node` would otherwise leave orphaned.
- Ensures graceful shutdown works correctly when Docker or ECS sends SIGTERM.

### No secrets in image layers

- No credentials, API keys, or tokens are embedded in `Dockerfile` instructions or `ENV` directives.
- All secrets are injected at runtime via environment variables from ECS task definitions, Kubernetes Secrets, or Docker Compose.
- The `.dockerignore` file in each service excludes `.env`, `terraform.tfvars`, and `*.tfstate`.

### Multi-stage build

The builder stage compiles TypeScript and installs all devDependencies. The runner stage copies only the compiled `dist/` directory and production `node_modules` — devDependencies, source TypeScript files, test files, and build tools are never in the final image.

---

## Network Security

All inbound traffic is controlled by AWS Security Groups with least-privilege rules. No port is open to `0.0.0.0/0` except the ALB on port 80 and 443.

### Security group topology

```
Internet (0.0.0.0/0)
    │ :80, :443
    ▼
[sg-alb] ─────────────────────────────────────────────────────────┐
    │ :3000                                                         │
    ▼                                                              │
[sg-frontend]                                                      │
    │ :4000                                                         │
    ▼                                                              │
[sg-gateway]                                                       │
    │ :4001                                                         │
    ▼                                                              │
[sg-auth] ◄──── [sg-backend-services] (:4001 for session calls)   │
    │                  │ :4002–:4004                               │
    │                  ▼                                           │
    │         [business, review, inquiry]                          │
    │                  │                                           │
    ├──────────────────┤ :5432                                     │
    ▼                  ▼                                           │
[sg-postgres]   [sg-redis] ◄─ :6379 (auth + backend services)     │
                                                                   │
[sg-eks-nodes] ◄──────────────────────────────────────────────────┘
  (node-to-node self + from ALB; port 0-65535 for NodePort routing)
```

### Security group rules summary

| Security Group    | Ingress from                          | Port(s)    |
|-------------------|---------------------------------------|------------|
| `sg-alb`          | `0.0.0.0/0`                           | 80, 443    |
| `sg-frontend`     | `sg-alb`                              | 3000       |
| `sg-gateway`      | `sg-frontend`                         | 4000       |
| `sg-auth`         | `sg-gateway`, `sg-backend-services`   | 4001       |
| `sg-backend-services` | `sg-gateway`                      | 4002–4004  |
| `sg-redis`        | `sg-auth`, `sg-backend-services`      | 6379       |
| `sg-postgres`     | `sg-auth`, `sg-backend-services`      | 5432       |
| `sg-eks-nodes`    | self (node-to-node), `sg-alb`         | all        |

All security groups have an open egress rule (`0.0.0.0/0`) to allow services to reach ECR, CloudWatch, and the AWS APIs. Restrict this in high-security deployments using VPC endpoints.

### EKS network policy

Kubernetes NetworkPolicy resources are not deployed in the current setup. Pod-to-pod isolation within the cluster relies on the node-level security group. For a production hardening step, add NetworkPolicy resources that restrict cross-namespace traffic and limit which pods can reach the database pods.

---

## Secrets Management

### Current state (development / this project)

| Platform | Where secrets live                                   | How they reach the container       |
|----------|------------------------------------------------------|------------------------------------|
| Local    | `docker-compose.yml` environment block               | Docker Compose env injection       |
| ECS      | Terraform variable values in `terraform.tfvars`      | ECS task definition `environment`  |
| EKS      | `k8s/02-secrets.yaml` (base64-encoded)               | Kubernetes Secret env vars         |

**Important**: The ECS approach passes secrets as plaintext in ECS task definition environment variables. These values are stored in the ECS task definition revision and are visible to anyone with `ecs:DescribeTaskDefinition` IAM permission. This is acceptable for a benchmarking project but is not recommended for production.

The Kubernetes secrets file (`k8s/02-secrets.yaml`) contains base64-encoded development defaults. Base64 is **not encryption**. Do not commit real production secrets in this file.

### Recommended production approach

#### AWS Secrets Manager + ECS

Store each secret in AWS Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name "businessconnect/prod/better-auth-secret" \
  --secret-string "$(openssl rand -hex 32)"
```

Reference it in the ECS task definition using `secrets` instead of `environment`:

```json
{
  "name": "BETTER_AUTH_SECRET",
  "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:businessconnect/prod/better-auth-secret"
}
```

Grant the ECS task role `secretsmanager:GetSecretValue` on those ARNs. The ECS agent fetches the value at task launch time — it is never stored in the task definition.

#### External Secrets Operator + AWS Secrets Manager (EKS)

Install the [External Secrets Operator](https://external-secrets.io/) and create `ExternalSecret` resources that pull from AWS Secrets Manager and materialise as Kubernetes Secrets:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: businessconnect-secrets
  namespace: businessconnect
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: businessconnect-secrets
  data:
    - secretKey: BETTER_AUTH_SECRET
      remoteRef:
        key: businessconnect/prod/better-auth-secret
    - secretKey: DB_PASSWORD
      remoteRef:
        key: businessconnect/prod/db-password
```

This removes all plaintext secrets from the Kubernetes manifest files and git history.

### Secret rotation

Rotate secrets immediately whenever:
- A team member with access leaves the organisation.
- A secret may have been exposed (leaked in logs, committed to git, etc.).
- As part of scheduled rotation (recommended quarterly for long-lived secrets).

Rotation procedure:

1. Generate a new secret value.
2. Update it in AWS Secrets Manager (or wherever it is stored).
3. Redeploy affected services to pick up the new value.
4. For `BETTER_AUTH_SECRET`: rotating this value will invalidate all active sessions. Users will need to log in again. Schedule rotation during a low-traffic window and communicate to users if needed.
5. For `DB_PASSWORD`: update it in PostgreSQL first (`ALTER USER postgres PASSWORD '...'`), then update the secret store, then redeploy. There will be a brief window of auth failure between the PostgreSQL change and service redeploy — perform this during a maintenance window.

---

## Rate Limiting

All Express services use `express-rate-limit` with the same baseline configuration:

```typescript
rateLimit({
  windowMs: 15 * 60 * 1000,   // 15 minutes
  max: 100,                    // 100 requests per window per IP
  standardHeaders: true,       // Return RateLimit-* headers (RFC 6585)
  legacyHeaders: false,        // Do not send X-RateLimit-* headers
})
```

### Behaviour

Clients that exceed 100 requests in 15 minutes receive a `429 Too Many Requests` response. The counter resets after the 15-minute window expires.

The `RateLimit-Limit`, `RateLimit-Remaining`, and `RateLimit-Reset` headers are included in every response so clients can implement their own back-off.

### Adjusting the limits

To change the rate limit for a specific service, edit `src/index.ts` in that service:

```typescript
// More restrictive for auth endpoints (prevent brute force)
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,   // 20 attempts per 15 minutes
})

// More permissive for a read-heavy public endpoint
const readLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 300,
})
```

For production, consider using Redis as the rate limiter store (`rate-limit-redis`) so that the limit is shared across multiple replicas of the same service. The current in-memory store is per-instance, meaning a client could exceed the effective limit by spreading requests across replicas.

---

## Helmet.js HTTP Security Headers

Every Express service uses `helmet()` with default settings. The key headers it sets:

| Header                       | Value (default)                  | Purpose                                              |
|------------------------------|----------------------------------|------------------------------------------------------|
| `Content-Security-Policy`    | Multiple directives (see below)  | Prevents XSS by controlling resource loading origins |
| `X-Frame-Options`            | `SAMEORIGIN`                     | Prevents clickjacking by blocking iframe embedding   |
| `X-Content-Type-Options`     | `nosniff`                        | Prevents MIME-type sniffing                          |
| `Strict-Transport-Security`  | `max-age=15552000; includeSubDomains` | Forces HTTPS for 180 days once served over HTTPS |
| `X-DNS-Prefetch-Control`     | `off`                            | Reduces information leakage via DNS prefetch         |
| `X-Download-Options`         | `noopen`                         | Prevents IE from auto-opening downloads              |
| `Referrer-Policy`            | `no-referrer`                    | Suppresses the `Referer` header on cross-origin requests |
| `X-Permitted-Cross-Domain-Policies` | `none`                  | Prevents Flash/Acrobat from loading cross-domain data|
| `Cross-Origin-Embedder-Policy` | `require-corp`                 | Required for SharedArrayBuffer/high-resolution timers |
| `Cross-Origin-Opener-Policy` | `same-origin`                    | Isolates the browsing context                        |
| `Cross-Origin-Resource-Policy` | `same-origin`                  | Prevents cross-origin resource leakage               |

### Content-Security-Policy

Helmet's default CSP is intentionally strict. If the frontend needs to load resources from external origins (CDN fonts, analytics, etc.), configure CSP explicitly on the frontend service:

```typescript
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'"],   // Vite dev mode requires this
      styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
      fontSrc: ["'self'", "https://fonts.gstatic.com"],
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'"],
    },
  },
}))
```

### HSTS considerations

`Strict-Transport-Security` only takes effect when the service is served over HTTPS. In the current setup the ALB terminates HTTP only (port 80). To enable HSTS:
1. Provision an ACM certificate for your domain.
2. Add an HTTPS listener (port 443) to the ALB.
3. Add the certificate ARN to the Terraform ALB listener resource.
4. Update `frontend_url` and `GATEWAY_URL` to use `https://`.

---

## Incident Response: Compromised Credentials

### If a database password is compromised

1. **Immediately** change the PostgreSQL password:
   ```sql
   ALTER USER postgres PASSWORD 'new-strong-password';
   ```
2. Update the secret in AWS Secrets Manager / Kubernetes Secret.
3. Force a redeployment of all services that use `DATABASE_URL`:
   ```bash
   # ECS
   aws ecs update-service --cluster businessconnect-ecs --service businessconnect-auth-service --force-new-deployment
   # Repeat for business, review, inquiry services
   
   # EKS
   kubectl rollout restart deployment/auth-service -n businessconnect
   # Repeat for other deployments
   ```
4. Audit the PostgreSQL logs for any unauthorized queries during the exposure window:
   ```bash
   aws logs tail /ecs/businessconnect/postgres --follow
   ```

### If the better-auth secret is compromised

Rotating `BETTER_AUTH_SECRET` invalidates all existing sessions. All users will be logged out.

1. Generate a new secret: `openssl rand -hex 32`
2. Update it in your secret store.
3. Redeploy `auth-service`.
4. All existing sessions in Redis and PostgreSQL become invalid. Users will need to log in again.
5. Optionally, explicitly delete all sessions from Redis and PostgreSQL to remove stale entries:
   ```sql
   DELETE FROM session;
   ```
   ```bash
   redis-cli FLUSHDB
   ```

### If AWS credentials are compromised

1. **Immediately** deactivate the exposed IAM access key in the AWS console:
   ```bash
   aws iam update-access-key --access-key-id <KEY_ID> --status Inactive
   ```
2. Generate a new key pair and update GitHub Secrets / CI/CD configuration.
3. Review CloudTrail logs for the compromised key's activity during the exposure window:
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=Username,AttributeValue=<iam-user> \
     --start-time <exposure-start>
   ```
4. If the key had write access to ECR, audit recently pushed images for tampering.
5. Delete the compromised key after the new key is verified to be working.

### If a git commit accidentally includes secrets

1. Remove the secret from the file and commit the fix immediately.
2. Rotate the exposed secret — it must be treated as compromised even if the commit is rewritten, because git history may have been cached by GitHub, forks, or CI logs.
3. Use `git filter-repo` to rewrite history if needed (coordinate with the team as this rewrites all commits):
   ```bash
   pip install git-filter-repo
   git filter-repo --path-glob '*.env' --invert-paths
   ```
4. Force-push the rewritten history and notify all contributors to re-clone.

---

## Dependency Security

### npm audit

Run `npm audit` in each service directory before opening a pull request:

```bash
cd services/auth-service
npm audit

# Automatically fix non-breaking vulnerabilities
npm audit fix
```

Address all **high** and **critical** severity vulnerabilities. Document any accepted risks for vulnerabilities that cannot be fixed (for example, a transitive dependency with no available fix).

### Dependabot

Enable GitHub Dependabot for automated dependency update pull requests. Add `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/services/auth-service"
    schedule:
      interval: "weekly"
  - package-ecosystem: "npm"
    directory: "/services/business-service"
    schedule:
      interval: "weekly"
  # Repeat for each service and frontend
  - package-ecosystem: "terraform"
    directory: "/terraform"
    schedule:
      interval: "monthly"
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "monthly"
```

### Container base image scanning

Enable ECR image scanning on push in `terraform/ecr.tf`:

```hcl
resource "aws_ecr_repository" "services" {
  ...
  image_scanning_configuration {
    scan_on_push = true
  }
}
```

Review scan results after each push:

```bash
aws ecr describe-image-scan-findings \
  --repository-name businessconnect/auth-service \
  --image-id imageTag=latest \
  --query 'imageScanFindings.findings[?severity==`HIGH` || severity==`CRITICAL`]'
```
