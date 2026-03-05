#!/usr/bin/env python3
"""Background process: sleeps for the delay, then sends notification if marker file still exists.

Supports two notification methods (configured via NOTIFY_METHOD in graph-creds.env):
  - "teams"  — posts an Adaptive Card to a Teams Incoming Webhook (default)
  - "email"  — sends email via Microsoft Graph API
"""

import json
import os
import sys
import time
import urllib.request
import urllib.parse

MARKER_FILE = "/tmp/claude-notify-pending"

delay = int(sys.argv[1]) if len(sys.argv) > 1 else 120
my_id = sys.argv[2] if len(sys.argv) > 2 else None
time.sleep(delay)

# If marker was removed, user responded — don't send
if not os.path.exists(MARKER_FILE):
    sys.exit(0)

# Read notification details from marker
with open(MARKER_FILE) as f:
    notification = json.load(f)

# If this sleeper's ID doesn't match the marker, a newer notification superseded us — exit
marker_id = notification.get("id")
if my_id and marker_id and my_id != marker_id:
    sys.exit(0)

# Clean up marker
os.remove(MARKER_FILE)

title = notification.get("title", "Claude Code Notification")
message = notification.get("message", "Claude Code is waiting for your input.")
question = notification.get("question", "")

# Load credentials
creds = {}
with open(os.path.expanduser("~/.claude/hooks/graph-creds.env")) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, val = line.split("=", 1)
            creds[key] = val


def send_teams():
    """Post an Adaptive Card to a Teams Incoming Webhook."""
    webhook_url = creds.get("TEAMS_WEBHOOK_URL", "")
    if not webhook_url:
        print("TEAMS_WEBHOOK_URL not set in graph-creds.env", file=sys.stderr)
        sys.exit(1)

    body = [
        {
            "type": "TextBlock",
            "text": f"Claude Code: {title}",
            "weight": "Bolder",
            "size": "Medium",
        },
        {
            "type": "TextBlock",
            "text": message,
            "wrap": True,
        },
    ]
    if question:
        body.append({
            "type": "TextBlock",
            "text": f"**Question:** {question}",
            "wrap": True,
        })

    payload = json.dumps({
        "type": "message",
        "attachments": [{
            "contentType": "application/vnd.microsoft.card.adaptive",
            "content": {
                "type": "AdaptiveCard",
                "version": "1.4",
                "body": body,
            },
        }],
    }).encode()

    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req)


def send_email():
    """Send email via Microsoft Graph API."""
    TENANT_ID = creds["GRAPH_TENANT_ID"]
    CLIENT_ID = creds["GRAPH_CLIENT_ID"]
    CLIENT_SECRET = creds["GRAPH_CLIENT_SECRET"]
    NOTIFY_FROM = creds["NOTIFY_FROM"]
    NOTIFY_TO = creds["NOTIFY_TO"]

    # Get OAuth token
    token_data = urllib.parse.urlencode({
        "client_id": CLIENT_ID,
        "scope": "https://graph.microsoft.com/.default",
        "client_secret": CLIENT_SECRET,
        "grant_type": "client_credentials",
    }).encode()

    token_req = urllib.request.Request(
        f"https://login.microsoftonline.com/{TENANT_ID}/oauth2/v2.0/token",
        data=token_data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    token_resp = json.loads(urllib.request.urlopen(token_req).read())
    access_token = token_resp.get("access_token")

    if not access_token:
        sys.exit(1)

    # Send email
    body_text = message
    if question:
        body_text += f"\n\nQuestion: {question}"

    payload = json.dumps({
        "message": {
            "subject": f"Claude Code: {title}",
            "body": {
                "contentType": "Text",
                "content": body_text,
            },
            "toRecipients": [{"emailAddress": {"address": NOTIFY_TO}}],
        },
        "saveToSentItems": False,
    }).encode()

    send_req = urllib.request.Request(
        f"https://graph.microsoft.com/v1.0/users/{NOTIFY_FROM}/sendMail",
        data=payload,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
        },
    )
    urllib.request.urlopen(send_req)


# Dispatch based on configured method (default: teams)
method = creds.get("NOTIFY_METHOD", "teams").lower()
if method == "email":
    send_email()
else:
    send_teams()
