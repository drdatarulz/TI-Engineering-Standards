---
name: implement-ticket
description: Implement a single ticket following all TI Engineering Standards. Loads context, applies critical constraints, builds/tests, commits, and reports.
argument-hint: "[issue-number or full ticket details]"
---

You are implementing a single ticket. Your working directory is the project root (the directory containing `CLAUDE.md`).

## Step 0: Resolve Project Context

Before anything else, determine the project's GitHub repo:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

This gives you `{OWNER}/{REPO}` for all GitHub CLI commands.

## Resolve Ticket Details

If `{TICKET_TITLE}` appears literally (i.e., was not substituted by an orchestrator), you are running standalone:
- Fetch the ticket: `gh issue view $ARGUMENTS` (the `--repo` flag is unnecessary if you're in the project directory)
- Use the issue title as the ticket title and the issue body as the ticket body
- Determine the branch from `git branch --show-current`
- Extract the Story ID (prefix-XXX) from the issue title

Otherwise, when invoked by the orchestrator, these values are already populated:
- **Story ID:** {TICKET_NUMBER}
- **Ticket:** {TICKET_TITLE}
- **Branch:** {BRANCH_NAME}
- **GitHub Issue:** #{ISSUE_NUMBER}

**Fetch the full ticket body** from GitHub (do NOT expect it inline — it is too large for the prompt):
```bash
gh issue view {ISSUE_NUMBER}
```
Read the acceptance criteria, technical approach, and files expected to change from the issue body.

## Context Loading (Do This First)

Before writing any code, read and internalize these files:

1. Read `../TI-Engineering-Standards/CLAUDE.md` and **every file it references** — there are 12 standards files covering architecture, testing, git, database, security, logging, etc. Read them all.
2. Read `CLAUDE.md` — project-specific rules (contains build commands, test commands, project structure)
3. Read `ARCHITECTURE.md` — system design, database schema, design rationale

Do NOT write any code until all three steps are complete.

## Critical Constraints (Non-Negotiable)

These are inlined because they are the most commonly violated rules. All rules in the standards files also apply, but violating ANY of these is a hard failure.

### Architecture
- **Domain has ZERO dependencies** — no NuGet packages, no project references
- **Dapper only** — NO Entity Framework, NO LINQ-to-SQL, NO other ORMs
- **Minimal APIs only** — NO MVC controllers
- **Built-in DI only** — NO third-party IoC containers (Autofac, etc.)
- **Services access data through the API** via HTTP client repos — not directly through DB repositories (unless existing code already uses direct access — don't partially convert)
- **Interfaces live in Domain** — concrete implementations live in Infrastructure
- **Interface names describe behavior, not technology** — `IEmailQueue` not `IAzureStorageQueue`
- **Infrastructure types NEVER in interfaces** — `DbConnection`, `HttpClient`, `SmtpClient`, `SslStream`, `TcpClient` appear ONLY in concrete classes in Infrastructure
- **No cloud SDKs outside Infrastructure** — Azure/AWS/GCP references belong only in Infrastructure

### Testing
- **xUnit + FluentAssertions** — the only test frameworks
- **NO mocking frameworks — EVER** — NO Moq, NO NSubstitute, NO FakeItEasy
- **Hand-rolled fakes only** — explicit classes in the `*.Fakes` project implementing the interface
- **Test naming**: `Snake_case_describing_behavior` as method names on a class named `{ClassUnderTest}Tests`
- **Write tests alongside implementation**, not after — every new endpoint and behavior gets tests
- **Dapper SQL and infrastructure go in integration tests**, not unit tests — unit tests use fakes

### Git
- **NO `Co-Authored-By` trailers** in commit messages
- **Commit message = concise "why"**, not just "what"
- **Stage specific files** — never `git add .` or `git add -A`
- **No `!` in passwords or secrets** — bash interprets `!` as history expansion
- **Always commit utility scripts** — SQL scripts, cleanup scripts in `scripts/` get committed even if not part of the current task

### Database
- **INT IDENTITY(1,1) primary keys** — NO GUIDs
- **DATETIME2 + SYSUTCDATETIME()** — NO DATETIME, NO GETDATE()
- **DbUp forward-only** — NO down migrations, ever
- **NVARCHAR(4000)** max for address fields — NO NVARCHAR(MAX)
- **Naming conventions** — Tables: PascalCase plural. Columns: PascalCase. FKs: `FK_{Child}_{Parent}`. UQs: `UQ_{Table}_{Col}`. CKs: `CK_{Table}_{Col}`. Indexes: `IX_{Table}_{Col}`

### Error Handling (API endpoints)
- **`ErrorResponse` record** — all errors use `{ Error: string, Detail: string? }`. No Problem Details / RFC 9457
- **HTTP status codes** — 200 GET, 201 POST (with Location header), 204 PUT/DELETE, 400 validation (ErrorResponse), 403 auth (no body, Results.Forbid()), 404 (no body)
- **Pagination envelope** — `{ items, totalCount, page, pageSize }` on all list endpoints. Default 25, max 100

### Logging
- **Serilog structured logging** — named placeholders `{EmailId}`, never string interpolation
- **Standard properties** — `{CorrelationId}`, `{UserId}`, `{EmailId}`, `{Count}`, `{Elapsed}`, `{Status}`
- **Never log secrets or PII** — no connection strings, passwords, tokens, full email bodies

## Implementation Workflow

### 1. EXPLORE (before writing code)
- Read all existing code in the affected area
- Understand the patterns already established for this component
- Check the Fakes project for existing fakes you'll need or need to extend
- Identify which files need to change and what new files are needed

### 2. PLAN (before writing code)
- Determine implementation approach based on existing patterns in the codebase
- Verify the approach respects the build order: Domain -> Fakes -> Infrastructure -> Api
- If anything is architecturally ambiguous, note it in your report — do your best interpretation but flag it

### 3. IMPLEMENT
- Follow the build order — don't jump ahead
- Write fakes for any new interfaces immediately
- Write tests alongside each piece of implementation, not after

### 4. TEST

Use the build and test commands from the project's `CLAUDE.md`:
- Build the full solution
- Run the relevant test project(s)
- All tests must pass — both new and existing
- If tests fail, fix them. You have 3 attempts to fix failing tests before reporting as partial.
- Confirm the full solution builds with no errors

### 5. COMMIT
- Stage specific files by name (never `git add .`)
- Commit message format: `{STORY_ID}: Concise description of why this change was made`
- Do NOT push the branch

### 6. REPORT

Return your results in this exact format:

```
STATUS: Complete | Partial | Blocked
TICKET: {STORY_ID}
BRANCH: {BRANCH_NAME}

CHANGES:
- path/to/file.cs: what changed and why
- path/to/file.cs: what changed and why

TESTS:
- New tests written: [count]
- All unit tests pass: yes/no
- Full solution builds: yes/no
- Integration tests needed: yes/no (reason)

DECISIONS:
- Any pattern choices, trade-offs, or interpretations of ambiguous requirements

CONCERNS:
- Anything that felt wrong, might need revisiting, or affects future tickets

BLOCKED_REASON: (only if STATUS is Blocked)
- What's blocking and what decision is needed
```

If STATUS is Blocked, explain clearly what decision or dependency you need. Do NOT guess or improvise around blockers.
