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
| Local | Developer workstation — unit, contract + integration tests, manual exploration | Manual — developer runs locally | Docker (Testcontainers), optional Azure services (e.g. authentication) |
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

## Dev Auth Bypass

Every project must implement a dev auth bypass (`Authentication:UseDevBypass`) so that local development and Playwright CI tests can run without real Azure AD infrastructure. However, **the bypass must default to OFF in every environment** — local, dev, staging, and production alike.

### Default-OFF Principle

Auth bypass is a security-sensitive toggle. The safe state is **disabled**. Enabling it must be an explicit, intentional act by the developer — never an infrastructure default.

| Location | `UseDevBypass` | Rationale |
|----------|---------------|-----------|
| `appsettings.json` (base) | `false` | Safe default — real auth everywhere |
| All Bicep parameter files (`dev`, `staging`, `prod`) | `false` | Deployed environments always use real Azure AD |
| Dockerfile `ARG` defaults | `false` | Container images default to real auth |
| CI/CD workflow env vars | `false` | Build pipelines default to real auth |
| `docker-compose.yml` (local dev) | `true` (explicit override) | Intentional local-only convenience |
| `docker-compose.playwright.yml` (CI overlay) | `true` (explicit override) | Intentional test-only convenience |
| `.env.development` (frontend local dev) | `true` (explicit override) | Intentional local-only convenience |

**Why this matters:** If a deployed environment (Dev, Staging) has bypass enabled, the backend silently ignores real JWT tokens. Users log in with real credentials but the backend discards their identity and resolves every request to the same fixed dev user. This causes data isolation failures that are invisible to the user — they see a real login flow but share a single identity.

### Startup Warning (Required)

When bypass is enabled, the application **must** log a warning at startup so that misconfiguration is immediately visible in logs:

```csharp
if (builder.Configuration.GetValue<bool>("Authentication:UseDevBypass"))
{
    builder.Services.AddAuthentication(DevBypassAuthHandler.SchemeName)
        .AddScheme<AuthenticationSchemeOptions, DevBypassAuthHandler>(
            DevBypassAuthHandler.SchemeName, _ => { });
    Log.Warning("Authentication dev bypass is ENABLED — all requests will authenticate as the dev user. This must NOT be used in staging or production.");
}
else
{
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.Authority = builder.Configuration["Authentication:Authority"] ?? "";
            options.Audience = builder.Configuration["Authentication:Audience"] ?? "";
            options.TokenValidationParameters.ValidateIssuer = true;
        });
}
```

### Where Bypass Is Enabled

Bypass is only turned on via **explicit overrides in local-only files** that are never deployed to Azure:

```yaml
# docker-compose.yml — local dev stack
services:
  api:
    environment:
      Authentication__UseDevBypass: "true"   # Explicit local-only override
```

```yaml
# docker-compose.playwright.yml — CI test overlay
services:
  api:
    environment:
      Authentication__UseDevBypass: "true"   # Explicit test-only override
```

Bicep parameter files, Dockerfiles, and `appsettings.json` must never set this to `true`.

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

### v5 CI requirements (self-hosted runner + merge gate)

Every v5 project **must** have all three of the following. They are provisioned from the
standards repo (`templates/workflows/`), not hand-written per project:

1. **The three test workflows** in `.github/workflows/` — `fast-tests.yml`,
   `integration-tests.yml`, `ui-tests.yml` — all `runs-on: self-hosted`. The auto-sync
   protocol copies these in (skipping any the project already customized).
2. **The merge gate** — `orchestrate-v5` will not merge a PR whose `fast-tests` or
   `integration-tests` checks are red (it polls them before merging). Merges in v5 go through the
   orchestrator, so that is where the gate lives — no branch-protection setup is assumed.
   `ui-tests` is intentionally **not** a required check.
3. **A self-hosted GitHub Actions runner** on the user's box (WSL2/Linux, with Docker
   access), installed **as a service** so it auto-starts on boot and restarts on crash.
   The runner brings the compute (no GitHub minutes billed) and runs Testcontainers /
   Playwright as sibling containers on the host Docker. Runner setup is documented in
   `developer-tools/` (see the runner setup guide).

**These three are test workflows (PR / `workflow_dispatch`), not a build/deploy pipeline** — none
run on push to `main`. A project keeps its existing main-push workflow for build, version-stamp,
frontend build, and deploy (and to feed any `workflow_run`-based CD). Adopting v5 means moving the
*tests* out of that workflow into the three tiers, **not** deleting it: deleting a `ci.yml` that a
`cd.yml` watches via `workflow_run` would break deployment.

Conformance/review checks these via the **Pipeline** section of the Conformance Checklist
below. The trigger model itself lives in `standards/testing.md` → CI/CD Testing Tiers.

### On PR to main (CI)

CI runs on a **self-hosted runner**. Two tiers gate the merge; the UI tier does not:

```
fast-tests.yml         (every PR): Restore → Build → Unit + Contract tests (fakes, no Docker)
integration-tests.yml  (required pre-merge check): Integration tests (Testcontainers, real SQL)
→ Both pass AND branch up to date with main → ✅ Merge allowed
```

The fast tier (Unit + Contract) and integration are **both blocking merge gates**; if either fails, do not merge. The branch must be up to date with `main` before merging so integration re-runs against latest `main`. Playwright is **not** a per-PR gate — it runs at the orchestration boundary via `workflow_dispatch` on the self-hosted runner. See `standards/testing.md` → CI/CD Testing Tiers for the full trigger model.

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

**Skip the deploy on test-only merges (v5).** v5 lands each ticket as **three** PRs
(implementation, integration-tests, ui-tests), so three merges hit `main` per ticket — but only
the **implementation** PR changes app code. The integration-tests and ui-tests PRs touch `tests/**`
only and are **not in the deployed image** (the Dockerfile builds `src/`), so deploying on them is a
pure no-op redeploy. Gate the CD deploy on `src/**` changes so a test-only merge is skipped:

```bash
# first step of the deploy job — bail out cleanly when the merge changed only tests/docs
if git diff --name-only HEAD^ HEAD | grep -qE '^src/'; then
  echo "app code changed — deploying"
else
  echo "test-only merge — skipping deploy"; exit 0
fi
```

This keeps the **one meaningful deploy per ticket** and still deploys migrations (they live under
`src/{Project}.Migrator/`, so they match `^src/`). It is safe because the integration and UI tiers
run on the **self-hosted runner** (Testcontainers / Compose), never against deployed dev — the test
merges never needed a deploy.

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

### Playwright Tests (orchestration boundary, not a PR gate)

Playwright tests run on the **self-hosted runner** via `ui-tests.yml` (`workflow_dispatch`) — fired *scoped* (branch ref + filter) for per-story authoring runs and *unfiltered* for the end-of-batch regression sweep. They run against a Docker Compose stack (API, Client, SQL Server, migrations, seed data) with auth bypass enabled. They are **not** a per-PR gate and do **not** block the merge — UI verification happens at the orchestration boundary. See `standards/testing.md` → CI/CD Testing Tiers.

**Required environment variables for the UI run:**

| Variable | Value |
|----------|-------|
| `{PROJECT}_BASE_URL` | `http://localhost:{client-port}` (Docker Compose client port) |

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
- [ ] Auth bypass defaults to `false` in `appsettings.json` (base config)
- [ ] Auth bypass is `false` in ALL Bicep parameter files (`dev`, `staging`, `prod`)
- [ ] Dockerfile `ARG` for bypass defaults to `false`
- [ ] Startup warning log fires when bypass is enabled

### GitHub Environments
- [ ] `dev`, `staging`, and `production` environments are configured in GitHub repo Settings
- [ ] `staging` has required reviewers set
- [ ] `production` has required reviewers set
- [ ] Deploy workflow jobs target the correct GitHub Environment (`environment: dev/staging/production`)

### Pipeline
- [ ] `fast-tests.yml` runs Unit + Contract tests on every PR (fakes, no Docker daemon)
- [ ] `integration-tests.yml` is a required pre-merge check (Testcontainers); branch must be up to date with `main`
- [ ] `ui-tests.yml` runs Playwright on the self-hosted runner via `workflow_dispatch` (not a per-PR gate)
- [ ] All test workflows are `runs-on: self-hosted`
- [ ] Merge gate enforced by `orchestrate-v5` — it won't merge a PR whose `fast-tests` or `integration-tests` checks are red
- [ ] A self-hosted runner is installed **as a service** (auto-start on boot) with Docker access
- [ ] `deploy.yml` deploys to Dev on merge to main
- [ ] Dev deploy **skips test-only merges** (gated on `src/**` changes) — v5 lands 3 PRs/ticket, only the implementation merge should deploy
- [ ] Post-deploy smoke step exists for Dev
- [ ] Staging promotion is manual and includes smoke gate
- [ ] Production promotion requires approval gate
- [ ] Images are built once and retagged — never rebuilt

### Exceptions
- [ ] If this is a personal/solo project with direct-to-prod deploys, this is declared in `CLAUDE.md`
