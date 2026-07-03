# Secure CI/CD DevSecOps Pipeline

An M.Tech dissertation project demonstrating a production-grade DevSecOps pipeline — integrating security scanning, infrastructure-as-code, and automated deployment across every stage of the software delivery lifecycle.

---

## Architecture Overview

```
Developer Push
      │
      ▼
┌─────────────────────────────────────────────────────────────────────┐
│  CI/CD Pipeline  (Jenkins or GitLab CI)                             │
│                                                                     │
│  Build → Unit Tests → SAST → Container Scan → Secrets Scan         │
│       → Quality Gate → ECR Push → ECS Deploy → DAST                │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │   AWS (ap-south-1)    │
                    │                       │
                    │  ECR Repository       │
                    │  ECS Fargate Cluster  │
                    │  VPC + Security Groups│
                    │  CloudWatch Logs      │
                    └───────────────────────┘
```

### Security tooling at each stage

| Stage | Tool | What it checks |
|-------|------|----------------|
| Build | Docker multi-stage | No dev deps in production image |
| Dependency scan | `npm audit` | Known CVEs in Node.js packages |
| SAST | SonarQube | Code bugs, security hotspots, smells |
| Quality Gate | SonarQube API | Enforced — fails build if not OK |
| Container scan | Trivy | OS and library CVEs in image layers |
| Secrets scan | TruffleHog | Leaked credentials in git history |
| DAST | OWASP ZAP | Runtime vulnerabilities in deployed app |
| Infrastructure | Terraform | Immutable ECR tags, least-privilege IAM |

---

## Project Structure

```
secure-cicd-devsecops/
├── app/                       # Express.js microservice
│   ├── index.js               # Application code
│   ├── test/index.test.js     # Jest test suite
│   ├── Dockerfile             # Multi-stage, non-root, real HEALTHCHECK
│   └── package.json           # Dependencies: express, helmet, express-rate-limit
├── terraform/                 # AWS infrastructure (IaC)
│   ├── main.tf                # Provider config
│   ├── vpc.tf                 # VPC, subnets, IGW, route tables
│   ├── ecs.tf                 # ECS cluster, task definition, service
│   ├── ecr.tf                 # ECR with IMMUTABLE tags + KMS encryption
│   ├── iam.tf                 # Least-privilege IAM roles
│   ├── security.tf            # Security groups (ALB, ECS)
│   ├── variables.tf           # Input variables
│   └── outputs.tf             # Outputs (VPC ID, ECR URL, etc.)
├── jenkins/                   # Jenkins configuration
│   ├── Dockerfile             # Jenkins LTS + curl healthcheck
│   └── init.groovy.d/
│       └── basic-security.groovy  # Admin creds from env vars (not hardcoded)
├── Jenkinsfile                # Main Jenkins declarative pipeline
├── .gitlab-ci.yml             # GitLab CI alternative pipeline
├── docker-compose.yml         # Local dev: app + SonarQube + PostgreSQL
├── devsecops-policy.json      # Least-privilege AWS IAM policy
├── sonar-project.properties   # SonarQube project config
└── SECURITY_AUDIT_REPORT.md   # Documented findings and remediations
```

---

## Prerequisites

| Tool | Minimum version | Purpose |
|------|----------------|---------|
| Docker Desktop | 24+ | Container build and local orchestration |
| Node.js | 18+ | Run and test the application |
| AWS CLI | 2+ | Interact with ECR and ECS |
| Terraform | 1.8+ | Provision AWS infrastructure |
| Jenkins | LTS | CI/CD orchestration |

---

## Local Development

### 1. Clone and install

```bash
git clone <repo-url>
cd secure-cicd-devsecops
cd app && npm ci
```

### 2. Set required environment variables

```bash
# Required to protect /toggle-health endpoint (use a strong random value)
export ADMIN_API_KEY="your-strong-random-key-here"
export PORT=3000
```

### 3. Start the full local stack

```bash
# Starts app (port 3000), SonarQube (port 9000), and PostgreSQL
docker-compose up -d
```

### 4. Run tests

```bash
cd app
npm test                  # Run tests with coverage
npm run lint              # Lint check
npm run audit:check       # Dependency vulnerability check
```

### 5. Access services

| Service | URL | Credentials |
|---------|-----|-------------|
| Application | http://localhost:3000 | — |
| SonarQube | http://localhost:9000 | admin / admin (change on first login) |

---

## API Reference

### `GET /`

Returns a greeting and version information.

```json
{
  "message": "Hello from DevSecOps App 🚀",
  "version": "1.0.0",
  "timestamp": "2026-05-20T10:00:00.000Z"
}
```

### `GET /health`

Health check endpoint used by ECS, the ALB, and the Docker HEALTHCHECK.

```json
// 200 OK — healthy
{ "status": "healthy", "uptime": 123.4, "timestamp": "..." }

// 503 Service Unavailable — unhealthy
{ "status": "unhealthy", "uptime": 123.4, "timestamp": "..." }
```

### `POST /toggle-health`  🔒 Protected

Toggles the health state. Requires the `X-API-Key` header.

```bash
curl -X POST http://localhost:3000/toggle-health \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-admin-api-key" \
  -d '{"healthy": false}'
```

```json
// 200 OK
{ "updated": false, "timestamp": "..." }

// 401 Unauthorized (missing or wrong key)
{ "error": "Unauthorized: invalid or missing API key." }

// 400 Bad Request (non-boolean value)
{ "error": "Request body must contain 'healthy' as a boolean value." }
```

---

## CI/CD Pipeline (Jenkins)

### Required Jenkins credentials

Go to **Manage Jenkins → Credentials → System → Global credentials**:

| ID | Type | Description |
|----|------|-------------|
| `aws-ecr-prod` | AWS credentials | Access key + secret for ECR/ECS/STS |
| `sonarqube-token` | Secret text | SonarQube user token |

### Required Jenkins tools

Go to **Manage Jenkins → Tools → NodeJS installations**:
- Name: `Node-18`, version: Node.js 18 LTS

### Pipeline stages

1. **Cleanup** — Remove stale containers from previous runs
2. **Verify AWS Credentials** — Confirm identity and ECR/ECS access
3. **Build Docker Image** — Multi-stage build with `build-NNN` tag
4. **Container Scan (Trivy)** — Fails on CRITICAL CVEs; no `|| echo` bypass
5. **Start SonarQube** — Launch local SonarQube + PostgreSQL via Docker Compose
6. **Install Dependencies** — `npm ci` (clean install)
7. **Dependency Scan** — `npm audit` fails on moderate+ vulnerabilities
8. **Unit Tests** — Jest with coverage (enforced thresholds)
9. **SonarQube Analysis** — Static code analysis
10. **Quality Gate** — Polls SonarQube API; fails build if status ≠ OK
11. **Push to ECR** — Pushes image with `build-NNN` tag (no bare `latest`)
12. **Deploy to ECS** — `update-service` + `wait services-stable`
13. **Health Check** — Verifies ECS running/desired counts; hits ALB `/health`
14. **DAST (ZAP)** — Baseline scan against deployed service URL
15. **Secrets Scan** — TruffleHog fails build on verified secret leaks
16. **Final Verification** — Confirms service state via AWS CLI

---

## AWS Infrastructure (Terraform)

### Setup

```bash
cd terraform

# Configure remote state backend BEFORE running init (never commit tfstate to git)
# Add a backend "s3" block to main.tf pointing to your state bucket.

terraform init
terraform plan \
  -var="aws_account_id=395069634073" \
  -var="aws_region=ap-south-1" \
  -var="ecs_task_execution_role_arn=arn:aws:iam::395069634073:role/ecsTaskExecutionRole" \
  -var="ecr_repo_url=395069634073.dkr.ecr.ap-south-1.amazonaws.com/devsecops-app" \
  -var="app_subnet_ids=[\"subnet-xxx\",\"subnet-yyy\"]" \
  -var="app_security_group_id=sg-xxx"

terraform apply
```

### Resources provisioned

| Resource | Details |
|----------|---------|
| VPC | 10.0.0.0/16, DNS enabled |
| Public subnets | 2× in ap-south-1a/b (for ALB) |
| Private subnets | 2× in ap-south-1a/b (for ECS tasks) |
| ECS Cluster | Container Insights enabled |
| ECS Task Definition | 256 CPU / 512 MB, read-only root FS, capabilities dropped |
| ECS Service | Deployment circuit breaker + auto-rollback |
| ECR Repository | IMMUTABLE tags, KMS encryption, scan on push |
| CloudWatch Logs | 30-day retention |
| IAM Roles | Least-privilege (scoped to specific resource ARNs) |
| Security Groups | ALB (80/443 public) + ECS (3000 from ALB only) |

---

## Security Controls Summary

### Application layer
- **helmet** — Sets `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`, etc.
- **express-rate-limit** — 100 requests per 15 minutes per IP
- **API key authentication** — `/toggle-health` requires `X-API-Key` header
- **Input validation** — Boolean type check on request body
- **Non-root container user** — UID 1001 (not root)
- **Read-only root filesystem** — Enforced in ECS task definition

### Infrastructure layer
- **Immutable ECR tags** — Prevents supply-chain tag-overwrite attacks
- **ECS deployment circuit breaker** — Auto-rollback on failed deployments
- **CloudWatch encryption** — Logs encrypted at rest
- **No direct public IPs** — ECS tasks behind ALB, not directly internet-facing
- **Least-privilege IAM** — Specific actions and resource ARNs, no wildcards

### Pipeline layer
- **No silenced failures** — All `|| echo` bypasses removed
- **Real Quality Gate** — SonarQube API polled; build fails if status ≠ OK
- **CRITICAL CVE gate** — Trivy `--exit-code 1` on CRITICAL severity
- **Verified secrets gate** — TruffleHog `--fail` on verified leaks
- **No hardcoded credentials** — All secrets via Jenkins Credential Store
- **Build-number image tags** — Never deploy bare `latest`
- **No Docker socket mounting** — Trivy scans image tarballs (no privilege escalation)

---

## Jenkins Security Setup

Jenkins admin credentials are read from environment variables at container startup — never hardcoded.

```bash
# Generate a strong random password
export JENKINS_ADMIN_USER=admin
export JENKINS_ADMIN_PASSWORD="$(openssl rand -base64 32)"

docker run -d \
  -p 8080:8080 \
  -e JENKINS_ADMIN_USER \
  -e JENKINS_ADMIN_PASSWORD \
  --name jenkins \
  your-jenkins-image:latest
```

---

## Known Limitations (Dissertation Scope)

- **No ALB provisioned** — ECS service uses `assign_public_ip = false` with ALB block commented in `ecs.tf`. Uncomment when your account supports ALB creation.
- **No NAT Gateway** — Private subnets have no outbound internet access (noted as M-6). A NAT Gateway is needed for private tasks to reach external services.
- **No remote Terraform state** — Use S3 + DynamoDB locking for all non-local environments. Never commit `.tfstate` files.
- **Single task instance** — `desired_count = 1`. Increase for production availability.
