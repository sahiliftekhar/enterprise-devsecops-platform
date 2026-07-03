# 🔐 Security Audit Report — secure-cicd-devsecops
**Date:** 2026-05-05  
**Auditor:** Claude (Cowork AI)  
**Scope:** Full codebase review — app code, CI/CD pipelines, Dockerfiles, Terraform IaC, IAM policies, docker-compose

---

## Summary

| Severity | Count |
|----------|-------|
| 🔴 Critical | 4 |
| 🟠 High | 7 |
| 🟡 Medium | 6 |
| 🔵 Low / Info | 5 |
| **Total** | **22** |

---

## 🔴 CRITICAL

---

### C-1 · Hardcoded Jenkins Admin Password in Source Code
**File:** `jenkins/init.groovy.d/basic-security.groovy`, line 8

```groovy
hudsonRealm.createAccount("admin", "pass@123")
```

**Risk:** Weak, plaintext admin password committed to the repository. Anyone with repo access gains full Jenkins admin access.  
**Fix:** Remove from source. Use environment variables or Jenkins' built-in secrets manager. On first boot, read the password from a secure secret store (e.g., AWS Secrets Manager or a Kubernetes secret).

---

### C-2 · Quality Gate Is Completely Bypassed
**File:** `Jenkinsfile`, lines 154–161

```groovy
stage('Quality Gate') {
    steps {
        script {
            sleep(10)
            echo "Quality Gate check completed - Assuming PASS for dissertation demo"
        }
    }
}
```

**Risk:** SonarQube is being run but its results are never enforced. Code with known vulnerabilities, bugs, or poor quality will pass the gate unconditionally. This makes the entire SAST stage cosmetic.  
**Fix:** Replace with a real gate check:
```groovy
timeout(time: 5, unit: 'MINUTES') {
    waitForQualityGate abortPipeline: true
}
```

---

### C-3 · Security Scan Failures Are Silently Swallowed
**File:** `Jenkinsfile`, lines 75, 124, 271, 277, 294

```bat
|| echo "Trivy scan completed with findings"
|| echo "Audit completed with findings"
|| echo "ZAP baseline completed with findings"
```

**Risk:** Trivy, npm audit, and OWASP ZAP all use `|| echo ...` to suppress non-zero exit codes. CRITICAL vulnerabilities in the container or dependencies will not fail the build — they will be silently logged and the pipeline continues to deploy.  
**Fix:** Remove the `|| echo` fallbacks and instead use threshold flags:
```bat
# Trivy: fail on CRITICAL only
trivy image --exit-code 1 --severity CRITICAL devsecops-ci-app:latest
# npm audit: fail on high+
npm audit --audit-level=high
```

---

### C-4 · Unprotected `/toggle-health` Endpoint Exposed in Production
**File:** `app/index.js`, lines 23–27

```js
app.post("/toggle-health", (req, res) => {
  isHealthy = req.body.healthy;
  res.json({ updated: isHealthy });
});
```

**Risk:** Any unauthenticated caller can `POST /toggle-health` with `{"healthy": false}` to make the application permanently report itself as unhealthy. ECS health checks would then restart or drain the service — a trivial Denial of Service attack. There is also no input validation; passing a non-boolean crashes the logic silently.  
**Fix:** This endpoint should not exist in production. Guard it with a `NODE_ENV` check or remove it entirely, using a dedicated test helper instead:
```js
if (process.env.NODE_ENV !== 'test') {
  // don't register this route
}
```

---

## 🟠 HIGH

---

### H-1 · Two Different AWS Account IDs in Committed Files
**Files:** `Jenkinsfile` (line 10), `task-definition.json` (line 7), `ecs-task-def.json` (line 7)

- `Jenkinsfile` and `task-definition.json` → account `395069634073`
- `ecs-task-def.json` → account `863207306654` (different account!)

**Risk:** Inconsistent account IDs indicate either a stale/wrong task definition being used, or accidental exposure of a second AWS account. Deploying `ecs-task-def.json` pulls an image from the wrong account and will fail at runtime with an authorization error.  
**Fix:** Standardise on one account ID. Store it as a pipeline environment variable or parameter rather than hardcoding it. Delete `ecs-task-def.json` or reconcile it with `task-definition.json`.

---

### H-2 · AWS Health Check Hardcoded as Skipped
**File:** `Jenkinsfile`, lines 233–242

```bat
echo "⚠️  Skipping AWS Health Check for dissertation demo"
echo "✅ Health check considered PASSED - Continuing pipeline"
```

**Risk:** A broken deployment will be considered healthy. The pipeline will report success even if the newly deployed container is crashing.  
**Fix:** Implement a real health check against the ECS service endpoint. If no public ALB is available, use `aws ecs describe-tasks` to verify task status, or wait on a CloudWatch metric alarm.

---

### H-3 · SonarQube Running Without Authentication
**File:** `docker-compose.yml`, line 50

```yaml
- SONAR_FORCE_AUTHENTICATION=false
```

**Risk:** The SonarQube instance at port 9000 accepts anonymous access. Anyone on the same network can read project code analysis results, security hotspot details, and potentially configure projects.  
**Fix:** Remove this flag. SonarQube defaults to requiring authentication. Use proper service accounts for CI integration.

---

### H-4 · Docker Socket Mounted into Trivy/TruffleHog Containers
**File:** `Jenkinsfile`, lines 72–73, 291

```bat
-v /var/run/docker.sock:/var/run/docker.sock
```

**Risk:** Mounting the Docker socket into a container gives that container full root-level access to the host's Docker daemon. A compromised scanning tool image could escape the container and control the host.  
**Fix:** Use Trivy in rootless mode with a pre-pulled image tarball, or run Trivy as a native binary on the Jenkins agent rather than as a Docker-in-Docker container.

---

### H-5 · ECR Repository Uses Mutable Image Tags
**File:** `terraform/ecr.tf`, line 3

```hcl
image_tag_mutability = "MUTABLE"
```

**Risk:** The `latest` tag can be silently overwritten. A supply-chain attack or accidental push can replace what is deployed without any audit trail.  
**Fix:**
```hcl
image_tag_mutability = "IMMUTABLE"
```
Use build-number-tagged images (`IMAGE_TAG = "${BUILD_NUMBER}"`) for all deployments — which your Jenkinsfile already does. Only `latest` needs this protection.

---

### H-6 · ECS Tasks Assigned Public IPs Without a Load Balancer
**File:** `terraform/ecs.tf`, line 127

```hcl
assign_public_ip = true
```

**Risk:** Each ECS Fargate task gets a direct public IP address. Without a load balancer or WAF in front, the container is directly reachable from the internet.  
**Fix:** Set `assign_public_ip = false`. Place tasks in private subnets, and route traffic through an ALB (which is already defined but commented out). Uncomment and complete the ALB resources in `ecs.tf`.

---

### H-7 · Overly Broad IAM Permissions (`ecs:*`, `ecr:*`, `elasticloadbalancing:*`)
**File:** `devsecops-policy.json`, lines 47–67

```json
"Action": ["ecs:*"],
"Resource": "*"

"Action": ["ecr:*"],
"Resource": "*"

"Action": ["elasticloadbalancing:*"],
"Resource": "*"
```

**Risk:** Violates the principle of least privilege. The CI/CD role can delete clusters, deregister task definitions, delete ECR repositories, or destroy load balancers — far beyond what a deployment needs.  
**Fix:** Scope to specific actions and resource ARNs:
```json
"Action": [
  "ecs:UpdateService",
  "ecs:DescribeServices",
  "ecs:RegisterTaskDefinition",
  "ecs:DeregisterTaskDefinition"
],
"Resource": "arn:aws:ecs:ap-south-1:395069634073:*"
```

---

## 🟡 MEDIUM

---

### M-1 · Incorrect Dockerfile Health Check
**File:** `app/Dockerfile`, lines 33–34

```dockerfile
HEALTHCHECK CMD node --version || exit 1
```

**Risk:** This checks whether Node.js is installed, not whether the application is actually running and serving requests. A crashed app with Node still present will appear healthy.  
**Fix:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:3000/health || exit 1
```
(Use `wget` since `curl` is not installed in Alpine by default without extra packages.)

---

### M-2 · `npm audit fix --force` in Production Dockerfile
**File:** `app/Dockerfile`, line 14

```dockerfile
RUN npm ci --only=production && \
    npm audit fix --force
```

**Risk:** `--force` can silently upgrade packages to semver-breaking major versions, introducing regressions. This runs at every image build, making builds non-reproducible.  
**Fix:** Remove `npm audit fix --force` from the Dockerfile. Address vulnerabilities explicitly in `package.json`. Run `npm audit` in CI as a reporting step (already done in the pipeline).

---

### M-3 · SonarQube Token Written to a File on Disk
**File:** `Jenkinsfile`, lines 144–146

```bat
echo sonar.login=%SONAR_TOKEN% >> sonar-project.properties
```

**Risk:** The SonarQube token is written in plaintext to `sonar-project.properties` inside the workspace. If this file is accidentally committed (it's not in `.gitignore`), the token is exposed. It also appears in the Jenkins build log.  
**Fix:** Pass the token via environment variable directly to the scanner rather than writing it to a properties file:
```bat
npx sonarqube-scanner -Dsonar.login=%SONAR_TOKEN%
```
Add `app/sonar-project.properties` to `.gitignore`.

---

### M-4 · GitLab CI File Has Syntax Errors and a Hardcoded Placeholder URL
**File:** `.gitlab-ci.yml`

Three issues:
1. **Duplicate `stages:` block** — defined at lines 1 and 40. Only the second one will take effect, so the first `build`/`test`/`code_scan`/`container_scan` job ordering is silently ignored.
2. **Stage name mismatch** — `code_scan:` job (line 25) references `stage: scan` but the first `stages:` list uses `code_scan`. The job will be skipped silently.
3. **Hardcoded ZAP target** — `zap_scan` job uses `http://your_app_url:port` — a placeholder never substituted.

**Fix:** Consolidate to a single `stages:` block, fix the stage name references, and use a CI variable for the target URL:
```yaml
- zap-baseline.py -t $APP_URL -r zap-report.html
```

---

### M-5 · CloudWatch Log Retention Too Short
**File:** `terraform/ecs.tf`, line 3

```hcl
retention_in_days = 7
```

**Risk:** 7 days may be insufficient for security incident investigation, audit trails, or compliance requirements. A breach may not be discovered within that window.  
**Fix:** Set to at least 30–90 days for production. For compliance (PCI-DSS, SOC2), 365 days is typical.

---

### M-6 · No Private Subnet NAT Gateway Defined
**File:** `terraform/vpc.tf`

Private subnets are defined but there is no NAT Gateway resource. If tasks are moved to private subnets (which they should be per H-6), they will have no outbound internet access — they won't be able to pull ECR images or send CloudWatch logs.  
**Fix:** Add a NAT Gateway in the public subnet and a route from private subnets:
```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}
```

---

## 🔵 LOW / INFO

---

### L-1 · Terraform State Files Committed to Git
**Files:** `terraform/terraform.tfstate`, `terraform/terraform.tfstate.backup`

The `.gitignore` has `*.tfstate` at the root level, but the files exist under `terraform/` — suggesting they were committed before the ignore rule was added or the glob didn't match.  
**Risk:** State files can contain sensitive output values and resource metadata. Low risk for this project, but dangerous habit.  
**Fix:** Verify these are truly gitignored (`git ls-files terraform/*.tfstate`). Use remote state (S3 + DynamoDB locking) instead.

---

### L-2 · `body-parser` Deprecated — Use Express Built-In
**File:** `app/index.js`, lines 2, 5

```js
const bodyParser = require("body-parser");
app.use(bodyParser.json());
```

Express 4.16+ includes `express.json()` natively. `body-parser` is a redundant dependency.  
**Fix:**
```js
app.use(express.json());
```
Remove `body-parser` from `package.json`.

---

### L-3 · No HTTP Security Headers on Express App
**File:** `app/index.js`

The app has no security headers (`X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`, etc.).  
**Fix:** Add `helmet`:
```js
const helmet = require("helmet");
app.use(helmet());
```

---

### L-4 · Trivy Cache Database Committed to Git
**Directory:** `trivy-cache/`

Binary database files (`trivy.db`, `fanal.db`) are committed. These are large, frequently updated binary blobs that don't belong in source control.  
**Fix:** Add to `.gitignore`:
```
trivy-cache/
```
Then remove from git history: `git rm -r --cached trivy-cache/`

---

### L-5 · `app/index.test.js` Is Empty
**File:** `app/index.test.js` (root-level, 1 line, empty)

The actual tests are in `app/test/index.test.js`. The empty root-level file is dead code that adds confusion.  
**Fix:** Delete `app/index.test.js`.

---

## Recommended Priority Order for Fixes

1. **C-2** — Enable real Quality Gate enforcement (the entire SAST loop is broken without this)
2. **C-3** — Remove `|| echo` suppression from Trivy, npm audit, and ZAP (security scans must fail the build)
3. **C-4** — Guard or remove `/toggle-health` endpoint
4. **C-1** — Rotate Jenkins admin password, remove from source
5. **H-1** — Reconcile the two AWS account IDs and remove hardcoded values
6. **H-3** — Enable SonarQube authentication
7. **H-5** — Set ECR to IMMUTABLE tags
8. **H-6** — Disable public IP on ECS tasks; enable ALB
9. **H-7** — Scope IAM actions to least privilege
10. **M-1** — Fix Dockerfile HEALTHCHECK to actually test the app

---

*Report generated by automated code review. All file paths, line numbers, and code snippets verified against actual source files.*
