#!/usr/bin/env python3
"""Mock OpenAI-совместимый провайдер для end-to-end теста LiteLLM.

Запуск: python3 tools/mock_provider.py --port 4011
"""

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    server_version = "MockProvider/0.1"

    def log_message(self, fmt, *args):
        print("[provider] " + fmt % args)

    def send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            self.send_json({"object": "list", "data": [{"id": "mock-gpt", "object": "model"}]})
            return
        self.send_json({"error": "not found"}, status=404)

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            self.send_json({"error": "not found"}, status=404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            request = json.loads(raw)
        except json.JSONDecodeError:
            request = {}

        prompt = sum(len(str(message.get("content", ""))) for message in request.get("messages", []))
        prompt_tokens = max(12, prompt // 4)
        completion_tokens = 7
        self.send_json({
            "id": "chatcmpl-mock-" + str(int(time.time() * 1000)),
            "object": "chat.completion",
            "created": int(time.time()),
            "model": request.get("model", "mock-gpt"),
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": "Hello from the mock provider."},
                "finish_reason": "stop",
            }],
            "usage": {
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "total_tokens": prompt_tokens + completion_tokens,
            },
        })


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4011)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Mock provider: http://127.0.0.1:{args.port}/v1")
    server.serve_forever()


if __name__ == "__main__":
    main()
