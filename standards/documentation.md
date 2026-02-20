# Documentation Standards

## XML Documentation (Convention-Only)

- **Full coverage** — All public types and members across all projects
- **Full tags** — `<summary>`, `<param name="x">`, `<returns>` on all applicable members
- **Remarks sparingly** — Only for complex behavior, caveats, or non-obvious rules
- **No enforcement** — No `<GenerateDocumentationFile>`, no CS1591 warnings
- **Additive** — Existing inline comments (numbered workflows, protocol phases) stay as-is
- **New code rule** — Always include XML docs on new public members
- **Fakes** — Class-level `<summary>` required; per-method docs only when behavior is non-obvious
- **Blazor code-behind** — Document public/protected methods and injected service properties
- **Not in .razor files** — XML doc comments go in `.razor.cs` code-behind, not in `.razor` markup

## Architecture Documentation — Dual Format

When creating or updating architecture documents in `docs/architecture/`, always produce **both formats**:

1. **Markdown files** (`.md`) — prose, tables, Mermaid diagrams for GitHub rendering
2. **draw.io files** (`.drawio`) — editable visual diagrams matching the same content

Each `.md` file has a corresponding `.drawio` file with the same base name (e.g., `diagrams.md` and `diagrams.drawio`). When updating an architecture document, update both files to keep them in sync.

### draw.io Conventions

- Use multiple tabs/pages within a single `.drawio` file (one per diagram)
- Color scheme: dark blue for people/primary, blue for containers, gray for external systems, green for success, red for failure, orange for warnings/CRON services, purple for secrets/tests
- Include edge labels for key relationships
- Files live alongside their markdown counterparts in `docs/architecture/`

## Project Documentation Map

Every project should have these documentation files:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project-specific rules, conventions, constraints (references TI-Engineering-Standards) |
| `ARCHITECTURE.md` | Full system design, database schema, design rationale |
| `STATUS.md` | Build progress history |
| `docs/checklists/` | Deployment runbooks, manual testing checklists |
| `docs/architecture/` | Architecture diagrams (md + draw.io) |
| `.github/ISSUE_TEMPLATE/` | Issue templates for stories, bugs, tasks |
