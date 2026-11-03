#!/usr/bin/env python3
"""LiteLLM -> Token Monitor bridge.

LiteLLM sees API traffic (OpenAI, Anthropic, OpenRouter, ...). Token Monitor sees
local coding agents and subscription limits (Claude Code, Codex, Cursor, ...).
This bridge normalizes LiteLLM spend logs into Token Monitor's Hub ingest format,
so both planes appear in one dashboard and one menu bar.

Usage:
    python3 bridge/litellm_bridge.py --once --dry-run
    python3 bridge/litellm_bridge.py --loop
    LITELLM_MASTER_KEY=... TOKEN_MONITOR_SECRET=... python3 bridge/litellm_bridge.py

Environment:
    LITELLM_BASE_URL       default http://127.0.0.1:4000
    LITELLM_MASTER_KEY     required (or --litellm-key)
    TOKEN_MONITOR_HUB_URL  default http://127.0.0.1:17321
    TOKEN_MONITOR_SECRET   optional hub bearer token
    TOKEN_MONITOR_DEVICE_ID default litellm-proxy
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import signal
import socket
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

UTC = dt.timezone.utc
DEFAULT_SINCE = "2024-01-01"
DEFAULT_PAGE_SIZE = 1000
DEFAULT_MAX_PAGES = 100
MAX_PAYLOAD_BYTES = 900_000
MAX_SESSIONS_PER_PERIOD = 200
MAX_PROJECTS = 100


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


@dataclass
class Config:
    litellm_url: str
    litellm_key: str
    hub_url: str
    hub_secret: str
    device_id: str
    interval: int
    db_path: Path
    since: str
    page_size: int
    max_pages: int
    dry_run: bool = False


def default_db_path() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "LLM Spend Bar" / "bridge.sqlite"
    return Path.home() / ".local" / "share" / "llm-spend-bar" / "bridge.sqlite"


def env(name: str, fallback: str = "") -> str:
    return os.environ.get(name, fallback).strip()


def config_from_args(args: argparse.Namespace) -> Config:
    return Config(
        litellm_url=(args.litellm_url or env("LITELLM_BASE_URL", "http://127.0.0.1:4000")).rstrip("/"),
        litellm_key=args.litellm_key or env("LITELLM_MASTER_KEY"),
        hub_url=(args.hub_url or env("TOKEN_MONITOR_HUB_URL", "http://127.0.0.1:17321")).rstrip("/"),
        hub_secret=args.hub_secret if args.hub_secret is not None else env("TOKEN_MONITOR_SECRET"),
        device_id=args.device_id or env("TOKEN_MONITOR_DEVICE_ID", "litellm-proxy"),
        interval=max(5, int(args.interval)),
        db_path=Path(args.db).expanduser() if args.db else default_db_path(),
        since=args.since,
        page_size=max(1, min(1000, int(args.page_size))),
        max_pages=max(1, int(args.max_pages)),
        dry_run=bool(args.dry_run),
    )


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def as_dict(value: Any) -> Dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        try:
            parsed = json.loads(value)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}
    return {}


def as_str(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, (int, float)):
        return str(value)
    return ""


def first_str(*values: Any) -> str:
    for value in values:
        text = as_str(value)
        if text:
            return text
    return ""


def as_float(value: Any) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return 0.0
    return 0.0


def as_int(value: Any) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        try:
            return int(float(value))
        except ValueError:
            return 0
    return 0


def parse_dt(value: Any) -> Optional[dt.datetime]:
    text = as_str(value)
    if not text:
        return None
    text = text.replace(" ", "T")
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(text)
    except ValueError:
        for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d"):
            try:
                parsed = dt.datetime.strptime(text, fmt)
                break
            except ValueError:
                parsed = None
        if parsed is None:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def iso_utc(value: dt.datetime) -> str:
    value = value.astimezone(UTC)
    return value.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def api_date(value: dt.datetime) -> str:
    return value.astimezone(UTC).strftime("%Y-%m-%d %H:%M:%S")


def stable_project_id(label: str) -> str:
    digest = hashlib.sha256(label.encode("utf-8")).hexdigest()[:16]
    return "sha256:" + digest


def local_timezone_name() -> str:
    tz = dt.datetime.now().astimezone().tzinfo
    key = getattr(tz, "key", None)
    if key:
        return key
    name = dt.datetime.now().astimezone().tzname()
    return name or "local"


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------


def http_get_json(url: str, headers: Dict[str, str], timeout: float = 30.0) -> Any:
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw) if raw else None


def http_post_json(
    url: str,
    payload: Dict[str, Any],
    headers: Dict[str, str],
    timeout: float = 60.0,
) -> Tuple[int, str]:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(url, data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode("utf-8", errors="replace")


# ---------------------------------------------------------------------------
# LiteLLM parsing
# ---------------------------------------------------------------------------


@dataclass
class SpendEvent:
    request_id: str
    start_time: str
    end_time: str
    session_id: str
    project_label: str
    task_label: str
    client: str
    model: str
    provider: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    cache_read_tokens: int
    cache_write_tokens: int
    reasoning_tokens: int
    cost_usd: float
    status: str


def usage_components(metadata: Dict[str, Any]) -> Tuple[int, int, int]:
    usage = as_dict(metadata.get("usage_object"))
    prompt_details = as_dict(usage.get("prompt_tokens_details") or usage.get("input_tokens_details"))
    completion_details = as_dict(usage.get("completion_tokens_details") or usage.get("output_tokens_details"))
    cache_read = max(
        as_int(prompt_details.get("cached_tokens")),
        as_int(usage.get("cache_read_input_tokens")),
        as_int(usage.get("cache_read_tokens")),
    )
    cache_write = max(
        as_int(usage.get("cache_creation_input_tokens")),
        as_int(usage.get("cache_write_tokens")),
    )
    reasoning = max(
        as_int(completion_details.get("reasoning_tokens")),
        as_int(usage.get("reasoning_tokens")),
    )
    return cache_read, cache_write, reasoning


def parse_spend_log(row: Dict[str, Any]) -> Optional[SpendEvent]:
    started = parse_dt(row.get("startTime") or row.get("start_time") or row.get("created_at"))
    if not started:
        return None
    ended = parse_dt(row.get("endTime") or row.get("end_time")) or started

    metadata = as_dict(row.get("metadata"))
    spend_meta = as_dict(metadata.get("spend_logs_metadata"))

    request_id = as_str(row.get("request_id")) or as_str(row.get("id"))
    session_id = first_str(
        row.get("session_id"),
        metadata.get("session_id"),
        metadata.get("trace_id"),
        spend_meta.get("session_id"),
        spend_meta.get("trace_id"),
        request_id,
    )
    if not session_id:
        return None

    project_label = first_str(
        spend_meta.get("project_label"),
        spend_meta.get("project"),
        spend_meta.get("project_name"),
        metadata.get("project_label"),
        metadata.get("project"),
        spend_meta.get("task"),
        spend_meta.get("task_name"),
        spend_meta.get("title"),
        spend_meta.get("session_title"),
        metadata.get("title"),
        metadata.get("session_title"),
        row.get("end_user"),
        row.get("user"),
    )
    if project_label in ("default_user_id", "litellm_proxy_master_key") or project_label.startswith("litellm_proxy"):
        project_label = ""
    project_label = project_label or "LiteLLM"

    task_label = first_str(
        spend_meta.get("task"),
        spend_meta.get("task_name"),
        spend_meta.get("title"),
        spend_meta.get("session_title"),
        spend_meta.get("name"),
        metadata.get("task"),
        metadata.get("task_name"),
        project_label,
    ) or project_label

    client = first_str(
        spend_meta.get("client"),
        spend_meta.get("tool"),
        spend_meta.get("agent"),
        metadata.get("client"),
    ) or "litellm"
    # Keep client ids slug-safe; Token Monitor normalizes the rest.
    client = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in client.lower()).strip("-") or "litellm"

    model = first_str(row.get("model_group"), row.get("model"), row.get("model_id")) or "unknown"
    provider = first_str(row.get("custom_llm_provider"), row.get("api_base")) or "unknown"

    prompt_tokens = as_int(row.get("prompt_tokens"))
    completion_tokens = as_int(row.get("completion_tokens"))
    total_tokens = as_int(row.get("total_tokens")) or (prompt_tokens + completion_tokens)
    cache_read, cache_write, reasoning = usage_components(metadata)

    cost = as_float(row.get("spend"))
    if cost == 0:
        cost = as_float(row.get("response_cost"))

    return SpendEvent(
        request_id=request_id or session_id,
        start_time=iso_utc(started),
        end_time=iso_utc(ended),
        session_id=session_id,
        project_label=project_label,
        task_label=task_label,
        client=client,
        model=model,
        provider=provider,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
        cache_read_tokens=cache_read,
        cache_write_tokens=cache_write,
        reasoning_tokens=reasoning,
        cost_usd=cost,
        status=first_str(row.get("status")) or "success",
    )


def fetch_spend_logs(cfg: Config, start: dt.datetime, end: dt.datetime) -> Tuple[List[SpendEvent], bool]:
    if not cfg.litellm_key:
        raise RuntimeError("LITELLM_MASTER_KEY is not set")

    headers = {
        "Authorization": "Bearer " + cfg.litellm_key,
        "Accept": "application/json",
    }
    events: List[SpendEvent] = []
    truncated = False
    page = 1

    while page <= cfg.max_pages:
        query = urllib.parse.urlencode(
            {
                "start_date": api_date(start),
                "end_date": api_date(end),
                "page": page,
                "page_size": cfg.page_size,
            }
        )
        url = f"{cfg.litellm_url}/spend/logs/v2?{query}"
        try:
            payload = http_get_json(url, headers)
        except urllib.error.HTTPError as error:
            if error.code == 404 and page == 1:
                return fetch_legacy_logs(cfg, headers, start, end)
            if error.code in (401, 403):
                raise RuntimeError(f"LiteLLM rejected the master key (HTTP {error.code})")
            raise RuntimeError(f"LiteLLM /spend/logs/v2 returned HTTP {error.code}")

        if not isinstance(payload, dict):
            raise RuntimeError("LiteLLM /spend/logs/v2 returned an unexpected payload")
        rows = payload.get("data") or []
        if not isinstance(rows, list):
            raise RuntimeError("LiteLLM /spend/logs/v2 data is not an array")

        for row in rows:
            if isinstance(row, dict):
                event = parse_spend_log(row)
                if event:
                    events.append(event)

        total_pages = as_int(payload.get("total_pages"))
        if not rows:
            break
        if len(rows) < cfg.page_size:
            break
        if total_pages and page >= total_pages:
            if payload.get("total_is_capped"):
                truncated = True
            break
        if page == cfg.max_pages:
            truncated = True
            break
        page += 1

    return events, truncated


def fetch_legacy_logs(
    cfg: Config,
    headers: Dict[str, str],
    start: dt.datetime,
    end: dt.datetime,
) -> Tuple[List[SpendEvent], bool]:
    query = urllib.parse.urlencode(
        {
            "start_date": api_date(start),
            "end_date": api_date(end),
            "summarize": "false",
        }
    )
    url = f"{cfg.litellm_url}/spend/logs?{query}"
    payload = http_get_json(url, headers, timeout=60.0)
    rows = payload if isinstance(payload, list) else (payload or {}).get("data", [])
    events = [parse_spend_log(row) for row in rows if isinstance(row, dict)]
    return [event for event in events if event], False


# ---------------------------------------------------------------------------
# SQLite store
# ---------------------------------------------------------------------------


def open_db(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(str(path))
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS events (
            request_id TEXT PRIMARY KEY,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            session_id TEXT NOT NULL,
            project_label TEXT NOT NULL,
            task_label TEXT NOT NULL,
            client TEXT NOT NULL,
            model TEXT NOT NULL,
            provider TEXT NOT NULL,
            prompt_tokens INTEGER NOT NULL DEFAULT 0,
            completion_tokens INTEGER NOT NULL DEFAULT 0,
            total_tokens INTEGER NOT NULL DEFAULT 0,
            cache_read_tokens INTEGER NOT NULL DEFAULT 0,
            cache_write_tokens INTEGER NOT NULL DEFAULT 0,
            reasoning_tokens INTEGER NOT NULL DEFAULT 0,
            cost_usd REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'success'
        )
        """
    )
    connection.execute("CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_time)")
    connection.execute("CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id)")
    connection.execute("CREATE INDEX IF NOT EXISTS idx_events_project ON events(project_label)")
    connection.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    connection.commit()
    return connection


def upsert_events(connection: sqlite3.Connection, events: Iterable[SpendEvent]) -> int:
    rows = [
        (
            event.request_id,
            event.start_time,
            event.end_time,
            event.session_id,
            event.project_label,
            event.task_label,
            event.client,
            event.model,
            event.provider,
            event.prompt_tokens,
            event.completion_tokens,
            event.total_tokens,
            event.cache_read_tokens,
            event.cache_write_tokens,
            event.reasoning_tokens,
            event.cost_usd,
            event.status,
        )
        for event in events
    ]
    if not rows:
        return 0
    connection.executemany(
        """
        INSERT INTO events (
            request_id, start_time, end_time, session_id, project_label, task_label,
            client, model, provider, prompt_tokens, completion_tokens, total_tokens,
            cache_read_tokens, cache_write_tokens, reasoning_tokens, cost_usd, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(request_id) DO UPDATE SET
            start_time=excluded.start_time,
            end_time=excluded.end_time,
            session_id=excluded.session_id,
            project_label=excluded.project_label,
            task_label=excluded.task_label,
            client=excluded.client,
            model=excluded.model,
            provider=excluded.provider,
            prompt_tokens=excluded.prompt_tokens,
            completion_tokens=excluded.completion_tokens,
            total_tokens=excluded.total_tokens,
            cache_read_tokens=excluded.cache_read_tokens,
            cache_write_tokens=excluded.cache_write_tokens,
            reasoning_tokens=excluded.reasoning_tokens,
            cost_usd=excluded.cost_usd,
            status=excluded.status
        """,
        rows,
    )
    connection.commit()
    return len(rows)


def get_meta(connection: sqlite3.Connection, key: str) -> str:
    row = connection.execute("SELECT value FROM meta WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else ""


def set_meta(connection: sqlite3.Connection, key: str, value: str) -> None:
    connection.execute(
        "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        (key, value),
    )
    connection.commit()


# ---------------------------------------------------------------------------
# Aggregation for Token Monitor
# ---------------------------------------------------------------------------


def _add(mapping: Dict[str, float], key: str, value: float) -> None:
    if not key:
        return
    mapping[key] = mapping.get(key, 0) + value


def aggregate_period(
    connection: sqlite3.Connection,
    start_iso: str,
    end_iso: str,
    include_sessions: bool,
) -> Dict[str, Any]:
    rows = connection.execute(
        "SELECT * FROM events WHERE start_time >= ? AND start_time < ? ORDER BY start_time ASC",
        (start_iso, end_iso),
    ).fetchall()

    total_tokens = 0
    cost = 0.0
    cache_read = 0
    cache_write = 0
    output_tokens = 0
    clients: Dict[str, float] = {}
    client_costs: Dict[str, float] = {}
    client_cache_reads: Dict[str, float] = {}
    client_cache_writes: Dict[str, float] = {}
    client_outputs: Dict[str, float] = {}
    models: Dict[str, float] = {}
    model_costs: Dict[str, float] = {}
    model_cache_reads: Dict[str, float] = {}
    model_cache_writes: Dict[str, float] = {}
    model_outputs: Dict[str, float] = {}
    client_models: Dict[str, Dict[str, float]] = {}
    client_model_costs: Dict[str, Dict[str, float]] = {}
    projects: Dict[str, Dict[str, Any]] = {}
    sessions: Dict[str, Dict[str, Any]] = {}

    for row in rows:
        tokens = int(row["total_tokens"] or 0)
        event_cost = float(row["cost_usd"] or 0)
        event_cache_read = int(row["cache_read_tokens"] or 0)
        event_cache_write = int(row["cache_write_tokens"] or 0)
        event_output = int(row["completion_tokens"] or 0)
        client = row["client"] or "litellm"
        model = row["model"] or "unknown"
        project = row["project_label"] or "LiteLLM"

        total_tokens += tokens
        cost += event_cost
        cache_read += event_cache_read
        cache_write += event_cache_write
        output_tokens += event_output

        _add(clients, client, tokens)
        _add(client_costs, client, event_cost)
        _add(client_cache_reads, client, event_cache_read)
        _add(client_cache_writes, client, event_cache_write)
        _add(client_outputs, client, event_output)
        _add(models, model, tokens)
        _add(model_costs, model, event_cost)
        _add(model_cache_reads, model, event_cache_read)
        _add(model_cache_writes, model, event_cache_write)
        _add(model_outputs, model, event_output)
        client_models.setdefault(client, {})
        _add(client_models[client], model, tokens)
        client_model_costs.setdefault(client, {})
        _add(client_model_costs[client], model, event_cost)

        project_entry = projects.setdefault(
            project,
            {"label": project, "tokens": 0, "costUsd": 0.0, "clients": {}, "models": {}},
        )
        project_entry["tokens"] += tokens
        project_entry["costUsd"] += event_cost
        _add(project_entry["clients"], client, tokens)
        _add(project_entry["models"], model, tokens)

        if include_sessions:
            key = f"{client}:{row['session_id']}"
            session = sessions.get(key)
            if not session:
                session = {
                    "client": client,
                    "sessionId": row["session_id"],
                    "totalTokens": 0,
                    "costUsd": 0.0,
                    "messageCount": 0,
                    "inputTokens": 0,
                    "outputTokens": 0,
                    "cacheReadTokens": 0,
                    "cacheWriteTokens": 0,
                    "reasoningTokens": 0,
                    "startedAt": row["start_time"],
                    "lastUsedAt": row["end_time"],
                    "projectId": stable_project_id(project),
                    "projectLabel": project,
                    "models": {},
                    "modelCosts": {},
                    "providers": {},
                }
                sessions[key] = session
            session["totalTokens"] += tokens
            session["costUsd"] += event_cost
            session["messageCount"] += 1
            session["outputTokens"] += event_output
            session["cacheReadTokens"] += event_cache_read
            session["cacheWriteTokens"] += event_cache_write
            session["reasoningTokens"] += int(row["reasoning_tokens"] or 0)
            if row["start_time"] < session["startedAt"]:
                session["startedAt"] = row["start_time"]
            if row["end_time"] > session["lastUsedAt"]:
                session["lastUsedAt"] = row["end_time"]
            _add(session["models"], model, tokens)
            _add(session["modelCosts"], model, event_cost)
            _add(session["providers"], row["provider"] or "unknown", tokens)

    # Component accounting: the residual is non-cache input. This keeps the
    # component sum equal to the total without pretending to know how the
    # provider split cache reads internally.
    unclassified = max(0, total_tokens - (cache_read + cache_write + output_tokens))
    for session in sessions.values():
        known = session["cacheReadTokens"] + session["cacheWriteTokens"] + session["outputTokens"]
        session["inputTokens"] = max(0, session["totalTokens"] - known)

    result: Dict[str, Any] = {
        "capabilities": {"tokenComponents": True, "throughput": False},
        "totalTokens": total_tokens,
        "costUsd": cost,
        "cacheReadTokens": cache_read,
        "cacheWriteTokens": cache_write,
        "outputTokens": output_tokens,
        "clients": clients,
        "clientCosts": client_costs,
        "clientCacheReads": client_cache_reads,
        "clientCacheWrites": client_cache_writes,
        "clientOutputs": client_outputs,
        "models": models,
        "modelCosts": model_costs,
        "modelCacheReads": model_cache_reads,
        "modelCacheWrites": model_cache_writes,
        "modelOutputs": model_outputs,
        "clientModels": client_models,
        "clientModelCosts": client_model_costs,
        "projects": projects,
    }
    if unclassified > 0:
        result["unclassifiedTokens"] = unclassified
    if include_sessions:
        result["sessions"] = sessions
    return result


def build_payload(connection: sqlite3.Connection, cfg: Config, now: Optional[dt.datetime] = None) -> Dict[str, Any]:
    now = (now or dt.datetime.now(UTC)).astimezone(UTC)
    local = now.astimezone()
    day_start = local.replace(hour=0, minute=0, second=0, microsecond=0)
    month_start = day_start.replace(day=1)
    since = dt.datetime.strptime(cfg.since, "%Y-%m-%d").replace(tzinfo=UTC)

    next_day = day_start + dt.timedelta(days=1)
    if month_start.month == 12:
        next_month = month_start.replace(year=month_start.year + 1, month=1)
    else:
        next_month = month_start.replace(month=month_start.month + 1)

    today = aggregate_period(connection, iso_utc(day_start), iso_utc(now + dt.timedelta(seconds=1)), True)
    month = aggregate_period(connection, iso_utc(month_start), iso_utc(now + dt.timedelta(seconds=1)), True)
    all_time = aggregate_period(connection, iso_utc(since), iso_utc(now + dt.timedelta(seconds=1)), False)

    omitted: Dict[str, int] = {}
    for name, period in (("today", today), ("month", month)):
        sessions = period.get("sessions") or {}
        if len(sessions) > MAX_SESSIONS_PER_PERIOD:
            keep = sorted(sessions.items(), key=lambda item: item[1].get("lastUsedAt", ""), reverse=True)[:MAX_SESSIONS_PER_PERIOD]
            omitted[name] = len(sessions) - len(keep)
            period["sessions"] = dict(keep)

    for period in (today, month, all_time):
        projects = period.get("projects") or {}
        if len(projects) > MAX_PROJECTS:
            keep = sorted(projects.items(), key=lambda item: item[1].get("tokens", 0), reverse=True)[:MAX_PROJECTS]
            period["projects"] = dict(keep)

    payload: Dict[str, Any] = {
        "deviceId": cfg.device_id,
        "hostname": socket.gethostname(),
        "platform": f"{sys.platform}-{platform.machine()}",
        "osName": platform.system(),
        "osVersion": platform.release(),
        "updatedAt": iso_utc(now),
        "agentVersion": "0.1.0",
        "agentRuntime": "llm-spend-bar-bridge",
        "trackedClients": ["litellm"],
        "today": today,
        "month": month,
        "allTime": all_time,
        "periodWindows": {
            "timeZone": local_timezone_name(),
            "today": {
                "key": day_start.strftime("%Y-%m-%d"),
                "endsAt": iso_utc(next_day),
            },
            "month": {
                "key": month_start.strftime("%Y-%m"),
                "endsAt": iso_utc(next_month),
            },
        },
        "syncUploadIntervalMs": cfg.interval * 1000,
    }
    if omitted:
        payload["sessionDetailsOmitted"] = omitted
    return payload


def fit_payload(payload: Dict[str, Any]) -> Tuple[Dict[str, Any], int]:
    """Trim session detail until the payload fits Token Monitor's 1 MiB ingest cap."""
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    size = len(data.encode("utf-8"))
    if size <= MAX_PAYLOAD_BYTES:
        return payload, size

    omitted = dict(payload.get("sessionDetailsOmitted") or {})
    for period_name in ("today", "month"):
        period = payload.get(period_name) or {}
        sessions = period.get("sessions") or {}
        while sessions and size > MAX_PAYLOAD_BYTES:
            keep_count = max(0, len(sessions) // 2)
            keep = sorted(sessions.items(), key=lambda item: item[1].get("lastUsedAt", ""), reverse=True)[:keep_count]
            omitted[period_name] = omitted.get(period_name, 0) + (len(sessions) - len(keep))
            period["sessions"] = dict(keep)
            sessions = period["sessions"]
            payload["sessionDetailsOmitted"] = omitted
            size = len(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))

    if size > MAX_PAYLOAD_BYTES and "projects" in (payload.get("allTime") or {}):
        payload["allTime"].pop("projects", None)
        payload["allTimeProjectsOmitted"] = True
        size = len(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))

    if size > MAX_PAYLOAD_BYTES:
        for period_name in ("today", "month"):
            period = payload.get(period_name) or {}
            if period.get("sessions"):
                omitted[period_name] = omitted.get(period_name, 0) + len(period["sessions"])
                period["sessions"] = {}
        payload["sessionDetailsOmitted"] = omitted
        size = len(json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))

    return payload, size


# ---------------------------------------------------------------------------
# Sync
# ---------------------------------------------------------------------------


def sync_once(cfg: Config, connection: sqlite3.Connection) -> Dict[str, Any]:
    now = dt.datetime.now(UTC)
    last = get_meta(connection, "last_sync")
    if last:
        last_dt = parse_dt(last) or (now - dt.timedelta(days=1))
        start = last_dt - dt.timedelta(minutes=10)
    else:
        start = dt.datetime.strptime(cfg.since, "%Y-%m-%d").replace(tzinfo=UTC)

    events, truncated = fetch_spend_logs(cfg, start, now)
    written = upsert_events(connection, events)
    set_meta(connection, "last_sync", iso_utc(now))

    payload = build_payload(connection, cfg, now)
    payload, size = fit_payload(payload)

    if cfg.dry_run:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return {"fetched": len(events), "written": written, "bytes": size, "truncated": truncated}

    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if cfg.hub_secret:
        headers["Authorization"] = "Bearer " + cfg.hub_secret
    status, body = http_post_json(cfg.hub_url + "/api/ingest", payload, headers)
    if status == 413:
        payload, size = fit_payload(payload)
        status, body = http_post_json(cfg.hub_url + "/api/ingest", payload, headers)
    if status < 200 or status >= 300:
        raise RuntimeError(f"Token Monitor hub returned HTTP {status}: {body[:500]}")

    return {"fetched": len(events), "written": written, "bytes": size, "truncated": truncated}


def print_stats(connection: sqlite3.Connection) -> None:
    count = connection.execute("SELECT COUNT(*) AS n FROM events").fetchone()["n"]
    total = connection.execute("SELECT COALESCE(SUM(cost_usd), 0) AS c FROM events").fetchone()["c"]
    print(f"events: {count}, cost: ${total:.6f}")
    for row in connection.execute(
        "SELECT project_label, COUNT(*) AS n, SUM(cost_usd) AS cost FROM events GROUP BY project_label ORDER BY cost DESC LIMIT 10"
    ):
        print(f"  {row['project_label']:<32} {row['n']:>6} запросов  ${row['cost']:.6f}")


def run_loop(cfg: Config) -> None:
    connection = open_db(cfg.db_path)
    stopping = False

    def stop(_signum: int, _frame: Any) -> None:
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    while not stopping:
        try:
            result = sync_once(cfg, connection)
            print(
                f"[{dt.datetime.now().strftime('%H:%M:%S')}] "
                f"fetched={result['fetched']} written={result['written']} bytes={result['bytes']}"
                + (" truncated" if result["truncated"] else "")
            )
        except Exception as error:  # noqa: BLE001 - keep the daemon alive
            print(f"[{dt.datetime.now().strftime('%H:%M:%S')}] error: {error}", file=sys.stderr)
        for _ in range(cfg.interval):
            if stopping:
                break
            time.sleep(1)
    connection.close()


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Bridge LiteLLM spend logs into Token Monitor Hub")
    parser.add_argument("--litellm-url", default="")
    parser.add_argument("--litellm-key", default="")
    parser.add_argument("--hub-url", default="")
    parser.add_argument("--hub-secret", default=None)
    parser.add_argument("--device-id", default="")
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--db", default="")
    parser.add_argument("--since", default=DEFAULT_SINCE)
    parser.add_argument("--page-size", type=int, default=DEFAULT_PAGE_SIZE)
    parser.add_argument("--max-pages", type=int, default=DEFAULT_MAX_PAGES)
    parser.add_argument("--once", action="store_true", help="sync once (default)")
    parser.add_argument("--loop", action="store_true", help="run continuously")
    parser.add_argument("--dry-run", action="store_true", help="print the Token Monitor payload instead of posting")
    parser.add_argument("--print-stats", action="store_true", help="print local bridge statistics and exit")
    args = parser.parse_args(argv)

    cfg = config_from_args(args)
    if not cfg.litellm_key and not args.print_stats:
        print("LITELLM_MASTER_KEY is not set (or pass --litellm-key)", file=sys.stderr)
        return 2

    if args.print_stats:
        connection = open_db(cfg.db_path)
        print_stats(connection)
        connection.close()
        return 0

    if args.loop:
        run_loop(cfg)
        return 0

    connection = open_db(cfg.db_path)
    try:
        result = sync_once(cfg, connection)
        print(
            f"fetched={result['fetched']} written={result['written']} bytes={result['bytes']}"
            + (" truncated" if result["truncated"] else "")
        )
        return 0
    except Exception as error:  # noqa: BLE001
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        connection.close()


if __name__ == "__main__":
    raise SystemExit(main())
