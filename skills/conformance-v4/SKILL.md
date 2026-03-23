---
name: conformance-v4
description: "Audit a project against TI Engineering Standards. Informational only — produces a gap report, creates no files and makes no changes. Use when onboarding an existing codebase, returning to a dormant project, or after standards have been updated."
argument-hint: "[full | pipeline | standards] (default: full)"
---

You are auditing a project against TI Engineering Standards. Your job is to read the project and produce an honest gap report. You make **no changes** — no file edits, no commits, no tickets, no PRs. Your only output is the report.

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

Read each workflow YAML file in full and check:

```bash
cat .github/workflows/ci.yml 2>/dev/null
cat .github/workflows/deploy.yml 2>/dev/null
```

| Check | Result | Finding |
|-------|--------|---------|
| CI runs unit tests on every PR | | |
| CI runs integration tests on every PR (no Category!=Integration filter) | | |
| Deploy triggers on merge to main | | |
| Deploy targets `dev` GitHub Environment | | |
| Post-deploy smoke step exists | | |
| Post-deploy UI test step exists (with `APP_BASE_URL`) | | |
| Staging job targets `staging` GitHub Environment | | |
| Staging includes smoke + UI test gates | | |
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

### 3d. Testing

```bash
# Check test projects exist
find tests -name "*.csproj" | grep -v bin

# Check for mocking frameworks
grep -rn "Moq\|NSubstitute\|FakeItEasy" tests/ --include="*.cs" | head -10

# Check for FluentAssertions (should be replaced with Shouldly)
grep -rn "FluentAssertions\|\.Should()" tests/ --include="*.cs" | head -10

# Check for Shouldly
grep -rn "Shouldly" tests/ --include="*.csproj" | head -5

# Check integration test filter in CI
grep -rn "Category!=Integration" .github/ 2>/dev/null
```

Check against `standards/testing.md`:
- Unit, integration, and UI test projects all exist
- No mocking frameworks (Moq, NSubstitute, FakeItEasy)
- Shouldly used (not FluentAssertions)
- Integration tests use Testcontainers pattern
- Test naming uses `Snake_case_describing_behavior`
- UI tests use Page Object Model

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

---

## Step 4: Produce Report

```
## Conformance Report
**Project:** {project name}
**Date:** {today}
**Mode:** full | pipeline | standards
**Audited by:** conformance-v4

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
<!-- skill-version: 4.0 -->
<!-- last-updated: 2026-03-23 -->
<!-- pipeline: v4 -->
