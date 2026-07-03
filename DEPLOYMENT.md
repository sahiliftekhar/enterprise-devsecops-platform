# Deployment Playbook — Secure DevSecOps Pipeline

This guide takes you from zero to a fully deployed application in three phases:

- **Phase 1** — Local stack (Docker Compose): app + SonarQube + PostgreSQL
- **Phase 2** — AWS infrastructure (Terraform): VPC, ECR, ECS Fargate
- **Phase 3** — Jenkins CI/CD pipeline: build → scan → push → deploy

Run the phases in order. Phase 2 and 3 depend on Phase 1 being healthy.

---

## Prerequisites checklist

| Tool | Minimum version | Check command |
|------|----------------|---------------|
| Docker Desktop | 24+ | `docker --version` |
| Docker Compose | 2+ | `docker compose version` |
| Node.js | 18+ | `node --version` |
| AWS CLI | 2+ | `aws --version` |
| Terraform | 1.8+ | `terraform --version` |
| Jenkins | LTS | accessible at http://localhost:8080 |

Your confirmed ready: Docker, AWS CLI, Jenkins.

---

## Phase 1 — Local Stack (Docker Compose)

### Step 1.1 — Set required environment variables

The app needs `ADMIN_API_KEY` to protect the `/toggle-health` endpoint.
Copy the example file and fill it in:

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops
copy .env.example .env
```

Edit `.env` and set:

```
ADMIN_API_KEY=<generate a strong random string — minimum 32 characters>
```

Generate a good key (run in PowerShell):
```powershell
[System.Web.Security.Membership]::GeneratePassword(32, 4)
# OR use:
-join ((65..90)+(97..122)+(48..57) | Get-Random -Count 32 | % {[char]$_})
```

### Step 1.2 — Fix the system limit for SonarQube (Windows/Docker Desktop)

SonarQube's Elasticsearch requires `vm.max_map_count >= 262144`.
On Docker Desktop for Windows this is set inside the WSL2 VM:

```powershell
# Run in PowerShell as Administrator
wsl -d docker-desktop
sysctl -w vm.max_map_count=262144
exit
```

To make it permanent, add to `%USERPROFILE%\.wslconfig`:
```
[wsl2]
kernelCommandLine = sysctl.vm.max_map_count=262144
```

### Step 1.3 — Build and start the full local stack

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops

REM Start PostgreSQL and SonarQube first
docker compose up -d sonar-db sonarqube

REM Wait ~2 minutes for SonarQube to initialise, then check health:
curl http://localhost:9000/api/system/health
REM Expected: {"health":"GREEN","causes":[]}

REM Start the application
docker compose up -d app
```

### Step 1.4 — Verify all services are healthy

```cmd
docker compose ps
```

Expected output:
```
NAME             STATUS
devsecops-app    running (healthy)
sonarqube        running
sonar-db         running (healthy)
```

### Step 1.5 — Smoke-test the application

```cmd
REM Root endpoint
curl http://localhost:3000/
REM Expected: {"message":"Hello from DevSecOps App","version":"1.0.0","timestamp":"..."}

REM Health endpoint
curl http://localhost:3000/health
REM Expected: {"status":"healthy","uptime":...,"timestamp":"..."}

REM Security headers check
curl -I http://localhost:3000/
REM Look for: x-frame-options, content-security-policy, x-content-type-options
```

### Step 1.6 — Configure SonarQube

Open http://localhost:9000 in a browser.

1. Log in: **admin / admin**
2. Change the password when prompted (use something strong)
3. Go to **My Account → Security → Generate Token**
4. Name it `jenkins-token`, click **Generate**
5. **Copy the token** — you will need it in Phase 3
6. Go to **Administration → Projects → Create Project → Manually**
   - Project key: `DevSecOps-Pipeline-Project`
   - Display name: `DevSecOps Pipeline Project`
   - Click **Set up**

### Step 1.7 — Fix sonar-project.properties for Node.js

The file currently has Java settings. Update it for your Node.js app:

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops
```

Open `sonar-project.properties` and replace its contents with:

```properties
sonar.projectKey=DevSecOps-Pipeline-Project
sonar.projectName=DevSecOps Pipeline Project
sonar.sources=app
sonar.exclusions=**/node_modules/**,**/coverage/**,**/*.test.js
sonar.javascript.lcov.reportPaths=app/coverage/lcov.info
sonar.host.url=http://localhost:9000
sonar.sourceEncoding=UTF-8
```

### Step 1.8 — Run local tests and SonarQube analysis

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops\app

REM Install dependencies
npm ci

REM Run tests with coverage (must pass before analysis)
set ADMIN_API_KEY=your-key-here
npm test

REM Run SonarQube analysis
npx sonarqube-scanner ^
  -Dsonar.projectKey=DevSecOps-Pipeline-Project ^
  -Dsonar.host.url=http://localhost:9000 ^
  -Dsonar.token=YOUR_SONAR_TOKEN
```

Open http://localhost:9000/dashboard?id=DevSecOps-Pipeline-Project to view the results.

**Phase 1 complete. Local stack is running.**

---

## Phase 2 — AWS Infrastructure (Terraform)

### Step 2.1 — Verify AWS credentials

```cmd
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXX",
    "Account": "395069634073",
    "Arn": "arn:aws:iam::395069634073:user/your-username"
}
```

If this fails, run `aws configure` and enter your Access Key ID, Secret Access Key, region `ap-south-1`, and output format `json`.

### Step 2.2 — Attach the least-privilege IAM policy

Attach `devsecops-policy.json` to your IAM user/role so Terraform has the permissions it needs:

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops

REM Create the managed policy
aws iam create-policy ^
  --policy-name DevSecOpsDeployPolicy ^
  --policy-document file://devsecops-policy.json ^
  --region ap-south-1

REM Attach it to your IAM user (replace YOUR_USERNAME)
aws iam attach-user-policy ^
  --user-name YOUR_USERNAME ^
  --policy-arn arn:aws:iam::395069634073:policy/DevSecOpsDeployPolicy
```

### Step 2.3 — Initialise Terraform

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops\terraform

terraform init
```

Expected: `Terraform has been successfully initialized!`

> **Note on remote state:** For production, add an S3 backend to `main.tf` before running init.
> The state file must NEVER be committed to git (already excluded by `.gitignore`).

### Step 2.4 — Preview the plan

```cmd
terraform plan ^
  -var="aws_account_id=395069634073" ^
  -var="aws_region=ap-south-1" ^
  -var="environment=dev" ^
  -var="image_tag=build-1" ^
  -var="ecs_task_execution_role_arn=PLACEHOLDER_WILL_BE_CREATED" ^
  -var="ecr_repo_url=PLACEHOLDER_WILL_BE_CREATED" ^
  -var="app_subnet_ids=[\"placeholder\"]" ^
  -var="app_security_group_id=placeholder" ^
  -out=tfplan
```

Review the plan. You should see ~15 resources to create.

### Step 2.5 — Apply in two passes (bootstrapping IAM first)

Because the ECS task definition needs the IAM role ARN and ECR URL — which don't exist yet — apply in two passes:

**Pass 1: Create IAM roles and ECR repo**

```cmd
terraform apply ^
  -target=aws_iam_role.ecs_task_execution_role ^
  -target=aws_iam_role_policy_attachment.ecs_task_execution_attachment ^
  -target=aws_iam_role.ecs_task_role ^
  -target=aws_ecr_repository.app ^
  -target=aws_ecr_lifecycle_policy.app ^
  -var="aws_account_id=395069634073" ^
  -var="aws_region=ap-south-1" ^
  -var="environment=dev" ^
  -var="image_tag=build-1" ^
  -var="ecs_task_execution_role_arn=placeholder" ^
  -var="ecr_repo_url=placeholder" ^
  -var="app_subnet_ids=[\"placeholder\"]" ^
  -var="app_security_group_id=placeholder" ^
  -auto-approve
```

**Capture the outputs from Pass 1:**

```cmd
REM Get the IAM role ARN
aws iam get-role ^
  --role-name devsecops-app-ecs-task-execution-role ^
  --query "Role.Arn" --output text

REM Get the ECR repo URL
aws ecr describe-repositories ^
  --repository-names devsecops-app ^
  --region ap-south-1 ^
  --query "repositories[0].repositoryUri" --output text
```

Save these two values — you'll need them below.

**Pass 2: Create everything else**

```cmd
terraform apply ^
  -var="aws_account_id=395069634073" ^
  -var="aws_region=ap-south-1" ^
  -var="environment=dev" ^
  -var="image_tag=build-1" ^
  -var="ecs_task_execution_role_arn=<ROLE_ARN_FROM_PASS_1>" ^
  -var="ecr_repo_url=<ECR_URL_FROM_PASS_1>" ^
  -var="app_subnet_ids=[\"$(terraform output -raw public_subnet_ids | head -1)\"]" ^
  -var="app_security_group_id=$(terraform output -raw ecs_security_group_id)" ^
  -auto-approve
```

### Step 2.6 — Capture Terraform outputs

```cmd
terraform output
```

Note these values — you'll use them in Phase 3:

| Output | Example value |
|--------|--------------|
| `ecr_repository_url` | `395069634073.dkr.ecr.ap-south-1.amazonaws.com/devsecops-app` |
| `ecs_cluster_name` | `devsecops-app-cluster` |
| `public_subnet_ids` | `["subnet-xxxxxxxxx", "subnet-yyyyyyyyy"]` |
| `ecs_security_group_id` | `sg-xxxxxxxxxxxxxxxxx` |

### Step 2.7 — Push the first image manually (bootstrap)

Before Jenkins runs, push an initial image so the ECS service has something to start:

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops

REM Authenticate Docker to ECR
aws ecr get-login-password --region ap-south-1 ^
  | docker login --username AWS --password-stdin ^
    395069634073.dkr.ecr.ap-south-1.amazonaws.com

REM Build the image
docker build -t devsecops-app:build-1 ./app

REM Tag and push
docker tag devsecops-app:build-1 ^
  395069634073.dkr.ecr.ap-south-1.amazonaws.com/devsecops-app:build-1

docker push ^
  395069634073.dkr.ecr.ap-south-1.amazonaws.com/devsecops-app:build-1
```

### Step 2.8 — Verify ECS cluster and service

```cmd
REM Check cluster
aws ecs describe-clusters ^
  --clusters devsecops-app-cluster ^
  --region ap-south-1 ^
  --query "clusters[0].{Name:clusterName,Status:status,Tasks:runningTasksCount}"

REM Check service
aws ecs describe-services ^
  --cluster devsecops-app-cluster ^
  --services devsecops-app-service ^
  --region ap-south-1 ^
  --query "services[0].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount}"
```

Expected: `Status: ACTIVE`, `Running: 1`, `Desired: 1`.

**Phase 2 complete. AWS infrastructure is provisioned.**

---

## Phase 3 — Jenkins Pipeline Setup & Execution

### Step 3.1 — Start Jenkins (if not already running)

```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops

REM Generate a strong admin password first (PowerShell):
REM $pass = -join ((65..90)+(97..122)+(48..57) | Get-Random -Count 32 | % {[char]$_})
REM Write-Host $pass

docker run -d ^
  --name jenkins ^
  -p 8080:8080 ^
  -p 50000:50000 ^
  -e JENKINS_ADMIN_USER=admin ^
  -e JENKINS_ADMIN_PASSWORD=YOUR_STRONG_PASSWORD ^
  -v jenkins_home:/var/jenkins_home ^
  -v /var/run/docker.sock:/var/run/docker.sock ^
  jenkins/jenkins:lts
```

Wait ~90 seconds for Jenkins to start, then open http://localhost:8080.

### Step 3.2 — Install required Jenkins plugins

Go to **Manage Jenkins → Plugins → Available plugins** and install:

- **Pipeline** (usually pre-installed)
- **NodeJS Plugin** — allows `tools { nodejs 'Node-18' }` in Jenkinsfile
- **Amazon Web Services SDK / AWS Credentials Plugin** — for `AmazonWebServicesCredentialsBinding`
- **Docker Pipeline** — for Docker steps
- **Timestamper** — for `timestamps()` option

Click **Install** and check **Restart after installation**.

### Step 3.3 — Configure the Node.js tool

Go to **Manage Jenkins → Tools → NodeJS installations → Add NodeJS**:

- **Name:** `Node-18` ← must match exactly what's in the Jenkinsfile
- **Version:** NodeJS 18.x (latest LTS)
- Click **Save**

### Step 3.4 — Add credentials

Go to **Manage Jenkins → Credentials → System → Global credentials → Add Credential**:

**Credential 1 — AWS:**
- Kind: `AWS Credentials`
- ID: `aws-ecr-prod` ← must match exactly
- Access Key ID: your AWS Access Key
- Secret Access Key: your AWS Secret Key
- Description: `AWS ECR/ECS production credentials`

**Credential 2 — SonarQube token:**
- Kind: `Secret text`
- ID: `sonarqube-token` ← must match exactly
- Secret: the token you generated in Step 1.6
- Description: `SonarQube user token`

### Step 3.5 — Create the Jenkins pipeline

Go to **New Item** → enter name `secure-devsecops-pipeline` → select **Pipeline** → OK.

In the pipeline configuration:

**General:**
- Check **Discard old builds** → Max # of builds to keep: `10`

**Build Triggers:**
- Check **Poll SCM** → Schedule: `H/5 * * * *` (polls every 5 min)
- OR check **GitHub/GitLab hook trigger** if your repo is hosted there

**Pipeline:**
- Definition: `Pipeline script from SCM`
- SCM: `Git`
- Repository URL: your git repo URL (or `file:///D:/DevSecOps-8th/secure-cicd-devsecops` for local)
- Branch: `*/main`
- Script Path: `Jenkinsfile`

Click **Save**.

### Step 3.6 — Verify environment variables match your AWS setup

Open `D:\DevSecOps-8th\secure-cicd-devsecops\Jenkinsfile` and confirm these values at the top match your actual AWS account:

```groovy
AWS_ACCOUNT_ID = '395069634073'    // Your 12-digit account ID
AWS_REGION     = 'ap-south-1'     // Your region
ECS_CLUSTER    = 'devsecops-app-cluster'
ECS_SERVICE    = 'devsecops-app-service'
ECR_REPO_NAME  = 'devsecops-app'
```

If any differ from the Terraform outputs in Step 2.6, update the Jenkinsfile before running.

### Step 3.7 — Run the pipeline for the first time

Go to your pipeline → click **Build Now**.

Watch the **Stage View** — each stage turns green as it passes:

```
Cleanup → Verify AWS → Prepare → Build Image → Trivy Scan
  → Start SonarQube → Wait SQ → Install Deps → npm audit
  → Tests → SonarQube Analysis → Quality Gate ✓
  → Push ECR → Deploy ECS → Health Check → ZAP DAST
  → Secrets Scan → Final Verification
```

### Step 3.8 — Monitor the pipeline

Click **Console Output** to see live logs.

Key things to watch for:

| Stage | What success looks like |
|-------|------------------------|
| Trivy Scan | `0 CRITICAL vulnerabilities found` |
| npm audit | `found 0 vulnerabilities` |
| Tests | `33 passed, 0 failed` |
| Quality Gate | `Quality Gate PASSED` |
| Push ECR | `The push refers to repository [...] build-1: digest: sha256:...` |
| Deploy ECS | `ECS service is stable` |
| Health Check | `Health check PASSED` |
| Secrets Scan | `Secrets scan PASSED - no verified secrets found` |

### Step 3.9 — View security reports

After the pipeline completes:
1. Go to the build page → click **Artifacts**
2. Download `security-reports/` — contains:
   - `trivy-container-report.json` — container vulnerabilities
   - `trivy-container-report.html` — human-readable Trivy report
   - `npm-audit.json` — dependency vulnerabilities
   - `trufflehog-secrets.json` — secrets scan results
   - `quality-gate.json` — SonarQube quality gate result

### Step 3.10 — Verify the deployed application on AWS

```cmd
REM Get the task's private IP (if no ALB yet)
aws ecs list-tasks ^
  --cluster devsecops-app-cluster ^
  --region ap-south-1 ^
  --query "taskArns[0]" --output text

aws ecs describe-tasks ^
  --cluster devsecops-app-cluster ^
  --tasks <TASK_ARN_FROM_ABOVE> ^
  --region ap-south-1 ^
  --query "tasks[0].containers[0].networkInterfaces[0].privateIpv4Address" ^
  --output text
```

Then from a machine in the same VPC (or a bastion host):
```cmd
curl http://<PRIVATE_IP>:3000/health
```

**Phase 3 complete. The full DevSecOps pipeline is running.**

---

## Troubleshooting

### SonarQube won't start
```cmd
REM Check logs
docker compose logs sonarqube

REM Most common cause: vm.max_map_count too low
wsl -d docker-desktop sysctl vm.max_map_count
REM Must be >= 262144 — if not, see Step 1.2
```

### Quality Gate stuck on PENDING
- SonarQube analysis hasn't finished yet — wait 30–60 seconds
- Check SonarQube logs: `docker compose logs sonarqube`
- Ensure the `sonarqube-token` credential in Jenkins is correct

### Trivy fails with "CRITICAL CVEs found"
```cmd
REM Run Trivy locally to see details
docker run --rm aquasec/trivy:latest image devsecops-ci-app:latest ^
  --severity CRITICAL --format table

REM Update the Node base image in app/Dockerfile:
REM FROM node:18-alpine  →  FROM node:20-alpine
REM Then rebuild and re-run
```

### ECR push fails with "no basic auth credentials"
```cmd
REM Re-authenticate (token expires after 12 hours)
aws ecr get-login-password --region ap-south-1 ^
  | docker login --username AWS --password-stdin ^
    395069634073.dkr.ecr.ap-south-1.amazonaws.com
```

### ECS service stays in PENDING (tasks not starting)
```cmd
REM Check stopped task failure reason
aws ecs describe-services ^
  --cluster devsecops-app-cluster ^
  --services devsecops-app-service ^
  --region ap-south-1 ^
  --query "services[0].events[0:5]"

REM Common causes:
REM 1. Image tag doesn't exist in ECR → push the image first (Step 2.7)
REM 2. ECS task role doesn't have ECR pull permissions → check IAM
REM 3. Security group blocks outbound → check ecs_tasks SG egress rules
```

### Jenkins "aws: command not found"
The Jenkins container needs the AWS CLI. Either:
```cmd
REM Install inside the running container
docker exec -u root jenkins apt-get update
docker exec -u root jenkins apt-get install -y awscli
```
Or rebuild the Jenkins image with AWS CLI pre-installed.

### npm audit fails with vulnerabilities
```cmd
cd D:\DevSecOps-8th\secure-cicd-devsecops\app
npm audit
npm audit fix           # Auto-fix safe upgrades only (no --force)
npm audit               # Re-check after fix
```

---

## Quick reference — key URLs and values

| Item | Value |
|------|-------|
| App (local) | http://localhost:3000 |
| SonarQube (local) | http://localhost:9000 |
| Jenkins | http://localhost:8080 |
| AWS Region | ap-south-1 |
| AWS Account | 395069634073 |
| ECR Repository | `395069634073.dkr.ecr.ap-south-1.amazonaws.com/devsecops-app` |
| ECS Cluster | `devsecops-app-cluster` |
| ECS Service | `devsecops-app-service` |
| CloudWatch Logs | `/ecs/devsecops-app` |

---

## Tear-down (when done)

```cmd
REM Stop local stack
cd D:\DevSecOps-8th\secure-cicd-devsecops
docker compose down -v

REM Stop Jenkins
docker stop jenkins && docker rm jenkins

REM Destroy AWS infrastructure (saves cost)
cd terraform
terraform destroy ^
  -var="aws_account_id=395069634073" ^
  -var="aws_region=ap-south-1" ^
  -var="environment=dev" ^
  -var="image_tag=build-1" ^
  -var="ecs_task_execution_role_arn=<ROLE_ARN>" ^
  -var="ecr_repo_url=<ECR_URL>" ^
  -var="app_subnet_ids=[\"placeholder\"]" ^
  -var="app_security_group_id=placeholder" ^
  -auto-approve
```
