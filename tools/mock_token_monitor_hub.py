#!/usr/bin/env python3
"""Minimal Token Monitor hub mock for bridge development.

Accepts POST /api/ingest and writes the last payload to --out.
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    server_version = "MockTokenMonitorHub/0.1"
    out_path = Path("/tmp/token-monitor-ingest.json")

    def log_message(self, fmt, *args):
        print("[tm-hub] " + fmt % args)

    def send_json(self, payload, status=200):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", "/api/health"):
            self.send_json({"ok": True, "role": "mock-hub"})
            return
        self.send_json({"error": "not found"}, status=404)

    def do_POST(self):
        if self.path.rstrip("/") != "/api/ingest":
            self.send_json({"error": "not found"}, status=404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            self.send_json({"error": "invalid JSON"}, status=400)
            return
        self.out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[tm-hub] ingested {len(raw)} bytes from {payload.get('deviceId')}")
        self.send_json({"ok": True})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=17321)
    parser.add_argument("--out", default="/tmp/token-monitor-ingest.json")
    args = parser.parse_args()
    Handler.out_path = Path(args.out)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Mock Token Monitor hub: http://127.0.0.1:{args.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
