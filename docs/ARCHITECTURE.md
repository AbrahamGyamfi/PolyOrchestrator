# Architecture Decisions

This document records the significant architectural decisions made in the BusinessConnect platform. Each decision is documented as an Architecture Decision Record (ADR) with context, the decision, and the consequences — including trade-offs accepted.

---

## Table of Contents

- [System Overview](#system-overview)
- [Component Diagram](#component-diagram)
- [ADR-001: Microservices over monolith](#adr-001-microservices-over-monolith)
- [ADR-002: better-auth over custom JWT](#adr-002-better-auth-over-custom-jwt)
- [ADR-003: Drizzle ORM over Prisma](#adr-003-drizzle-orm-over-prisma)
- [ADR-004: ECS in public subnets, no NAT Gateway](#adr-004-ecs-in-public-subnets-no-nat-gateway)
- [ADR-005: Dual ECS and EKS deployment](#adr-005-dual-ecs-and-eks-deployment)
- [Service Discovery Comparison](#service-discovery-comparison)
- [Database Strategy](#database-strategy)
- [Image Storage: Current State and Migration Path](#image-storage-current-state-and-migration-path)

---

## System Overview

BusinessConnect is a multi-tenant business directory application. Users can register businesses, post jobs and events, receive reviews, and handle inquiries from potential customers.

The application is structured as a set of independent services, each responsible for a bounded domain. Services communicate exclusively through HTTP over internal networks. No shared memory, no message brokers, no shared libraries between services.

The system is deployed to two AWS container orchestrators — Amazon ECS Fargate and Amazon EKS — as a benchmarking exercise comparing the operational characteristics of each.

### Technology choices at a glance

| Layer        | Technology                                               |
|--------------|----------------------------------------------------------|
| Frontend     | React 19, Vite, Tailwind CSS v4, Radix UI, React Router v6 |
| API proxy    | Express with http-proxy-middleware                        |
| Auth         | better-auth 1.2 (email/password, session-based)          |
| Backend ORM  | Drizzle ORM with pg driver                               |
| Email        | nodemailer (SMTP, optional)                              |
| Database     | PostgreSQL 16                                            |
| Cache/sessions | Redis 7                                               |
| Container runtime | Docker, Alpine-based images                        |
| IaC          | Terraform >= 1.6 (AWS provider 5.x)                     |
| ECS          | Fargate launch type, Cloud Map service discovery         |
| EKS          | Managed node group (t3.medium), CoreDNS, ALB Ingress     |
| Logging      | pino (structured JSON), CloudWatch Logs                  |
| Testing      | Vitest, supertest                                        |

---

## Component Diagram

```
                          ┌────────────────────────────────────────────┐
                          │               AWS VPC 10.0.0.0/16          │
                          │                                            │
  Internet ─── Port 80 ──►│  [Application Load Balancer]               │
                          │           │                                │
                          │           │ :3000                          │
                          │           ▼                                │
                          │  ┌─────────────────┐                       │
                          │  │    Frontend      │                       │
                          │  │ Nginx + React 19 │                       │
                          │  │   :3000          │                       │
                          │  └────────┬────────┘                       │
                          │           │ /api/*  :4000                  │
                          │           ▼                                │
                          │  ┌─────────────────┐                       │
                          │  │    Gateway       │                       │
                          │  │  Express proxy   │                       │
                          │  │   :4000          │                       │
                          │  └──┬──┬──┬──┬─────┘                       │
                          │     │  │  │  │                             │
                          │  :4001 :4002 :4003 :4004                   │
                          │     │  │  │  │                             │
                          │  ┌──▼──┐┌─▼───────┐┌─▼──────┐┌─▼───────┐  │
                          │  │Auth ││Business ││Review  ││Inquiry  │  │
                          │  │Svc  ││Svc      ││Svc     ││Svc      │  │
                          │  └──┬──┘└─┬───────┘└─┬──────┘└─┬───────┘  │
                          │     │     │           │         │          │
                          │     │     └─────┬─────┘─────────┘          │
                          │     │           │ :5432                    │
                          │     │           ▼                          │
                          │     │  ┌─────────────────┐                 │
                          │     │  │   PostgreSQL 16  │                 │
                          │     │  │   :5432          │                 │
                          │     │  └─────────────────┘                 │
                          │     │                                      │
                          │     │ :6379                                │
                          │     ▼                                      │
                          │  ┌─────────────────┐                       │
                          │  │     Redis 7      │                       │
                          │  │   (sessions)     │                       │
                          │  │   :6379          │                       │
                          │  └─────────────────┘                       │
                          │                                            │
                          └────────────────────────────────────────────┘
```

---

## ADR-001: Microservices over Monolith

**Status**: Accepted

### Context

The application is a business directory with authentication, business management, reviews, and inquiries. These are functionally independent domains. The project was also explicitly designed as a deployment benchmarking exercise, meaning multiple independently deployable components were required to demonstrate service discovery, inter-service communication, and per-service scaling.

### Decision

Implement each major domain as an independent Node.js/Express service:

- `auth-service`: authentication and session management
- `business-service`: business listings, jobs, events, bookings, categories, services, admin, uploads
- `review-service`: business reviews and ratings
- `inquiry-service`: contact inquiries and email notifications
- `gateway`: HTTP reverse proxy / API gateway
- `frontend`: React SPA served by Nginx

### Consequences

**Benefits:**
- Each service can be scaled independently. The business-service handles the bulk of traffic; auth-service is lightweight.
- Services can be deployed and updated independently without a full redeployment.
- Demonstrates realistic service discovery challenges across Docker Compose, ECS Cloud Map, and Kubernetes CoreDNS.
- Failure in one service (for example, inquiry-service SMTP misconfiguration) does not affect other services.

**Costs:**
- Higher operational complexity than a monolith. Service startup order must be managed (Docker Compose `depends_on`).
- Cross-service HTTP calls add latency. Every authenticated request to business, review, or inquiry services makes an additional HTTP call to auth-service for session validation.
- The shared PostgreSQL database (see [Database Strategy](#database-strategy)) creates a hidden coupling between services that contradicts the microservices independence principle.
- Testing requires mocking inter-service calls or running the full stack.

**Rejected alternatives:**
- **Monolith**: Would have simplified development and testing, but would not serve the deployment benchmarking goal of demonstrating container orchestration with multiple services.
- **GraphQL federation**: Too much additional complexity for a project of this scale.

---

## ADR-002: better-auth over Custom JWT

**Status**: Accepted

### Context

The application requires email/password authentication with persistent sessions. Options considered:
1. Custom JWT implementation with `jsonwebtoken` library
2. Passport.js with a local strategy
3. better-auth (v1.2)
4. Auth0 / Clerk (managed third-party)

### Decision

Use **better-auth** as the authentication framework. It provides a complete auth solution (email/password, session management, account linking) with a single dependency. Session state is stored server-side in PostgreSQL with Redis as a secondary fast store.

### Why not custom JWT?

Custom JWT implementations have several recurring pitfalls:
- Algorithm confusion attacks (accepting `alg: none`)
- Incorrect `exp` validation
- No built-in session revocation (JWTs are stateless by design)
- Developers re-implementing refresh token rotation incorrectly

better-auth uses opaque session tokens stored server-side, which means:
- Sessions can be revoked immediately
- No token held by the client contains any information
- The auth logic is maintained by the library, not the application team

### Why not Auth0 / Clerk?

External managed auth services introduce:
- Vendor dependency on an external network call for every auth decision
- Data residency concerns (user PII sent to third-party)
- Cost at scale
- Reduced control over session behaviour

For a project running entirely within an AWS VPC, keeping auth internal makes sense.

### Consequences

**Benefits:**
- Session revocation works immediately (delete from Redis/PostgreSQL).
- No JWT secret management — the `BETTER_AUTH_SECRET` is used for signing cookies, not distributed to services.
- Complete auth system with minimal code: `auth-service/src/auth.ts` is 34 lines.
- Redis secondary storage makes session lookups fast without additional infrastructure.

**Costs:**
- Every protected request in downstream services requires an HTTP call to auth-service (`/api/auth/get-session`). This adds ~1–5ms of internal latency per request.
- better-auth is a relatively new library (v1.x). Its API may change between versions.
- All session state is stored in two places (PostgreSQL + Redis), requiring both to be healthy for auth to function.

**Trade-off accepted:**
The latency of the session validation call is an acceptable trade-off for the security benefit of server-side session revocation. In a high-throughput scenario, the auth-service can be scaled horizontally and Redis lookups are sub-millisecond.

---

## ADR-003: Drizzle ORM over Prisma

**Status**: Accepted

### Context

The backend services require a database access layer for PostgreSQL. The two primary candidates for TypeScript projects are:
- **Prisma** (v5): schema-first, generates a type-safe client, requires a binary query engine
- **Drizzle ORM** (v0.45): code-first, schema defined in TypeScript, no binary dependencies

### Decision

Use **Drizzle ORM** for all database access in `business-service`, `review-service`, and `inquiry-service`.

### Reasons

1. **No binary dependencies**: Prisma requires a native query engine binary (`prisma-engines`) that must be compiled for the target platform (`linux/amd64`). This increases image build time and image size. Drizzle is pure TypeScript/JavaScript with no native binaries.

2. **Alpine compatibility**: Prisma's binary engine has occasional glibc compatibility issues with Alpine Linux. Drizzle works on any platform without modification.

3. **Lighter container images**: Without the Prisma engine binary, images are smaller. The business-service image is approximately 80MB vs ~140MB with Prisma.

4. **TypeScript-native schema**: Drizzle schemas are regular TypeScript code. They can be imported, composed, and referenced by tooling like vitest without any code generation step. Prisma requires running `prisma generate` before TypeScript compilation.

5. **SQL-like query API**: Drizzle's query API closely mirrors SQL, making it easier to audit and understand generated queries without learning a bespoke abstraction.

### Consequences

**Benefits:**
- Faster Docker builds (no binary compilation or download).
- No `prisma generate` step needed in CI or Dockerfile.
- Schema as code is easier to keep in sync across services.
- `drizzle-kit push` works directly against the database without maintaining migration files.

**Costs:**
- Drizzle has a smaller ecosystem than Prisma. Third-party tooling (admin UIs, introspection tools) is primarily built for Prisma.
- The query builder API is lower-level than Prisma's. Complex queries require more explicit code.
- `db:push` (schema sync without migration files) is not suitable for production schema management. A migration-file workflow (`db:generate` + `db:migrate`) should be adopted before going to production.

**Rejected alternative:**
- **Prisma**: Heavier, requires binary, slower builds. The type safety benefits are achievable with Drizzle.
- **Raw pg queries**: Loses type safety and increases boilerplate.

---

## ADR-004: ECS in Public Subnets, No NAT Gateway

**Status**: Accepted

### Context

The initial infrastructure design placed ECS Fargate tasks in private subnets and used a NAT Gateway for outbound internet access (to reach ECR, CloudWatch, and AWS API endpoints). A NAT Gateway costs approximately $32/month in base fees, plus $0.045 per GB of data processed — significant for a development/benchmarking environment.

### Decision

Remove the NAT Gateway. Place all ECS Fargate tasks and EKS nodes in **public subnets** with `assign_public_ip = true`. Internet access for outbound calls (ECR pull, CloudWatch log delivery, AWS APIs) goes directly via the Internet Gateway.

```hcl
# vpc.tf — comment left in the code
# NAT Gateway removed — ECS Fargate tasks run in public subnets with public IPs.
# Add a NAT Gateway back here if EKS nodes (private subnets) need internet access.
```

### Security implications

Public IPs are assigned to task ENIs, but inbound traffic is blocked by security groups. The security groups are the actual enforcement boundary:

- No security group allows inbound connections from `0.0.0.0/0` except `sg-alb` on ports 80 and 443.
- All backend service security groups accept traffic only from the upstream tier's security group.
- PostgreSQL and Redis only accept traffic from `sg-auth` and `sg-backend-services`.

The public IPs on tasks are effectively unreachable because no security group rule allows internet traffic to reach them.

### Consequences

**Benefits:**
- Saves ~$32/month in base NAT Gateway fees.
- Eliminates data processing charges for ECR pulls, CloudWatch log delivery, and AWS API calls.
- Simpler VPC routing (no NAT instance to manage).

**Costs:**
- ECS tasks and EKS nodes have public IPs. This is a non-standard configuration that may trigger security audits.
- Any misconfigured security group rule that accidentally opens inbound traffic to `0.0.0.0/0` would expose a service directly to the internet without a firewall layer. Security group hygiene is critical.
- If a future service needs to call an external API that requires a fixed outbound IP (for IP allowlisting), a NAT Gateway or Elastic IP assignment is required.

**When to add the NAT Gateway back:**
- Production deployments where regulatory or compliance requirements mandate that compute runs in private subnets.
- When a service needs to connect to a third-party that IP-allowlists the outbound IP.
- When the cost ($32/month) is not significant relative to the security benefit.

---

## ADR-005: Dual ECS and EKS Deployment

**Status**: Accepted (assignment requirement)

### Context

The project brief for the ShopNow DevOps benchmark required deploying the same application to both Amazon ECS Fargate and Amazon EKS, then measuring and comparing operational characteristics. This is an unusual design for a production application — normally you would choose one.

### Decision

Maintain Terraform code for both ECS and EKS in the same root module (`ecs.tf` and `eks.tf`). Both are provisioned by the same `terraform apply`. Deploy Kubernetes manifests independently using `scripts/02-deploy-eks.sh`.

### Operational considerations

Running both simultaneously means:
- Both clusters incur compute costs.
- Both access the same ECR repositories (images are shared).
- The ECS and EKS deployments point to the **same PostgreSQL and Redis** ECS services. This means both deployments share application state — a user created via ECS is visible via EKS. This is useful for the benchmark but unusual in practice.
- Terraform manages both clusters, so `terraform destroy` removes both in one operation.

### Consequences of the dual-deployment design

**Benefits:**
- Direct side-by-side comparison with identical application code and shared state.
- Demonstrates the difference in service discovery DNS resolution (Cloud Map vs CoreDNS).
- Single Terraform module means infrastructure drift between the two deployments is minimised.

**Costs:**
- Approximately 2x compute cost while both clusters are running.
- EKS cluster provisioning adds ~15 minutes to `terraform apply`.
- Two deployment paths to maintain — changes to the application require updates to both ECS task definitions and Kubernetes manifests.
- The shared database is a coupling point — schema migrations affect both deployments simultaneously.

**Guidance for single-platform use:**
- To use ECS only: remove or rename `eks.tf` (for example, `eks.tf.disabled`) before running `terraform apply`.
- To use EKS only: remove `ecs.tf` and `autoscaling.tf`. The ECS-specific security groups can remain as they are used by EKS nodes too.

---

## Service Discovery Comparison

| Platform      | Mechanism                          | DNS format                                       | TTL  | Health checking      |
|---------------|------------------------------------|--------------------------------------------------|------|----------------------|
| Docker Compose | Internal Docker DNS                | `http://service-name:port`                        | N/A  | Via healthcheck labels |
| ECS (Fargate) | AWS Cloud Map (Service Discovery)  | `http://service-name.businessconnect.local:port` | 10s  | Custom config (failure_threshold = 1) |
| EKS (Kubernetes) | CoreDNS (kube-dns)              | `http://service-name.namespace:port`             | 5s   | Kubernetes readiness probes |

### How Cloud Map works in ECS

Each ECS service has a paired Cloud Map service entry (`aws_service_discovery_service`). When an ECS task starts and passes its health check, the ECS agent registers the task's ENI private IP as an A record with the Cloud Map service. Other tasks resolve the hostname to all healthy task IPs using DNS.

The `MULTIVALUE` routing policy returns up to 8 IP addresses per DNS query. The caller is responsible for load balancing across the returned IPs — the Node.js HTTP client and Express proxy middleware use the first resolved IP by default, so Cloud Map provides loose multi-homing rather than true load balancing.

### How CoreDNS works in EKS

Kubernetes Services create stable virtual IPs (ClusterIP) backed by iptables/eBPF rules. Pods resolve `service-name.namespace.svc.cluster.local` to the Service ClusterIP, and the kube-proxy on each node distributes connections across healthy pod endpoints. This is more reliable for load balancing than Cloud Map's DNS-level round-robin.

### Practical differences observed

- Cloud Map DNS TTL of 10 seconds means there is a brief period after task termination where dead IPs may be returned. Services must handle connection failures gracefully.
- CoreDNS updates endpoint lists immediately when a pod's readiness probe fails, providing faster removal of unhealthy pods from the endpoint pool.
- Cloud Map requires the application to be resilient to transient DNS staleness. EKS's iptables-based routing is more immediately consistent.

---

## Database Strategy

### Current: Shared PostgreSQL

All services share a single PostgreSQL 16 instance with a single database (`church_platform`). The schema is defined in `migrate/schema.ts` and maintained via Drizzle Kit.

Services that own tables:
- **auth-service** conceptually owns: `user`, `session`, `account`, `verification`
- **business-service** owns: `category`, `business`, `job`, `event`, `booking`, `member`, `service`
- **review-service** owns: `review`
- **inquiry-service** owns: `inquiry`

However, all services connect to the same database and can technically query any table. This is a pragmatic choice for a project of this scope, not an architectural ideal.

### Trade-offs accepted

| Concern                  | Current state                              | Ideal state                                   |
|--------------------------|--------------------------------------------|-----------------------------------------------|
| Schema coupling          | All tables in one database                 | Per-service database schemas                  |
| Migration coordination   | One `db:push` touches all tables           | Per-service migration pipelines               |
| Blast radius of failure  | One PostgreSQL failure affects all services | Service continues if its own DB is healthy   |
| Cross-service data joins | Possible (but not done)                    | Impossible — requires inter-service API calls |
| Operational complexity   | Low (one connection string)                | Higher (N databases to manage)                |

### Migration path to per-service databases

If the project evolves into a production system requiring stronger service isolation:

1. Extract the `review` and `inquiry` tables into separate schemas or databases.
2. Update `review-service` and `inquiry-service` to connect to their own `DATABASE_URL`.
3. Remove cross-schema query capabilities from each service.
4. Use the API (not direct DB access) for any cross-service data requirements.

The `business` and `auth` tables have a soft dependency (both reference `userId` as a plain text foreign key, not a database-level constraint). Separating these into different databases would require that `userId` values remain consistent through the auth service API rather than a shared table.

### PostgreSQL in ECS vs EKS

Both ECS and EKS currently run PostgreSQL as a container (not as RDS). This means:

- PostgreSQL data is stored in a volume. In ECS, this is an ephemeral Fargate volume — **data is lost when the task stops**. This is acceptable for development/benchmarking, not production.
- In EKS, PostgreSQL uses a PersistentVolumeClaim backed by an EBS volume via the aws-ebs-csi-driver addon. Data persists across pod restarts.

**For production**, replace containerised PostgreSQL with **Amazon RDS for PostgreSQL** (Multi-AZ for HA, automated backups, point-in-time recovery). Remove the `postgres` ECS task definition and Kubernetes StatefulSet, and update `DATABASE_URL` in all services.

---

## Image Storage: Current State and Migration Path

### Current: Multer disk storage

Business profile images are uploaded via `POST /api/upload` in `business-service`. The route uses **multer** with disk storage, writing files to the `UPLOADS_DIR` directory (default: `/uploads`).

```typescript
// services/business-service/src/routes/upload.ts
const storage = multer.diskStorage({
  destination: UPLOADS_DIR,
  filename: (req, file, cb) => cb(null, `${Date.now()}-${file.originalname}`),
})
```

The uploaded files are then served as static assets via:

```typescript
app.use('/uploads', express.static(UPLOADS_DIR))
```

The gateway proxies `/uploads` requests to `business-service`.

In Docker Compose, the `uploads_data` named volume persists uploaded files across container restarts. In ECS, the volume is ephemeral unless EFS is mounted. In EKS, the volume is backed by an EBS PVC.

### Limitations of disk storage

- **ECS task restart**: When a Fargate task is replaced (deployment, auto-scaling, health check failure), the new task starts without the upload volume unless EFS is used.
- **Multi-replica problem**: If business-service runs with 2 replicas, each replica has its own local filesystem. An image uploaded to replica A is not accessible from replica B. This causes 50% of image requests to return 404.
- **No CDN**: Serving images directly from the Express static handler is inefficient and adds unnecessary load to the service.

### Recommended migration to S3

1. Add `@aws-sdk/client-s3` and `@aws-sdk/s3-request-presigner` to `business-service`.
2. Replace the `multer.diskStorage` configuration with `multer.memoryStorage()`.
3. In the upload route, stream the buffer directly to S3:
   ```typescript
   import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3'
   
   const s3 = new S3Client({ region: process.env.AWS_REGION })
   
   await s3.send(new PutObjectCommand({
     Bucket: process.env.S3_BUCKET,
     Key: `uploads/${Date.now()}-${file.originalname}`,
     Body: file.buffer,
     ContentType: file.mimetype,
   }))
   ```
4. Store the S3 key (or full public URL) in the `image` column of the `business` table instead of a local path.
5. For serving: either make the S3 bucket public-read, or generate pre-signed URLs with expiry.
6. For CDN: place CloudFront in front of the S3 bucket. Update the stored URLs to use the CloudFront domain. This eliminates origin bandwidth costs and improves load time globally.

The Terraform module would need:
- An S3 bucket resource with appropriate ACLs or bucket policies.
- An IAM policy granting `s3:PutObject` and `s3:GetObject` to the ECS task role / EKS pod service account.
- Optionally, a CloudFront distribution pointing to the S3 bucket.

This migration can be done without disrupting existing functionality — existing disk-stored images can be migrated to S3 in a one-time script, and the static file route can be maintained temporarily as a fallback.
