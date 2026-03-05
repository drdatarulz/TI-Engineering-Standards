# Claude Code Hooks & Customizations

Configuration for Claude Code hooks, notifications, and UI customizations. These live in `~/.claude/` and need to be set up on each new machine.

## Overview

The notification system sends a Teams message (or email) when Claude Code is waiting for input and you haven't responded within a configurable delay. A cancel hook suppresses the notification if you respond before the delay expires.

Additionally, a custom status line and spinner verbs are configured for the CLI experience.

---

## File Layout

```
~/.claude/
  settings.json              # Hook registration, status line, spinner verbs
  hooks/
    notify-email.sh          # Python — notification trigger (parses transcript for unanswered questions)
    cancel-notify.sh         # Bash — cancels pending notification on user response
    delayed-send.sh          # Python — background sender (Teams webhook or Graph email)
    graph-creds.env          # Credentials and config (not committed — secrets)
  statusline-command.sh      # Bash — custom status bar (user@host, cwd, model, context %)
```

---

## settings.json

Register the hooks, status line, and UI customizations:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify-email.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/cancel-notify.sh"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "spinnerVerbs": {
    "mode": "replace",
    "verbs": [
      "Stylin' and Profilin'",
      "Standing Tall, Looking Good",
      "Flappin' and Slappin'",
      "Feeling Good, Looking Good",
      "Layeth the Smacketh Downeth"
    ]
  },
  "effortLevel": "high",
  "skipDangerousModePermissionPrompt": true
}
```

### Hook Events

| Event | Script | Purpose |
|-------|--------|---------|
| `Notification` | `notify-email.sh` | Fires when Claude is idle waiting for input. Parses transcript for the unanswered question, writes a marker file, spawns a delayed background sender. |
| `UserPromptSubmit` | `cancel-notify.sh` | Fires when you submit a response. Deletes the marker file so the delayed sender knows not to send. |

---

## Notification Flow

```
Claude asks a question and waits
  |
  v
Notification hook fires
  |-- Reads transcript, extracts unanswered question
  |-- If no unanswered question found, exits (no notification for plain idle)
  |-- Writes marker file to /tmp/claude-notify-pending
  |-- Spawns delayed-send.sh in background with delay + unique ID
  v
[delay elapses — default 120 seconds]
  |
  v
delayed-send.sh wakes up
  |-- If marker file is gone (user responded) → exit silently
  |-- If marker file ID doesn't match (newer notification superseded) → exit silently
  |-- Otherwise → send notification via configured method (Teams or email)
```

If you respond before the delay expires, the `UserPromptSubmit` hook deletes the marker file and no notification is sent.

---

## Scripts

### notify-email.sh (Python)

The notification trigger. Despite the `.sh` extension, this is a Python 3 script with a `#!/usr/bin/env python3` shebang.

**What it does:**
1. Loads config from `graph-creds.env`
2. Checks `NOTIFY_ENABLED` — exits if disabled
3. Parses hook input (JSON on stdin) for title and message
4. Reads the conversation transcript to find the most recent unanswered `AskUserQuestion`
5. If no unanswered question is found, exits without notifying (prevents noise from plain idle states)
6. Writes a marker file with a unique ID
7. Spawns `delayed-send.sh` as a detached background process

### cancel-notify.sh (Bash)

One line — removes the marker file:

```bash
#!/bin/bash
rm -f /tmp/claude-notify-pending
```

### delayed-send.sh (Python)

The background sender. Also Python 3 with a `.sh` extension.

**What it does:**
1. Sleeps for the configured delay
2. Checks if marker file still exists (user didn't respond)
3. Checks if marker ID matches (no newer notification superseded this one)
4. Dispatches to `send_teams()` or `send_email()` based on `NOTIFY_METHOD`

**Teams method:** Posts an Adaptive Card to a Teams Incoming Webhook URL.

**Email method:** Authenticates via OAuth2 client credentials against Microsoft Graph API, sends email via `/users/{from}/sendMail`.

---

## graph-creds.env

Credentials and configuration. **This file contains secrets — do not commit it.**

Create it at `~/.claude/hooks/graph-creds.env` with these keys:

```bash
# General
NOTIFY_ENABLED=true
NOTIFY_DELAY_SECONDS=120
NOTIFY_METHOD=teams          # "teams" or "email"

# Teams webhook (required if NOTIFY_METHOD=teams)
TEAMS_WEBHOOK_URL=https://your-org.webhook.office.com/webhookb2/...

# Microsoft Graph email (required if NOTIFY_METHOD=email)
GRAPH_TENANT_ID=your-tenant-id
GRAPH_CLIENT_ID=your-client-id
GRAPH_CLIENT_SECRET=your-client-secret
NOTIFY_FROM=sender@your-org.com
NOTIFY_TO=recipient@your-org.com
```

### Teams Webhook Setup

1. In the target Teams channel, add an **Incoming Webhook** connector
2. Name it (e.g., "Claude Code Notifications"), copy the webhook URL
3. Set `TEAMS_WEBHOOK_URL` in `graph-creds.env`

### Graph Email Setup

1. Register an app in Azure AD (Entra ID)
2. Grant `Mail.Send` application permission and admin consent
3. Create a client secret
4. Set the `GRAPH_*`, `NOTIFY_FROM`, and `NOTIFY_TO` values in `graph-creds.env`

---

## Status Line

Custom status bar that mirrors the bash PS1 prompt style:

```
user@hostname:/current/working/directory [Claude Opus 4.6] ctx:42%
```

- Bold green `user@host`, bold blue `cwd` (matches default bash PS1)
- Dimmed model name and context window usage percentage
- Reads workspace, model, and context data from JSON on stdin

---

## Source Files

All scripts are checked into this repo at `developer-tools/hooks/`:

| File | Description |
|------|-------------|
| [hooks/notify-email.sh](hooks/notify-email.sh) | Notification trigger (Python 3) |
| [hooks/cancel-notify.sh](hooks/cancel-notify.sh) | Cancel pending notification (Bash) |
| [hooks/delayed-send.sh](hooks/delayed-send.sh) | Background sender — Teams or email (Python 3) |
| [hooks/statusline-command.sh](hooks/statusline-command.sh) | Custom status bar (Bash) |
| [hooks/graph-creds.env.template](hooks/graph-creds.env.template) | Credentials template (fill in and rename) |

## Setup on a New Machine

```bash
# 1. Copy hook scripts
mkdir -p ~/.claude/hooks
cp developer-tools/hooks/notify-email.sh ~/.claude/hooks/
cp developer-tools/hooks/cancel-notify.sh ~/.claude/hooks/
cp developer-tools/hooks/delayed-send.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh

# 2. Copy status line
cp developer-tools/hooks/statusline-command.sh ~/.claude/statusline-command.sh

# 3. Create credentials file from template
cp developer-tools/hooks/graph-creds.env.template ~/.claude/hooks/graph-creds.env
# Edit ~/.claude/hooks/graph-creds.env and fill in your values

# 4. Copy or merge settings.json (see settings.json section above)
# If ~/.claude/settings.json doesn't exist:
#   cp the JSON from the settings.json section above into ~/.claude/settings.json
# If it already exists:
#   merge the hooks, statusLine, and spinnerVerbs keys into your existing file
```

5. **Verify Python 3** is available (`python3 --version`) — the notification scripts use only stdlib (no pip installs needed)

6. **Test:** Run Claude Code, let it ask a question, wait for the delay — you should receive a Teams message or email
