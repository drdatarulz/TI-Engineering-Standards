# AgentZula Project Setup Guide

How to connect a Claude Code machine and project to AgentZula for automatic time tracking and optional interactive MCP access.

---

## Prerequisites

1. **AgentZula API** must be deployed and reachable
2. **MCP API key** — generate one from the AgentZula UI (Settings > MCP API Keys > Generate)
3. **jq** installed (`sudo apt install jq` or `brew install jq`)
4. **curl** installed (standard on most systems)

---

## 1. Hook Setup

### Copy the heartbeat script

```bash
mkdir -p ~/.claude/hooks

# From TI Engineering Standards repo:
cp developer-tools/hooks/agentzula-heartbeat.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/agentzula-heartbeat.sh
```

### Create the config file

```bash
cp developer-tools/hooks/agentzula-heartbeat.env.template ~/.claude/hooks/agentzula-heartbeat.env
```

Edit `~/.claude/hooks/agentzula-heartbeat.env` and fill in:

```bash
AGENTZULA_API_URL=https://your-agentzula-api-url
AGENTZULA_API_KEY=your-mcp-api-key
HEARTBEAT_INTERVAL_SECONDS=300
```

### Register the PostToolUse hook

Add this to `~/.claude/settings.json` under the `hooks` object:

```json
"PostToolUse": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/agentzula-heartbeat.sh"
      }
    ]
  }
]
```

If you already have other hooks registered (Notification, UserPromptSubmit), add PostToolUse as a sibling entry. See [claude-code-hooks.md](claude-code-hooks.md) for the full settings.json example.

---

## 2. Project Registration

Each repo you want to track needs two things:

### a) A project in AgentZula with a tag

Ensure the project exists in AgentZula with a unique `tag` field (e.g., `proj-agentzula`, `proj-delayedsend`). Create it via the UI or MCP if it doesn't exist.

### b) A `.agentzula-project` marker file

Create a `.agentzula-project` file in the repo root containing just the project tag:

```bash
echo "proj-agentzula" > .agentzula-project
```

Commit this file — it's not a secret and helps identify the project for all Claude Code sessions.

The hook walks up from the current working directory to find this file. Repos without it are silently skipped (no errors, no heartbeats).

---

## 3. MCP Connection (Optional)

For interactive access to AgentZula tools (tasks, plans, activity summaries, invoicing) from Claude Code:

Create `.mcp.json` in the project root:

```json
{
  "mcpServers": {
    "agentzula": {
      "type": "streamable-http",
      "url": "https://your-agentzula-api-url/mcp",
      "headers": {
        "X-Api-Key": "your-mcp-api-key"
      }
    }
  }
}
```

Add `.mcp.json` to `.gitignore` (it contains the API key).

### Available MCP Tools

| Tool | Description |
|------|-------------|
| LogActivity | Log a manual activity entry |
| GetActivitySummary | Get time breakdown by project/client for a date range |
| GetClientsAndProjects | List all clients and their projects |
| GetCurrentPlan | Read the current daily plan |
| UpdateCurrentPlan | Update the daily plan content |
| AddTask | Create a new task |
| CompleteTask | Mark a task as done |
| GetTasks | List tasks with filters |
| GetAgentInstructions | Read agent instruction rules |
| GenerateInvoiceData | Generate invoice line items for a date range |
| Echo | Test connectivity |

---

## 4. Verification

### Test heartbeat connectivity

```bash
# Check API is reachable
curl -s -H "X-Api-Key: YOUR_KEY" https://your-api-url/api/projects?active=true | jq .

# Delete the debounce file to force immediate heartbeat
rm -f /tmp/agentzula-last-heartbeat
```

Then start a Claude Code session in the project directory, use any tool, and check the AgentZula activity log for a new "Claude Code session activity" entry.

### Test MCP connection

If configured, ask Claude Code to call the `Echo` tool — it should return a response.

---

## 5. Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| No heartbeats appearing | Missing `.agentzula-project` file | Create the marker file in the repo root |
| No heartbeats appearing | API key invalid or expired | Generate a new key from the UI |
| No heartbeats appearing | Debounce masking first heartbeat | Delete `/tmp/agentzula-last-heartbeat` to reset |
| No heartbeats appearing | jq not installed | Install jq: `sudo apt install jq` |
| Wrong project logged | Project tag mismatch | Verify `.agentzula-project` tag matches the project's tag in AgentZula |
| Heartbeats too infrequent | Interval too high | Lower `HEARTBEAT_INTERVAL_SECONDS` in env file (default: 300 = 5 min) |
| Hook errors in Claude Code | Script not executable | Run `chmod +x ~/.claude/hooks/agentzula-heartbeat.sh` |
| MCP connection fails | Wrong URL or key | Verify `.mcp.json` URL includes `/mcp` path suffix |
