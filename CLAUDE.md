# TI Engineering Standards

This repository is the single source of truth for engineering standards, conventions, and patterns used across all TI projects. It is consumed primarily by Claude Code but is also human-readable.

---

## Auto-Sync Protocol (for Claude Code)

When starting a session on **any project**, follow this protocol:

1. **Check for this repo** as a sibling directory: `../TI-Engineering-Standards/`
2. **If not found**, clone it: `git clone https://github.com/drdatarulz/TI-Engineering-Standards.git ../TI-Engineering-Standards/`
3. **If found**, pull latest: `cd ../TI-Engineering-Standards && git pull --ff-only && cd -`
4. **Read this file** and the referenced standards files below before starting work.
5. **Sync skills**: Copy shared skills into the project (skipping any that already exist locally):
   ```bash
   mkdir -p .claude/skills
   for skill_dir in ../TI-Engineering-Standards/skills/*/; do
     skill_name=$(basename "$skill_dir")
     if [ ! -d ".claude/skills/$skill_name" ]; then
       cp -r "$skill_dir" ".claude/skills/$skill_name"
     fi
   done
   ```
   Local skills in `.claude/skills/` take precedence — if a project has a customized version, it won't be overwritten.

When the user asks to update a standard:
- Update the relevant file in this repo
- Apply the change to the current project if applicable
- Commit the change to this repo

---

## Standards Index

Read each of these files — they contain the engineering rules and conventions that apply to all projects:

| File | Scope |
|------|-------|
| [standards/architecture.md](standards/architecture.md) | Dependency inversion, interface-first design, project layering |
| [standards/configuration.md](standards/configuration.md) | Options pattern, config layering, environment variables |
| [standards/database.md](standards/database.md) | SQL Server conventions, primary keys, timestamps, migrations |
| [standards/documentation.md](standards/documentation.md) | XML docs, architecture docs (dual-format md + draw.io) |
| [standards/dotnet.md](standards/dotnet.md) | .NET runtime, Minimal APIs, Dapper, DbUp, DI conventions |
| [standards/error-handling.md](standards/error-handling.md) | Error responses, HTTP status codes, validation, pagination |
| [standards/git-workflow.md](standards/git-workflow.md) | Branching, commits, PR process |
| [standards/logging.md](standards/logging.md) | Serilog, log levels, correlation IDs, health checks |
| [standards/project-tracking.md](standards/project-tracking.md) | GitHub Projects v2 workflow, issue types, board structure |
| [standards/security.md](standards/security.md) | Auth, input validation, CORS, rate limiting, secrets |
| [standards/testing.md](standards/testing.md) | Testing philosophy, frameworks, naming, fakes, CI/CD tiers |
| [standards/ui.md](standards/ui.md) | Blazor WebAssembly, MudBlazor, frontend patterns |

---

## Skills (Claude Code)

Shared skills live in `skills/` and are auto-copied to each project's `.claude/skills/` during sync. Projects can override any skill by placing a customized version in their own `.claude/skills/` directory.

| Skill | Purpose |
|-------|---------|
| [skills/implement-ticket](skills/implement-ticket/SKILL.md) | Implement a single ticket — loads context, applies constraints, builds/tests, commits, reports |
| [skills/orchestrate](skills/orchestrate/SKILL.md) | Sequentially implement multiple tickets via subagents — pre-flight, board updates, merging |
| [skills/refine-story](skills/refine-story/SKILL.md) | Refine a GitHub issue into an implementation-ready spec — explores codebase, resolves gaps interactively |

---

## Templates

| File | Purpose |
|------|---------|
| [templates/CLAUDE-project.md](templates/CLAUDE-project.md) | Template CLAUDE.md for new projects — copy and fill in project-specific sections |

---

## Things NOT To Do (Universal)

These rules apply to **every project**, no exceptions:

- Do NOT use Entity Framework or any ORM other than Dapper
- Do NOT use MVC controllers — Minimal APIs only
- Do NOT use mocking frameworks (Moq, NSubstitute, FakeItEasy) — hand-rolled fakes only
- Do NOT use GUID primary keys — INT IDENTITY everywhere
- Do NOT add third-party IoC containers — built-in DI only
- Do NOT create down migrations — DbUp forward-only
- Do NOT use `!` in passwords or secrets — bash interprets `!` as history expansion, making them unusable in shell commands
- Do NOT put cloud SDK references in Domain or any service project except Infrastructure
- Do NOT add `Co-Authored-By` trailers to git commit messages
