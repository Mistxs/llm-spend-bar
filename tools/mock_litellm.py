#!/usr/bin/env python3
"""Небольшой mock LiteLLM для разработки менюбара.

Слушает /health/liveliness, /spend/logs/v2, /spend/logs и /ui.
Запуск: python3 tools/mock_litellm.py [--port 4010]
"""

import argparse
import datetime as dt
import json
import random
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

random.seed(42)

MODELS = [
    ("gpt-5.1", "openai", 1.25e-6, 1.0e-5),
    ("claude-sonnet-4.5", "anthropic", 3.0e-6, 1.5e-5),
    ("gemini-2.5-pro", "google", 1.25e-6, 1.0e-5),
    ("deepseek-chat", "deepseek", 2.7e-7, 1.1e-6),
]

SESSIONS = [
    ("ses_opencode_auth", "opencode · auth refactor", "gpt-5.1"),
    ("ses_chatgpt_sql", "ChatGPT · SQL review", "gpt-5.1"),
    ("ses_claude_payments", "Claude Code · payments", "claude-sonnet-4.5"),
    ("ses_codex_tests", "Codex · flaky tests", "gemini-2.5-pro"),
    ("ses_deepseek_docs", "DeepSeek · docs", "deepseek-chat"),
]


def iso(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def build_logs() -> list[dict]:
    now = dt.datetime.now(dt.timezone.utc)
    logs: list[dict] = []

    # Несколько запросов на каждую сессию сегодня.
    for index, (session_id, title, model) in enumerate(SESSIONS):
        info = next(item for item in MODELS if item[0] == model)
        count = 3 + index * 2
        for step in range(count):
            started = now - dt.timedelta(minutes=(index + 1) * 17 + step * 3)
            prompt = random.randint(1200, 18000)
            completion = random.randint(120, 2400)
            spend = prompt * info[2] + completion * info[3]
            logs.append({
                "request_id": "chatcmpl-" + uuid.uuid4().hex[:24],
                "call_type": "acompletion",
                "api_key": "hash_local_dev",
                "spend": round(spend, 8),
                "total_tokens": prompt + completion,
                "prompt_tokens": prompt,
                "completion_tokens": completion,
                "startTime": iso(started),
                "endTime": iso(started + dt.timedelta(seconds=random.randint(2, 40))),
                "model": model,
                "model_id": model,
                "model_group": model,
                "custom_llm_provider": info[1],
                "api_base": "https://api.example.com/v1",
                "user": "local",
                "metadata": {
                    "user_api_key_alias": "dev",
                    "spend_logs_metadata": {"session_id": session_id, "title": title},
                },
                "cache_hit": "true" if step % 4 == 0 else "false",
                "request_tags": ["mock"],
                "team_id": None,
                "organization_id": None,
                "end_user": "local",
                "requester_ip_address": "127.0.0.1",
                "session_id": session_id,
                "status": "success",
                "litellm_call_id": uuid.uuid4().hex,
                "request_duration_ms": random.randint(900, 9000),
            })

    # Пара запросов на прошлой неделе и в прошлом месяце.
    for days_ago, session_id, title, model in [
        (3, "ses_week_1", "opencode · weekly review", "gpt-5.1"),
        (5, "ses_week_2", "Claude Code · refactor", "claude-sonnet-4.5"),
        (12, "ses_month_1", "ChatGPT · migration", "gpt-5.1"),
        (18, "ses_month_2", "Gemini · research", "gemini-2.5-pro"),
    ]:
        info = next(item for item in MODELS if item[0] == model)
        started = now - dt.timedelta(days=days_ago, hours=2)
        prompt = random.randint(5000, 30000)
        completion = random.randint(500, 4000)
        spend = prompt * info[2] + completion * info[3]
        logs.append({
            "request_id": "chatcmpl-" + uuid.uuid4().hex[:24],
            "call_type": "acompletion",
            "api_key": "hash_local_dev",
            "spend": round(spend, 8),
            "total_tokens": prompt + completion,
            "prompt_tokens": prompt,
            "completion_tokens": completion,
            "startTime": iso(started),
            "endTime": iso(started + dt.timedelta(seconds=20)),
            "model": model,
            "model_id": model,
            "model_group": model,
            "custom_llm_provider": info[1],
            "api_base": "https://api.example.com/v1",
            "user": "local",
            "metadata": {
                "user_api_key_alias": "dev",
                "spend_logs_metadata": {"session_id": session_id, "title": title},
            },
            "cache_hit": "false",
            "request_tags": ["mock"],
            "session_id": session_id,
            "status": "success",
            "litellm_call_id": uuid.uuid4().hex,
            "request_duration_ms": random.randint(900, 9000),
        })

    logs.sort(key=lambda row: row["startTime"], reverse=True)
    return logs


LOGS = build_logs()


class Handler(BaseHTTPRequestHandler):
    server_version = "MockLiteLLM/0.1"

    def log_message(self, fmt, *args):
        print("[mock] " + fmt % args)

    def send_json(self, payload, status=200, headers=None):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)

        if path in ("/health", "/health/liveliness"):
            self.send_json({"status": "healthy"})
            return

        if path == "/spend/logs/v2":
            page = max(1, int(query.get("page", ["1"])[0]))
            page_size = min(1000, max(1, int(query.get("page_size", ["50"])[0])))
            start = query.get("start_date", [""])[0]
            end = query.get("end_date", [""])[0]
            rows = [row for row in LOGS if (not start or row["startTime"] >= start.replace(" ", "T")) and (not end or row["startTime"] <= end.replace(" ", "T"))]
            total = len(rows)
            total_pages = (total + page_size - 1) // page_size if total else 0
            chunk = rows[(page - 1) * page_size: page * page_size]
            self.send_json({
                "data": chunk,
                "total": total,
                "page": page,
                "page_size": page_size,
                "total_pages": total_pages,
                "total_is_capped": False,
            })
            return

        if path == "/spend/logs":
            self.send_json(LOGS)
            return

        if path == "/ui":
            body = b"<!doctype html><meta charset=utf-8><title>Mock LiteLLM</title><h1>Mock LiteLLM UI</h1><p>This is a mock. Use /spend/logs/v2.</p>"
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_json({"error": "not found"}, status=404)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4010)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Mock LiteLLM: http://127.0.0.1:{args.port}")
    print(f"  GET /spend/logs/v2?page=1&page_size=1000")
    print(f"  {len(LOGS)} mock requests, {len(SESSIONS)} sessions")
    server.serve_forever()


if __name__ == "__main__":
    main()
