# Template Workflows (v5 CI substrate)

Parameterized GitHub Actions workflows that implement the v5 trigger model
(`standards/testing.md` → CI/CD Testing Tiers). They are **repo-agnostic templates** —
the standards repo ships them, each project instantiates them once. All three run on a
**self-hosted runner** (`runs-on: self-hosted`).

| Workflow | Tier | Trigger | Gates merge? |
|----------|------|---------|--------------|
| `fast-tests.yml` | Unit + Contract (fakes, no Docker) | `pull_request` | **Yes** |
| `integration-tests.yml` | Integration (Testcontainers, real SQL) | `pull_request` (required pre-merge check) | **Yes** |
| `ui-tests.yml` | UI (Playwright) | `workflow_dispatch` (`ref` + `filter` inputs) | No — orchestration boundary |

## How they get into a project

The `CLAUDE.md` auto-sync protocol copies this directory into a project's
`.github/workflows/` on session start, **skipping any workflow the project already has**
(same precedence rule as skills — a customized local copy is never overwritten). After the
first sync a project fills in the placeholder tokens (below) and commits.

## Fill-in tokens

Replace these in each copied workflow before committing:

| Token | Meaning | Example |
|-------|---------|---------|
| `{ProjectName}` | Solution / project name; used for `.sln` and `tests/{ProjectName}.*.Tests/` paths | `FormIt` |
| `{PROJECT}` | Uppercase env-var prefix for the Playwright base-URL var | `FORMIT` (→ `FORMIT_BASE_URL`) |
| Ports / health paths in `ui-tests.yml` | Match your `docker-compose` client + API ports | `5001` (API health), `5002` (client) |

Multi-service projects (e.g. an additional `McpServer.Tests` fakes project) add their
extra fast-tier test projects to the **Run fast tests** step in `fast-tests.yml`.

## Merge gate

`fast-tests` and `integration-tests` gate the merge, but the enforcement lives in the
**orchestrator**, not in GitHub settings: `orchestrate-v5` polls each PR's checks and won't
merge a red PR. No branch-protection setup is assumed (it isn't available on a private repo's
Free plan anyway). `ui-tests` is intentionally **not** a required check.

These three workflows are PR/`workflow_dispatch` **test** workflows — none run on push to
`main`. Keep your project's existing main-push workflow for build, version-stamp, frontend
build, and deploy; adopting v5 means moving the *tests* out of it into these tiers, not
deleting it (a `cd.yml` that watches `ci.yml` via `workflow_run` would lose its trigger).

## Self-enforcing no-Docker fast tier (TR-11)

`fast-tests.yml` sets `DOCKER_HOST` to an unreachable address, so any Testcontainers/Docker
reference that sneaks into a fast-tier project fails loudly rather than quietly slowing the
per-PR gate. Do not "fix" this by pointing `DOCKER_HOST` at the real daemon — move the test
to the integration tier instead.
