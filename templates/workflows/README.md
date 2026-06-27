# Template Workflows (v5 CI substrate)

Parameterized GitHub Actions workflows that implement the v5 trigger model
(`standards/testing.md` → CI/CD Testing Tiers). They are **repo-agnostic templates** —
the standards repo ships them, each project instantiates them once. All three run on a
**self-hosted runner** (`runs-on: self-hosted`) — see
[developer-tools/self-hosted-runner-setup.md](../../developer-tools/self-hosted-runner-setup.md)
to provision one.

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

## Dispatching `ui-tests.yml` against a branch (`--ref` vs `-f ref=`)

`gh workflow run` has a `--ref` flag **and** `ui-tests.yml` defines a `ref` *input* — they are
not the same thing:

- `--ref <branch>` selects **which version of the YAML runs** and sets the run's git context
  (`github.ref` / `github.ref_name` / `github.sha`). It does **not** populate the `ref` input.
- `-f ref=<branch>` sets the `ref` *input*, which is what the **checkout step** actually pulls.

The template's `ref` input now defaults to `${{ github.ref_name }}`, so **`--ref <branch>`
alone checks out that branch correctly** — no extra flag needed. (Before this default it fell
back to `main` and silently tested the wrong branch — a feature branch's harness files like
`docker-compose.ui.yml` aren't on `main`, so the run would fail confusingly or pass against
stale code.) Passing `-f ref=<branch>` explicitly still works and overrides the default;
`refine`/`orchestrate` flows pass it for clarity. Pin a raw SHA via `-f ref=<sha>` if needed.

## Merge gate

`fast-tests` and `integration-tests` gate the merge, but the enforcement lives in the
**orchestrator**, not in GitHub settings: `orchestrate-v5` polls each PR's checks and won't
merge a red PR. No branch-protection setup is assumed (it isn't available on a private repo's
Free plan anyway). `ui-tests` is intentionally **not** a required check.

These three workflows are PR/`workflow_dispatch` **test** workflows — none run on push to
`main`. Keep your project's existing main-push workflow for build, version-stamp, frontend
build, and deploy; adopting v5 means moving the *tests* out of it into these tiers, not
deleting it (a `cd.yml` that watches `ci.yml` via `workflow_run` would lose its trigger).

The orchestrator gate stops *automated* red merges; a human keeps the manual override
(**force-merge**) by design — on the Free plan there's no hard block to fight when you judge a
merge is right.

## Adopting v5 in a repo that already has a monolithic CI workflow

If a project runs one `ci.yml` that builds + tests + (via `workflow_run`) triggers deploy, split
it like this — don't rip it out:

1. **Sync the templates** (auto-sync copies the three tier workflows in). Fill `{ProjectName}` /
   `{PROJECT}` / ports.
2. **Move the tests out** of `ci.yml` into the tiers, by failure mode:
   - `Domain.Tests` (Unit) + `Infrastructure.Tests` (Unit — logic in Infrastructure) + `Api.Tests` (Contract) + any other fakes-based projects → `fast-tests.yml`
   - `Integration.Tests` → `integration-tests.yml`
   - `Playwright.Tests` → `ui-tests.yml` (already `workflow_dispatch`)

   Delete the old unfiltered `dotnet test` step.
3. **Slim `ci.yml` to main-push only:** drop its `pull_request` trigger; keep build, version-stamp,
   frontend (npm) builds, and the deploy / `workflow_run` signal. **Keep the file** — `cd.yml` needs it.
4. **Frontend builds:** add the npm build to `fast-tests.yml` so a broken frontend blocks a PR, and
   keep it in `ci.yml` for the main-push/deploy path.
5. **Gate:** nothing to configure — `orchestrate-v5` won't merge a red PR.

Net: tests are fully tiered, nothing runs twice, and CD keeps working off the slimmed `ci.yml`.

## Self-enforcing no-Docker fast tier (TR-11)

`fast-tests.yml` sets `DOCKER_HOST` to an unreachable address, so any Testcontainers/Docker
reference that sneaks into a fast-tier project fails loudly rather than quietly slowing the
per-PR gate. Do not "fix" this by pointing `DOCKER_HOST` at the real daemon — move the test
to the integration tier instead.
