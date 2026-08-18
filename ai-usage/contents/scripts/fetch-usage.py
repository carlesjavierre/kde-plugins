#!/usr/bin/env python3
"""Collect AI provider usage limits and print one JSON object to stdout.

Output: {"providers": [{"id", "name", "limits": [{"label", "percent", "resets_at"}], "error"?}]}
percent is 0-100, resets_at is epoch seconds or null.
Add a provider by writing a function returning that dict and listing it in PROVIDERS.
"""
import json
import os
import time
import urllib.request
from datetime import datetime


def iso_to_epoch(iso):
    if not iso:
        return None
    return int(datetime.fromisoformat(iso).timestamp())


def limit(label, percent, resets_at):
    # A limit whose window already reset is effectively back at 0
    if resets_at and resets_at < time.time():
        percent = 0
    return {"label": label, "percent": round(percent), "resets_at": resets_at}


def claude():
    creds = json.load(open(os.path.expanduser("~/.claude/.credentials.json")))
    token = creds["claudeAiOauth"]["accessToken"]
    req = urllib.request.Request(
        "https://api.anthropic.com/api/oauth/usage",
        headers={
            "Authorization": "Bearer " + token,
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json",
        },
    )
    data = json.load(urllib.request.urlopen(req, timeout=10))
    limits = []
    # The "limits" array carries per-model scoped limits (e.g. Weekly Fable)
    # that the legacy top-level fields do not
    for entry in data.get("limits") or []:
        model = ((entry.get("scope") or {}).get("model") or {}).get("display_name")
        label = {"session": "Session (5h)", "weekly_all": "Weekly"}.get(entry["kind"])
        if label is None:
            label = "Weekly " + model if model else entry["kind"]
        limits.append(limit(label, entry["percent"], iso_to_epoch(entry.get("resets_at"))))
    if not limits:  # older API shape
        for key, label in (("five_hour", "Session (5h)"), ("seven_day", "Weekly")):
            entry = data.get(key)
            if entry and entry.get("utilization") is not None:
                limits.append(limit(label, entry["utilization"], iso_to_epoch(entry.get("resets_at"))))
    return {"id": "claude", "name": "Claude", "limits": limits}


def codex():
    # Live account-level usage — also covers other clients (e.g. Hermes) using
    # the same ChatGPT account, unlike the local ~/.codex/sessions logs
    tokens = json.load(open(os.path.expanduser("~/.codex/auth.json")))["tokens"]
    req = urllib.request.Request(
        "https://chatgpt.com/backend-api/wham/usage",
        headers={
            "Authorization": "Bearer " + tokens["access_token"],
            "chatgpt-account-id": tokens["account_id"],
            "Accept": "application/json",
        },
    )
    data = json.load(urllib.request.urlopen(req, timeout=10))
    rl = data.get("rate_limit") or {}
    limits = []
    for window in (rl.get("primary_window"), rl.get("secondary_window")):
        if not window or window.get("used_percent") is None:
            continue
        secs = window.get("limit_window_seconds") or 0
        label = "Weekly" if secs > 24 * 3600 else "Session (%dh)" % max(1, secs // 3600)
        limits.append(limit(label, window["used_percent"], window.get("reset_at")))
    if not limits:
        raise RuntimeError("no rate limits in usage response")
    return {"id": "codex", "name": "Codex", "limits": limits}


def opencode():
    key = json.load(open(os.path.expanduser("~/.local/share/opencode/auth.json")))["opencode-go"]["key"]
    req = urllib.request.Request(
        "https://opencode.ai/zen/go/v1/usage",
        # opencode.ai's edge rejects the default Python-urllib user agent
        headers={"Authorization": "Bearer " + key, "Accept": "application/json", "User-Agent": "curl/8"},
    )
    usage = json.load(urllib.request.urlopen(req, timeout=10))["usage"]
    limits = []
    for window, label in (("rolling", "Session"), ("weekly", "Weekly"), ("monthly", "Monthly")):
        entry = usage.get(window)
        if entry and entry.get("percent") is not None:
            limits.append(limit(label, entry["percent"], iso_to_epoch(entry.get("resetsAt"))))
    return {"id": "opencode", "name": "OpenCode", "limits": limits}


PROVIDERS = [claude, codex, opencode]

providers = []
for fn in PROVIDERS:
    try:
        providers.append(fn())
    except (FileNotFoundError, KeyError):
        pass  # provider not set up on this machine — hide it entirely
    except Exception as e:  # one broken provider must not blank the widget
        providers.append({"id": fn.__name__, "name": fn.__name__.title(), "limits": [], "error": str(e)})

print(json.dumps({"providers": providers}))
