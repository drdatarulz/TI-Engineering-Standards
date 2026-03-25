# Environments & Deployment Pipeline Standards

## Philosophy

- Every project has four environments: **Local**, **Dev**, **Staging**, and **Production**
- Infrastructure is defined as code (Bicep) — never hand-configured in the Azure portal
- Docker images are **built once and promoted** — never rebuilt between environments
- Automated gates enforce quality at every promotion boundary
- Personal/solo projects may deploy directly to Production — this exception must be declared in the project's `CLAUDE.md`

---

## Environment Definitions

| Environment | Purpose | Deploy Trigger | Infrastructure |
|-------------|---------|---------------|----------------|
| Local | Developer workstation — unit + integration tests, manual exploration | Manual — developer runs locally | Docker (Testcontainers), optional Azure services (e.g. authentication) |
| Dev | Integration target, automated test validation | Auto — every merge to `main` | Azure resource group: `{project}-dev` |
| Staging | Pre-production validation, manual QA | Manual promotion from Dev | Azure resource group: `{project}-staging` |
| Production | Live system | Manual promotion with approval gate | Azure resource group: `{project}-prod` |

Local is not a pipeline environment — it has no deployment trigger and no promotion gate. It exists so developers can run and test the application without requiring full Azure infrastructure. Testcontainers provides the database locally. Some Azure dependencies such as authentication may still be used locally — the auth bypass (`Authentication:UseDevBypass`) is available for developers who prefer to skip Azure AD during local development, but is not required.

---

## Infrastructure as Code (Bicep)

Every project maintains Bicep templates that fully describe its Azure infrastructure.

### Structure

```
infra/
  main.bicep              # Entry point — accepts environment parameter
  modules/
    app.bicep             # Container App or App Service
    database.bicep        # Azure SQL
    storage.bicep         # Blob / Queue storage (if needed)
    keyvault.bicep        # Key Vault
  parameters/
    dev.bicepparam        # Dev parameter values
    staging.bicepparam    # Staging parameter values
    prod.bicepparam       # Production parameter values
```

### Conventions

- `main.bicep` accepts an `environment` parameter (`dev` | `staging` | `prod`)
- All resource names are derived from the environment parameter: `{project}-{environment}-{resource}`
- Secrets are never stored in parameter files — they are seeded into Key Vault separately
- Running `az deployment group create` against a resource group is idempotent — safe to re-run

### Bootstrap a New Environment

To stand up a new environment from scratch:

```bash
# Create resource group
az group create --name {project}-{environment} --location eastus

# Deploy infrastructure
az deployment group create \
  --resource-group {project}-{environment} \
  --template-file infra/main.bicep \
  --parameters infra/parameters/{environment}.bicepparam
```

This is the only step required to provision a new environment. The pipeline handles everything after this.

---

## Health Endpoint (Required)

Every project **must** expose a `/health` endpoint on the API. This is a hard requirement — smoke tests depend on it.

```csharp
app.MapHealthChecks("/health");
```

Add database and dependency health checks as appropriate. The endpoint must return HTTP 200 when the application is healthy.

---

## Dev Auth Bypass (Required for Non-Production)

Local, Dev, and Staging environments must support an auth bypass for automated Playwright tests and local development convenience. Production never uses the bypass.

Controlled via configuration (see `standards/configuration.md`):

```json
// appsettings.Development.json / appsettings.Staging.json
{
  "Authentication": {
    "UseDevBypass": true
  }
}
```

```csharp
// Program.cs
if (builder.Configuration.GetValue<bool>("Authentication:UseDevBypass"))
{
    // Register dev bypass auth handler
}
else
{
    // Register Azure AD auth handler
}
```

The bypass must never be enabled in Production. Bicep parameter files for `prod` must set this to `false` via environment variable.

---

## Docker Image Tagging

Images are built once per commit and promoted by retagging — never rebuilt.

| Stage | Tag Format |
|-------|-----------|
| Built on merge to main | `{registry}/{image}:{sha}-dev` |
| Promoted to Staging | `{registry}/{image}:{sha}-staging` |
| Promoted to Production | `{registry}/{image}:{sha}-prod` |

The commit SHA is the source of truth — it ties every deployed image back to an exact commit.

---

## GitHub Environments (Promotion Mechanism)

Promotions are managed using **GitHub Environments** — not `workflow_dispatch` inputs. This gives a click-to-approve UI in GitHub without requiring anyone to type a SHA or manually trigger a workflow.

### Setup (one-time per project)

In the GitHub repo under **Settings → Environments**, create three environments:

| Environment | Protection Rules |
|-------------|-----------------|
| `dev` | None — deploys automatically |
| `staging` | Required reviewers: project owner |
| `production` | Required reviewers: project owner + approval gate |

### How it works in practice

The deploy pipeline is a single workflow with sequential jobs, each targeting a GitHub Environment:

```yaml
jobs:
  deploy-dev:
    environment: dev
    # runs automatically on merge to main

  deploy-staging:
    environment: staging        # pauses here — requires approval
    needs: deploy-dev
    if: success()

  deploy-production:
    environment: production     # pauses here — requires approval
    needs: deploy-staging
    if: success()
```

When `deploy-dev` completes (smoke passes), GitHub pauses at `deploy-staging` and sends a notification to required reviewers. The reviewer clicks **Approve** in the GitHub UI. The pipeline resumes, retags the image, and deploys to Staging. Same pattern for Production.

**No SHA input required.** The SHA is already embedded in the image tag from the Dev deploy — the pipeline carries it forward automatically.

### Deployment history

GitHub Environments also provide a deployment history per environment — you can see exactly which SHA is running in each environment at any time from the repo's main page.

### Superseded runs

When you approve a run for Staging or Production, **cancel any older runs** that are still waiting approval for that environment. This keeps the Actions tab unambiguous — only one run should ever be in a "waiting" state per environment at a time. A waiting run that was superseded by a newer promotion is noise and should be cleaned up immediately.

---

## CI/CD Pipeline Structure

### On PR to main (CI)

Two parallel jobs:

```
Job 1: Restore → Build → Unit tests → Integration tests
Job 2: Docker Compose up → Health wait → Playwright UI tests → Docker Compose down
→ Both pass → ✅ Merge allowed
```

Unit, integration, and Playwright tests must all pass. Playwright runs against a Docker Compose stack (API + Client + SQL Server + seed data) with auth bypass enabled. See `standards/testing.md` for test tier details.

### On merge to main (CD → Dev)

```
Build Docker images (tagged {sha}-dev)
  → Push to registry
  → az deployment group create (idempotent Bicep)
  → Run migrations (Migrator container)
  → Deploy to {project}-dev resource group
  → Smoke tests (HTTP health check)
  → ✅ Dev validated — eligible for Staging promotion
```

### Promote to Staging (manual)

```
Retag image ({sha}-dev → {sha}-staging)
  → az deployment group create (idempotent Bicep)
  → Run migrations
  → Deploy to {project}-staging resource group
  → Smoke tests
  → ✅ Staging validated — eligible for Production promotion
```

### Promote to Production (manual + approval gate)

```
Approval gate
  → Retag image ({sha}-staging → {sha}-prod)
  → az deployment group create (idempotent Bicep)
  → Run migrations
  → Deploy to {project}-prod resource group
  → Health check only (no smoke suite)
```

---

## Post-Deploy Gate Details

### Smoke Tests

Smoke tests run immediately after every deploy to Dev and Staging. They are lightweight HTTP checks — not a test project, just pipeline steps.

**What they check:**
- `/health` returns HTTP 200
- API responds within an acceptable timeout

**If smoke fails:** Pipeline stops. Playwright does not run. The deploy is considered broken.

```yaml
# Example GitHub Actions smoke step
- name: Smoke test
  run: |
    for i in {1..10}; do
      status=$(curl -s -o /dev/null -w "%{http_code}" ${{ env.APP_URL }}/health)
      if [ "$status" = "200" ]; then exit 0; fi
      sleep 5
    done
    echo "Smoke test failed" && exit 1
```

### Playwright Tests (CI Gate)

Playwright tests run in CI on every PR, not post-deploy. They run against a Docker Compose stack that includes the API, Client, SQL Server, database migrations, and seed data — all with auth bypass enabled.

**Required environment variables for the CI step:**

| Variable | Value |
|----------|-------|
| `FORMIT_BASE_URL` | `http://localhost:{client-port}` (Docker Compose client port) |

**If Playwright fails:** The PR is blocked from merging. Playwright failures are a blocking CI gate.

No Playwright tests run post-deploy or against Production. Post-deploy validation is limited to smoke tests (health checks).

---

## Conformance Checklist

Use this checklist when applying this standard to an existing project or auditing a project for compliance.

### Infrastructure
- [ ] `infra/main.bicep` exists and accepts an `environment` parameter
- [ ] Parameter files exist for `dev`, `staging`, and `prod`
- [ ] Resource groups exist in Azure: `{project}-dev`, `{project}-staging`, `{project}-prod`
- [ ] Bicep deployment is idempotent (safe to re-run)

### Application
- [ ] `/health` endpoint is implemented and returns 200
- [ ] Auth bypass is implemented and controlled by `Authentication:UseDevBypass`
- [ ] Auth bypass is disabled in prod parameter file

### GitHub Environments
- [ ] `dev`, `staging`, and `production` environments are configured in GitHub repo Settings
- [ ] `staging` has required reviewers set
- [ ] `production` has required reviewers set
- [ ] Deploy workflow jobs target the correct GitHub Environment (`environment: dev/staging/production`)

### Pipeline
- [ ] `ci.yml` runs unit + integration tests on every PR (no Category!=Integration filter)
- [ ] `ci.yml` runs Playwright UI tests on every PR via Docker Compose (blocking gate)
- [ ] `deploy.yml` deploys to Dev on merge to main
- [ ] Post-deploy smoke step exists for Dev
- [ ] Staging promotion is manual and includes smoke gate
- [ ] Production promotion requires approval gate
- [ ] Images are built once and retagged — never rebuilt

### Exceptions
- [ ] If this is a personal/solo project with direct-to-prod deploys, this is declared in `CLAUDE.md`
