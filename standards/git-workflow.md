# Git & Workflow Standards

## Branching

- **Trunk-based development** — `main` is always deployable
- One branch per story: `story/{ID}-short-name`
- Branch from `main`, merge back to `main`
- Multiple stories can be in progress simultaneously on separate branches
- Process/infrastructure changes commit directly to `main`
- Bugs and tasks use branches only if the change is non-trivial

## Commit Conventions

- Do NOT add `Co-Authored-By` trailers to git commit messages
- Commit messages should be concise and describe the "why" not just the "what"
- Always commit utility scripts (SQL scripts, cleanup scripts, etc.) even if not part of the current task

## Git Hooks

All projects use `.githooks/` (committed to the repo) for shared git hooks.

**Setup (required after clone):**

```bash
git config --local core.hooksPath .githooks
```

### commit-msg

Rejects any commit message containing a `Co-Authored-By` trailer per TI Engineering Standards.

## Passwords and Secrets

- Do NOT use `!` in passwords or secrets — bash interprets `!` as history expansion, making them unusable in shell commands

## Deployment Strategy

### Environments

- **Dev** — auto-deploy on merge to main
- **Staging** — manual promotion (pick a build)
- **Production** — manual promotion with approval gate

### CI/CD Pipeline (GitHub Actions)

**On PR to main (CI):**
```
Restore packages → Build solution → Run unit tests → Fail PR if anything breaks
```

**On merge to main (CD to Dev):**
```
Build + test → Build Docker images (tagged with commit SHA + "dev") → Push to registry → Run migrations → Deploy → Run integration tests
```

**Promote to Staging (manual):**
```
Retag images → Run migrations → Deploy → Smoke tests
```

**Promote to Production (manual + approval):**
```
Approval gate → Retag images → Run migrations → Deploy
```

Images are built once and promoted — never rebuilt.
