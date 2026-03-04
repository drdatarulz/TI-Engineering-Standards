# Claude VM Helper Scripts

Shell helpers defined in `~/.bashrc` on Claude development VMs. They simplify working with tmux sessions for running multiple Claude Code instances in parallel.

## Quick Reference

| Command | Description |
|---------|-------------|
| `claude-attach [name]` | Attach to (or create) a named tmux session |
| `claude-new [name]` | Create a new named tmux session |
| `claude-list` | List all active tmux sessions |
| `claude-yolo` | Launch Claude Code with `--dangerously-skip-permissions` |
| `workspace` | `cd ~/claude-workspace` |

## Multi-Instance Workflow

Run multiple Claude Code instances in parallel using named tmux sessions:

```bash
# Start three sessions for parallel work
claude-attach api        # session "api"
# Ctrl-a d to detach

claude-attach frontend   # session "frontend"
# Ctrl-a d to detach

claude-attach bugfix     # session "bugfix"
# Ctrl-a d to detach

# See all running sessions
claude-list

# Switch between them
claude-attach api
claude-attach frontend
```

## Session Commands

### `claude-attach [name]`

Attaches to an existing tmux session or creates one if it doesn't exist. Defaults to `claude` if no name is given.

```bash
claude-attach           # attaches to (or creates) session "claude"
claude-attach my-task   # attaches to (or creates) session "my-task"
```

### `claude-new [name]`

Creates a new tmux session. Errors if the session already exists. Defaults to `claude` if no name is given.

```bash
claude-new              # creates session "claude"
claude-new feature-x    # creates session "feature-x"
```

### `claude-list`

Lists all active tmux sessions, or prints "No active sessions." if none exist.

```bash
claude-list
# Example output:
# api: 1 windows (created Wed Mar  4 10:00:00 2026)
# frontend: 1 windows (created Wed Mar  4 10:05:00 2026)
```

## Aliases

### `claude-yolo`

Launches Claude Code with all permission prompts skipped:

```bash
claude-yolo
# equivalent to: claude --dangerously-skip-permissions
```

### `workspace`

Shortcut to change into the shared workspace directory:

```bash
workspace
# equivalent to: cd ~/claude-workspace
```

## tmux Basics

The VM uses `Ctrl-a` as the tmux prefix (not the default `Ctrl-b`).

| Keys | Action |
|------|--------|
| `Ctrl-a d` | Detach from current session |
| `Ctrl-a c` | Create a new window within the session |
| `Ctrl-a n` / `Ctrl-a p` | Next / previous window |
| `Ctrl-a [` | Enter scroll mode (navigate with arrows, `q` to exit) |
