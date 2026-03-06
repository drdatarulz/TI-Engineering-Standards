#!/bin/bash
# AgentZula heartbeat hook — fires after every Claude Code tool call.
# Logs a heartbeat activity entry to AgentZula for automatic time tracking.
# Debounces to avoid flooding: skips if < HEARTBEAT_INTERVAL_SECONDS since last heartbeat.

# 1. Drain stdin (required — Claude Code passes JSON on stdin)
cat > /dev/null

# 2. Load config
ENV_FILE="$HOME/.claude/hooks/agentzula-heartbeat.env"
if [ ! -f "$ENV_FILE" ]; then
    exit 0
fi
# shellcheck source=/dev/null
source "$ENV_FILE"

# Validate required config
if [ -z "$AGENTZULA_API_URL" ] || [ -z "$AGENTZULA_API_KEY" ]; then
    exit 0
fi

HEARTBEAT_INTERVAL_SECONDS="${HEARTBEAT_INTERVAL_SECONDS:-300}"

# 3. Debounce — check timestamp of last heartbeat
DEBOUNCE_FILE="/tmp/agentzula-last-heartbeat"
if [ -f "$DEBOUNCE_FILE" ]; then
    last_ts=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
    now_ts=$(date +%s)
    elapsed=$((now_ts - last_ts))
    if [ "$elapsed" -lt "$HEARTBEAT_INTERVAL_SECONDS" ]; then
        exit 0
    fi
fi

# 4. Find project — walk up from CWD looking for .agentzula-project
project_tag=""
search_dir="$(pwd)"
while [ "$search_dir" != "/" ]; do
    if [ -f "$search_dir/.agentzula-project" ]; then
        project_tag=$(head -1 "$search_dir/.agentzula-project" | tr -d '[:space:]')
        break
    fi
    search_dir=$(dirname "$search_dir")
done

if [ -z "$project_tag" ]; then
    exit 0
fi

# 5. Resolve project ID from tag
projects_json=$(curl -s --max-time 3 \
    -H "X-Api-Key: $AGENTZULA_API_KEY" \
    "${AGENTZULA_API_URL}/api/projects?active=true" 2>/dev/null)

if [ -z "$projects_json" ]; then
    exit 0
fi

project_id=$(echo "$projects_json" | jq -r \
    --arg tag "$project_tag" \
    '.items[] | select(.tag == $tag) | .projectId' 2>/dev/null)

if [ -z "$project_id" ] || [ "$project_id" = "null" ]; then
    exit 0
fi

# 6. Post heartbeat
curl -s --max-time 3 \
    -X POST \
    -H "X-Api-Key: $AGENTZULA_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"projectId\": $project_id, \"source\": \"claude-code\", \"description\": \"Claude Code session activity\"}" \
    "${AGENTZULA_API_URL}/api/activity" > /dev/null 2>&1

# 7. Update debounce timestamp
date +%s > "$DEBOUNCE_FILE"
