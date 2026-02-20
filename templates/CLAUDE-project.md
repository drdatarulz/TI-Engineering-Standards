# CLAUDE.md — Project Instructions for Claude Code

## Engineering Standards (Auto-Sync)

This project follows **TI Engineering Standards**. Before starting work:

1. Check for the standards repo at `../TI-Engineering-Standards/`
2. If not found: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
3. If found: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
4. Read `../TI-Engineering-Standards/CLAUDE.md` and all referenced standards files.

All generic engineering rules (architecture, testing, database, git workflow, etc.) live in that repo. This file contains only **project-specific** instructions.

---

## Project Overview

<!-- Describe what this project does in 2-3 sentences -->

Full architectural details: see `ARCHITECTURE.md`

---

## Documentation Map

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project-specific rules and conventions (this file) |
| `ARCHITECTURE.md` | Full system design, database schema, design rationale |
| `STATUS.md` | Build progress history |
| `docs/checklists/` | Deployment runbooks, manual testing checklists |
| `docs/architecture/` | Architecture diagrams (markdown + draw.io) |
| `.github/ISSUE_TEMPLATE/` | Issue templates for stories, bugs, and tasks |
| <!-- GitHub Project link --> | Kanban board — single source of truth for work tracking |

---

## Tech Stack (Project-Specific)

<!-- List technologies specific to this project that go beyond the standard stack -->
<!-- The standard stack (Minimal APIs, Dapper, DbUp, SQL Server, xUnit, etc.) is in TI-Engineering-Standards -->

---

## Project Structure

```
src/
  <!-- List your project's specific source directories -->

tests/
  <!-- List your project's specific test directories -->
```

---

## Key Domain Rules

<!-- Project-specific business rules, domain model, lifecycle states, etc. -->

---

## Build Commands

```bash
# Build everything
dotnet build {ProjectName}.sln

# Run unit tests
dotnet test tests/{ProjectName}.Api.Tests/

# Run integration tests
dotnet test tests/{ProjectName}.Integration.Tests/

# Run Playwright tests
dotnet test tests/{ProjectName}.Playwright.Tests/

# Run DbUp migrations
dotnet run --project src/{ProjectName}.Migrator/
```

---

## Work Tracking

<!-- Reference your GitHub Project board -->
<!-- Story ID prefix for this project (e.g., DS-XXX, XX-XXX) -->

---

## Namespace Gotchas

<!-- Project-specific namespace issues, naming conflicts, etc. -->

---

## Things NOT To Do (Project-Specific)

<!-- Rules specific to this project beyond the universal rules in TI-Engineering-Standards -->
