---
name: conformance-v5
description: "Audit a project against TI Engineering Standards, including the v5 four-tier test model (TR-1..TR-11) and the v5 CI tiering. Informational only — produces a gap report, creates no files and makes no changes. Use when onboarding an existing codebase, returning to a dormant project, or after standards have been updated."
argument-hint: "[full | pipeline | standards] (default: full)"
---

You are auditing a project against TI Engineering Standards. Your job is to read the project and produce an honest gap report. You make **no changes** — no file edits, no commits, no tickets, no PRs. Your only output is the report.

**Audit under engineering discipline** (`standards/engineering-discipline.md`, ED-1..ED-4). Every finding must be **grounded in the actual file** (ED-1) — cite the `file:line` you read, never report a gap from an assumption about how the project "probably" looks. A check you genuinely cannot determine is reported as **Unknown with the reason** (ED-3), never silently passed or failed. This honest-evidence discipline *is* the value of a conformance report.

## Mode

When `$ARGUMENTS` contains a mode, use it:
- `full` — audit everything: pipeline/environments, code standards, testing, project structure (default)
- `pipeline` — audit only pipeline and environments conformance (faster, focused on `standards/environments.md`)
- `standards` — audit only code and testing standards (architecture, naming, testing patterns, etc.)

If no mode is provided, default to `full`.

## Step 0: Load Context

1. Sync and read the standards repo:
   - If `../TI-Engineering-Standards/` exists: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
   - If not: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
2. Read `../TI-Engineering-Standards/CLAUDE.md` and **every standards file it references**
3. Read `CLAUDE.md` — project-specific rules and declared exceptions
4. Read `ARCHITECTURE.md` — system design context

---

## Step 1: Understand the Project

Before auditing, build a picture of what the project is:

```bash
# Repo identity
gh repo view --json name,description,defaultBranch

# Solution structure
find . -name "*.sln" -o -name "*.csproj" | grep -v bin | grep -v obj | head -30

# Test projects
find . -path "*/tests/*" -name "*.csproj" | grep -v bin | grep -v obj

# CI/CD files
ls -la .github/workflows/

# Infrastructure files
find . -name "*.bicep" -o -name "*.bicepparam" | grep -v bin | grep -v obj

# Git hooks
ls -la .githooks/ 2>/dev/null || echo "No .githooks directory"
```

Read each workflow YAML file in full. Read each Bicep file. Read the solution structure.

---

## Step 2: Pipeline & Environments Audit

*(Skip if mode is `standards`)*

Work through each item in the `standards/environments.md` conformance checklist. For each item, determine pass, fail, or not-applicable with a brief finding.

### 2a. Infrastructure

For each check, look at the actual files:

```bash
# Check Bicep structure
find . -name "*.bicep" -o -name "*.bicepparam" | grep -v bin

# Check environment parameter
grep -n "param environment" infra/main.bicep 2>/dev/null || echo "Not found"
```

| Check | Result | Finding |
|-------|--------|---------|
| `infra/main.bicep` exists | | |
| Accepts `environment` parameter | | |
| Parameter files for dev/staging/prod | | |
| Resource names derived from environment | | |

### 2b. Application

```bash
# Health endpoint
grep -rn "MapHealthChecks\|/health" src/ --include="*.cs"

# Auth bypass
grep -rn "UseDevBypass\|DevBypass" src/ --include="*.cs"
grep -rn "UseDevBypass" --include="*.json" .
```

| Check | Result | Finding |
|-------|--------|---------|
| `/health` endpoint implemented | | |
| Auth bypass controlled by `Authentication:UseDevBypass` | | |
| Auth bypass absent from prod config | | |

### 2c. GitHub Environments

```bash
# Check GitHub Environments are configured
gh api repos/{REPO_OWNER}/{REPO_NAME}/environments --jq '.environments[].name' 2>/dev/null

# Check environment protection rules
gh api repos/{REPO_OWNER}/{REPO_NAME}/environments/staging --jq '.protection_rules' 2>/dev/null
gh api repos/{REPO_OWNER}/{REPO_NAME}/environments/production --jq '.protection_rules' 2>/dev/null
```

| Check | Result | Finding |
|-------|--------|---------|
| `dev` environment configured | | |
| `staging` environment configured | | |
| `production` environment configured | | |
| `staging` has required reviewers | | |
| `production` has required reviewers | | |

### 2d. Pipeline

Read each workflow YAML file in full. v5 splits tests into **three workflows** (see `templates/workflows/` and `standards/testing.md` → CI/CD Testing Tiers):

```bash
ls .github/workflows/
cat .github/workflows/fast-tests.yml 2>/dev/null
cat .github/workflows/integration-tests.yml 2>/dev/null
cat .github/workflows/ui-tests.yml 2>/dev/null
cat .github/workflows/deploy.yml 2>/dev/null
```

| Check | Result | Finding |
|-------|--------|---------|
| `fast-tests` workflow runs on every PR (Unit `Domain.Tests`+`Infrastructure.Tests` and Contract `Api.Tests`) | | |
| `fast-tests` runs with **no Docker daemon** — fast tier is Docker-free (TR-11) | | |
| `integration-tests` workflow runs on every PR (real infra via Testcontainers) | | |
| `ui-tests` runs via **`workflow_dispatch`** on the self-hosted runner — NOT a per-PR gate | | |
| Merge gate = `fast-tests` + `integration-tests` green (enforced by orchestrator, not branch protection) | | |
| Deploy triggers on merge to main, targets `dev` GitHub Environment | | |
| Post-deploy smoke step exists | | |
| Staging job targets `staging`; includes smoke + UI gates | | |
| Production job targets `production` GitHub Environment | | |
| Images built once and retagged — not rebuilt | | |

---

## Step 3: Code & Standards Audit

*(Skip if mode is `pipeline`)*

This is a sampling audit, not an exhaustive line-by-line review. Read a representative set of files from each layer and assess conformance. Flag patterns, not individual instances — if a violation appears once it may be an oversight; if it appears across multiple files it's a pattern worth calling out.

### 3a. Project Structure

```bash
# Verify expected project layout
find src -maxdepth 2 -type d | grep -v bin | grep -v obj
find tests -maxdepth 2 -type d | grep -v bin | grep -v obj
```

Check against `standards/architecture.md`:
- Domain project has zero dependencies (no NuGet, no project references)
- Interfaces in `Domain/Interfaces/`, models in `Domain/Models/`
- Infrastructure types absent from interfaces
- Fakes project exists: `{Project}.Fakes`

### 3a.1 Service Data Access — API as the Boundary

For every project that is a **worker, CRON job, or background service** (NOT the API, NOT the Migrator), check whether it accesses data through the API or directly through infrastructure:

```bash
# Find worker/service projects (exclude Api, Migrator, Domain, Infrastructure, Web, test projects)
find src -maxdepth 1 -type d | grep -v -E 'Api|Migrator|Domain|Infrastructure|Web|obj|bin' | while read dir; do
  if [ -f "$dir/Program.cs" ]; then
    echo "=== $(basename $dir) ==="
    # Check for direct infrastructure registrations
    grep -n "ISubmissionRepository\|IBlobStorageService\|ITeamMailboxConfigRepository\|I.*Repository\|IAuditWriter\|ISubmissionAuditWriter" "$dir/Program.cs" 2>/dev/null | head -10
    # Check for HttpClient-based API access (the correct pattern)
    grep -n "HttpClient\|AddHttpClient\|IApiClient" "$dir/Program.cs" 2>/dev/null | head -5
  fi
done
```

Per `standards/architecture.md` → "Service Data Access — API as the Boundary":

| Check | Result | Finding |
|-------|--------|---------|
| Workers access data through API endpoints (not direct DB/storage) | | |
| No direct `I*Repository` registrations in worker DI | | |
| No direct `IBlobStorageService` registrations in worker DI | | |
| Workers use `HttpClient` to call API endpoints | | |
| Any exceptions are documented and approved by project owner | | |

If a worker has direct infrastructure access, flag it as a gap. Note the standard's guidance: "do not partially convert — leave as-is until a dedicated conversion ticket is created."

### 3b. API Layer

Read 3–5 endpoint files. Check against `standards/api-design.md` and `standards/dotnet.md`:
- Minimal APIs (no MVC controllers)
- Typed DTOs — no anonymous types returned
- `[JsonPropertyName]` on all DTO properties
- `.Produces<T>()` declarations on endpoints
- No hard-coded config fallbacks (`?? "default"` patterns)

### 3c. Data Access

Read 2–3 repository files. Check against `standards/database.md` and `standards/dotnet.md`:
- Dapper only (no Entity Framework)
- INT IDENTITY primary keys (no GUIDs)
- No raw string concatenation in SQL
- DbUp migrations — forward-only, no down migrations

### 3d. Testing — the v5 four-tier model (TR-1..TR-11)

Audit against `standards/testing.md` → Test Tiers + Test Rules. This is the heart of the v5 conformance check: the right **shape** (a pyramid, not an inverted one), not just "tests exist."

```bash
# Tier projects — expect FOUR test-project kinds, by where each tier lives
find tests -name "*.csproj" | grep -v bin
#   Unit:        {Project}.Domain.Tests  AND  {Project}.Infrastructure.Tests
#   Contract:    {Project}.Api.Tests   (WebApplicationFactory over fakes, no Docker)
#   Integration: real-infra project (Testcontainers)
#   UI:          Playwright project

# Contract tier uses the real host (WebApplicationFactory)
grep -rln "WebApplicationFactory" tests/ --include="*.cs"

# Critical-path journeys — count the repo-wide tagged set (TR-6 ceiling 10, floor ~3)
grep -rn 'Trait("CriticalPath"' tests/ --include="*.cs" | wc -l

# Docker/Testcontainers in the fast tier? (TR-11 — must be NONE in Domain/Infra/Api .Tests)
grep -rln "Testcontainers\|DockerClient\|new .*Container" tests/*Domain.Tests tests/*Infrastructure.Tests tests/*Api.Tests 2>/dev/null

# Silent failures / Skip (TR-8) and UI anti-patterns (TR-9)
grep -rn "Skip\s*=" tests/ --include="*.cs" | head
grep -rn "Task.Delay\|Thread.Sleep\|WaitForTimeoutAsync" tests/ --include="*.cs" | head

# Hygiene (unchanged): no mocking frameworks, Shouldly not FluentAssertions
grep -rn "Moq\|NSubstitute\|FakeItEasy" tests/ --include="*.cs" | head
grep -rn "FluentAssertions\|\.Should()" tests/ --include="*.cs" | head
```

| Check | Result | Finding |
|-------|--------|---------|
| Unit tier spans **two** projects: `Domain.Tests` AND `Infrastructure.Tests` | | |
| Contract tier (`Api.Tests`) exists and uses `WebApplicationFactory` over fakes | | |
| **No business logic in Contract** — Contract tests assert wiring/seam, not business outcomes (TR-2) | | |
| **No inverted pyramid** — logic tested at Unit, not at Integration; no behavior tested at two tiers (TR-1/TR-10) | | |
| Integration tests assert only real-infra behavior, not re-asserted contract (TR-3) | | |
| Critical-path count **≤ 10 repo-wide** (TR-6 ceiling); floor ~3 if any UI surface | | |
| No `Skip`, no silent/guard-and-bail tests (TR-8) | | |
| UI uses Page Object Model + condition-based waits — no `Task.Delay`/`Thread.Sleep`/inline locators (TR-9) | | |
| **No Testcontainers/Docker in the fast tier** projects (TR-11) | | |
| No mocking frameworks; Shouldly (not FluentAssertions); `Snake_case` test names | | |

**Inverted-pyramid is the headline finding.** If logic-only scenarios (pricing, mapping, validation walks) live in the Integration project, or `Infrastructure.Tests` is missing so Infrastructure logic has nowhere fast to land, call it out as a pattern — it is the single largest driver of slow, flaky suites.

### 3e. Error Handling & Logging

Read Program.cs and 1–2 service files. Check against `standards/error-handling.md` and `standards/logging.md`:
- Serilog configured
- No swallowed exceptions (`catch {}` or `catch (Exception) {}` with no logging)
- Structured logging (no string interpolation in log messages)

### 3f. Security

```bash
# Check for hardcoded secrets
grep -rn "password\s*=\s*\"" src/ --include="*.cs" -i | head -5
grep -rn "secret\s*=\s*\"" src/ --include="*.cs" -i | head -5
```

Check against `standards/security.md`:
- No secrets in source code
- Auth configured (not commented out)
- CORS configured appropriately

### 3g. Git Hygiene

```bash
# Check git hooks
cat .githooks/commit-msg 2>/dev/null || echo "No commit-msg hook"

# Check for Co-Authored-By in recent commits
git log --oneline -20 | head -20
git log --format="%B" -20 | grep -i "co-authored" | head -5
```

### 3h. v5 Adoption

```bash
# Orchestration entrypoint vendored
ls scripts/orchestrate.sh 2>/dev/null || echo "No vendored orchestrate.sh"
# v5 skills synced locally
ls .claude/skills/ 2>/dev/null | grep -E 'v5' | head
# Standards sync includes the discipline standard
ls ../TI-Engineering-Standards/standards/engineering-discipline.md 2>/dev/null
```

| Check | Result | Finding |
|-------|--------|---------|
| `scripts/orchestrate.sh` wrapper vendored (for long-haul runs) | | |
| v5 pipeline skills present in `.claude/skills/` (not stale v4-only) | | |
| `standards/engineering-discipline.md` present in the synced standards | | |

---

## Step 4: Produce Report

```
## Conformance Report
**Project:** {project name}
**Date:** {today}
**Mode:** full | pipeline | standards
**Audited by:** conformance-v5

---

### Summary

| Category | Passed | Failed | N/A |
|----------|--------|--------|-----|
| Infrastructure (Bicep) | X | X | X |
| Application | X | X | X |
| GitHub Environments | X | X | X |
| Pipeline | X | X | X |
| Project Structure | X | X | X |
| API Layer | X | X | X |
| Data Access | X | X | X |
| Testing | X | X | X |
| Error Handling & Logging | X | X | X |
| Security | X | X | X |
| Git Hygiene | X | X | X |
| **Total** | **X** | **X** | **X** |

**Overall assessment:** Conformant | Mostly conformant | Significant gaps | Non-conformant

> Report each check as Pass / Fail / N-A / **Unknown** (with the reason it couldn't be determined — ED-3). Every Fail cites the `file:line` evidence behind it (ED-1).

---

### Gaps Found

List every failed check with context:

#### [Category]: [Check description]
**Finding:** What was found (or not found)
**Standard:** `standards/{file}.md` — relevant rule
**Suggested fix:** What would need to change to pass this check

---

### Passed Checks

[Collapsed list of everything that passed — one line each]

---

### Declared Exceptions

[Any items marked as exceptions in the project's CLAUDE.md, e.g. personal project with direct-to-prod deploys]

---

### Notes

[Anything observed that doesn't map cleanly to a specific check but is worth flagging — patterns, drift, areas of concern]
```

---
<!-- skill-version: 5.0 -->
<!-- last-updated: 2026-06-27 -->
<!-- pipeline: v5 -->
