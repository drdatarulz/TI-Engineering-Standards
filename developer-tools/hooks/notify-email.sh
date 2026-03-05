#!/usr/bin/env python3
"""Claude Code notification hook — sends Teams message or email after a delay.

Writes a marker file and spawns a background process that waits NOTIFY_DELAY_SECONDS.
If the marker file still exists after the delay (user hasn't responded), sends a
notification via the method configured in NOTIFY_METHOD (teams or email).
The cancel-notify.sh hook deletes the marker when the user responds, preventing the send.
"""

import json
import os
import subprocess
import sys
import uuid

MARKER_FILE = "/tmp/claude-notify-pending"

# Load config
creds = {}
with open(os.path.expanduser("~/.claude/hooks/graph-creds.env")) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, val = line.split("=", 1)
            creds[key] = val

# Check if enabled
if creds.get("NOTIFY_ENABLED", "true").lower() != "true":
    sys.exit(0)

delay = int(creds.get("NOTIFY_DELAY_SECONDS", "120"))

# Parse hook input
hook_input = json.load(sys.stdin)
title = hook_input.get("title", "Claude Code Notification")
message = hook_input.get("message", "Claude Code is waiting for your input.")

# Try to extract the actual question from the transcript
question = ""
transcript_path = hook_input.get("transcript_path", "")
if transcript_path and os.path.exists(transcript_path):
    try:
        # Read last 20 lines of transcript to find the most recent question
        with open(transcript_path, "rb") as tf:
            # Seek from end to find last N lines efficiently
            tf.seek(0, 2)
            size = tf.tell()
            # Read last 100KB max (plenty for recent entries)
            read_size = min(size, 100_000)
            tf.seek(size - read_size)
            tail = tf.read().decode("utf-8", errors="replace")

        last_question = ""
        question_answered = False
        for line in tail.strip().split("\n"):
            try:
                obj = json.loads(line)
                msg = obj.get("message", {})
                role = msg.get("role", "")
                content = msg.get("content", [])
                # If we see a user message after a question, it's been answered
                if role == "user" and last_question:
                    question_answered = True
                if isinstance(content, list):
                    for block in content:
                        if (isinstance(block, dict)
                                and block.get("type") == "tool_use"
                                and block.get("name") == "AskUserQuestion"):
                            questions = block.get("input", {}).get("questions", [])
                            if questions:
                                last_question = questions[0].get("question", "")
                                question_answered = False
            except (json.JSONDecodeError, KeyError):
                continue

        if last_question and not question_answered:
            question = last_question
    except Exception:
        pass  # Fall through — notification still sends without the question

# Only notify if there's an unanswered question — skip plain idle notifications
if not question:
    sys.exit(0)

# Generate a unique ID for this notification event
notify_id = str(uuid.uuid4())

# Write marker file with notification details (including unique ID)
with open(MARKER_FILE, "w") as f:
    json.dump({"id": notify_id, "title": title, "message": message, "question": question}, f)

# Spawn background sender that sleeps, then sends if marker still exists with matching ID
sender_script = os.path.expanduser("~/.claude/hooks/delayed-send.sh")
subprocess.Popen(
    [sender_script, str(delay), notify_id],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)
