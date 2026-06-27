# Self-Hosted Runner Setup (v5 CI)

The v5 test workflows (`templates/workflows/{fast,integration,ui}-tests.yml`) all declare
`runs-on: self-hosted`. They need a **persistent** machine because the integration and UI tiers
run real infrastructure: Testcontainers (real SQL Server) and a full Docker Compose stack with a
Playwright browser. GitHub-hosted runners can't keep that warm or give reliable Docker-in-Docker,
so each project that adopts v5 points its repo at one self-hosted runner.

This guide sets up a single Linux/WSL2 runner, installed **as a service** so it survives reboots,
with Docker access for the integration/UI tiers. It assumes the standard GitHub Actions runner
(`actions/runner`).

## Quick reference

```bash
# Status / control once installed (run from the runner dir)
sudo ./svc.sh status
sudo ./svc.sh start
sudo ./svc.sh stop

# Smoke-test the runner path end to end (dispatch from the repo)
gh workflow run ui-tests.yml --ref <branch> -f filter="FullyQualifiedName~SmokeTests"
```

## What the runner must provide

| Tier | Workflow | Needs Docker? | Other |
|------|----------|---------------|-------|
| Unit + Contract (fast) | `fast-tests.yml` | **No** — `DOCKER_HOST` is set to an unreachable address on purpose (TR-11). Don't "fix" it. | .NET SDK |
| Integration | `integration-tests.yml` | **Yes** — Testcontainers spins up real SQL Server | .NET SDK |
| UI | `ui-tests.yml` (`workflow_dispatch`) | **Yes** — `docker compose ... up` the app + Playwright stack | .NET SDK, the compose files on the branch, ports `5001` (API health) / `5002` (client) per project |

So the host needs: the **.NET SDK** matching the project's `global.json`/TFM, a working **Docker
daemon** the runner user can reach, and enough disk for images + Testcontainers volumes.

## 1. Prerequisites (one-time on the host)

```bash
# .NET SDK — match the project's target (example: .NET 9)
# (use the project's documented install; on Ubuntu/WSL2 the dotnet-install script is simplest)
dotnet --info

# Docker — daemon must be running and usable WITHOUT sudo by the runner user
docker run --rm hello-world          # must succeed as the runner user
sudo usermod -aG docker "$USER"      # then log out/in (or `newgrp docker`) if it needed sudo
```

On **WSL2**, either use Docker Desktop with WSL integration enabled for the distro, or run native
`dockerd` inside the distro. Verify `docker run --rm hello-world` works **as the runner user**, not
just under `sudo` — the runner service won't have your interactive sudo.

## 2. Register the runner

1. In the repo on GitHub: **Settings → Actions → Runners → New self-hosted runner → Linux**. GitHub
   shows a download block and a **registration token** (short-lived).
2. On the host:

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
# Use the download URL/version GitHub shows on that page:
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v<VERSION>/actions-runner-linux-x64-<VERSION>.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

# Configure against the repo with the token from the page. Keep the default 'self-hosted' label
# (the workflows match on it). Add project-specific labels only if you later run multiple runners.
./config.sh --url https://github.com/<OWNER>/<REPO> --token <REGISTRATION_TOKEN>
```

Accept the defaults for runner group, name, and work folder unless you have a reason not to.

## 3. Install as a service (survives reboot)

Running `./run.sh` interactively dies when the shell closes — install the service instead:

```bash
sudo ./svc.sh install        # registers a systemd service for the current user
sudo ./svc.sh start
sudo ./svc.sh status         # should show 'active (running)' and 'Connected to GitHub'
```

### WSL2: keep it alive across reboots

WSL2 shuts the distro down when nothing is running and does not auto-start on Windows boot. To keep
the runner up:

1. **Enable systemd in the distro** so `svc.sh` (systemd) works — in `/etc/wsl.conf`:
   ```ini
   [boot]
   systemd=true
   ```
   then `wsl --shutdown` from Windows and reopen the distro.
2. **Auto-start the distro on Windows login** — a Task Scheduler task running
   `wsl -d <Distro> -u root -e /bin/true` (or `wsl.exe --exec dbus-launch true`) at logon is enough
   to boot the distro; systemd then brings the runner service up.

Confirm after a reboot: `sudo ./svc.sh status` shows running and the runner shows **Idle** (green)
on the GitHub Runners page.

## 4. Smoke-test the runner path

Reproduce the path the pilot proved — echo, then Docker, then a real test run:

```bash
# 1. Does the runner pick up jobs at all? Dispatch the UI workflow with a trivial filter:
gh workflow run ui-tests.yml --ref <branch> -f filter="FullyQualifiedName~SmokeTests"
gh run watch   # or watch the Actions tab

# 2. Docker reachable from a job? The integration workflow exercising Testcontainers is the real test:
gh workflow run integration-tests.yml --ref <branch>
```

If the fast tier passes but integration/UI can't reach Docker, the runner **user** lacks Docker
access (see Prerequisites) — the fast tier doesn't expose it because `DOCKER_HOST` is deliberately
unreachable there.

## 5. Persistent-runner hygiene

A long-lived runner accumulates state; budget for it:

- **Disk** — Testcontainers images, compose stacks, and the runner's `_work` dir grow. Prune
  periodically: `docker system prune -af --volumes` (when no run is active) and clear stale
  `_work/<repo>` checkouts.
- **Leftover containers** — a crashed UI run can leave the compose stack up. The `ui-tests.yml`
  teardown handles the happy path; after a failure, `docker compose ... down` manually (or a
  scheduled `docker container prune`).
- **Toolchain drift** — when a project bumps its .NET TFM or Playwright version, update the SDK and
  run `pwsh playwright.ps1 install --with-deps` (or the project's documented browser install) on the
  host. The runner does **not** auto-provision toolchains.
- **Runner updates** — the service auto-updates the runner agent in most cases; if it falls behind,
  `sudo ./svc.sh stop && ./config.sh remove --token <TOKEN>` then re-register with a fresh token.
- **One runner, multiple repos** — register a separate runner per repo (separate `actions-runner`
  dirs), or use a runner group. Don't share one `_work` dir across repos.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Jobs queue forever, runner shows **Offline** | Service not running / distro shut down | `sudo ./svc.sh start`; on WSL2 confirm systemd + auto-start (§3) |
| Integration/UI jobs fail on `docker` | Runner user can't reach the daemon | Add user to `docker` group; verify `docker run --rm hello-world` as that user |
| Fast tier fails trying to use Docker | A Testcontainers/Docker reference leaked into a fast-tier project (TR-11) | Move that test to the integration tier — do **not** point `DOCKER_HOST` at the real daemon |
| UI run checks out the wrong code | `ref` input defaulting to `main` | Pass `--ref <branch>` (and `-f ref=<branch>` for clarity) — see `templates/workflows/README.md` |
| Runner dies when terminal closes | Started with `./run.sh` instead of the service | `sudo ./svc.sh install && sudo ./svc.sh start` |

See also: [templates/workflows/README.md](../templates/workflows/README.md) (the workflows this runner
executes) and [standards/testing.md](../standards/testing.md) (the four-tier model and CI trigger rules).
