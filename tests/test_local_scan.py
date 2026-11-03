import datetime as dt
import json
import os
import sqlite3
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / "build" / "LLM Spend Bar.app" / "Contents" / "MacOS" / "LLMSpendBar"


def iso(value):
    return value.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def ms(value):
    return int(value.timestamp() * 1000)


class LocalScanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.data = self.root / "data"
        self.claude = self.root / "claude"
        self.codex = self.root / "codex"
        self.opencode = self.root / "opencode.db"
        self.snapshot = self.root / "snapshot.json"
        self.now = dt.datetime.now(dt.timezone.utc)

    def tearDown(self):
        self.tmp.cleanup()

    def write_claude(self):
        project = self.claude / "projects" / "demo-project"
        project.mkdir(parents=True)
        path = project / "session.jsonl"
        first = self.now - dt.timedelta(hours=2)
        second = self.now - dt.timedelta(hours=1)
        lines = [
            {
                "type": "assistant",
                "sessionId": "claude-test",
                "timestamp": iso(first),
                "cwd": "/tmp/demo-project",
                "requestId": "req-c1",
                "message": {
                    "id": "msg-c1",
                    "model": "claude-sonnet-4.5",
                    "usage": {
                        "input_tokens": 1000,
                        "output_tokens": 50,
                        "cache_read_input_tokens": 2000,
                        "cache_creation_input_tokens": 100,
                    },
                },
            },
            # Streaming repeat for the same message: must update, not double count.
            {
                "type": "assistant",
                "sessionId": "claude-test",
                "timestamp": iso(first + dt.timedelta(seconds=2)),
                "cwd": "/tmp/demo-project",
                "requestId": "req-c1",
                "message": {
                    "id": "msg-c1",
                    "model": "claude-sonnet-4.5",
                    "usage": {
                        "input_tokens": 1000,
                        "output_tokens": 100,
                        "cache_read_input_tokens": 2000,
                        "cache_creation_input_tokens": 100,
                    },
                },
            },
            {
                "type": "assistant",
                "sessionId": "claude-test",
                "timestamp": iso(second),
                "cwd": "/tmp/demo-project",
                "requestId": "req-c2",
                "message": {
                    "id": "msg-c2",
                    "model": "claude-sonnet-4.5",
                    "usage": {
                        "input_tokens": 500,
                        "output_tokens": 20,
                        "cache_read_input_tokens": 0,
                        "cache_creation_input_tokens": 0,
                    },
                },
            },
        ]
        path.write_text("\n".join(json.dumps(line) for line in lines) + "\n", encoding="utf-8")

    def write_codex(self):
        sessions = self.codex / "sessions"
        sessions.mkdir(parents=True)
        path = sessions / "codex-test.jsonl"
        first = self.now - dt.timedelta(minutes=40)
        second = self.now - dt.timedelta(minutes=20)
        lines = [
            {
                "timestamp": iso(first),
                "type": "session_meta",
                "payload": {
                    "id": "codex-test",
                    "cwd": "/tmp/demo-codex",
                    "model": "gpt-5.1",
                    "model_provider": "openai",
                },
            },
            {
                "timestamp": iso(first),
                "type": "turn_context",
                "payload": {"model": "gpt-5.1"},
            },
            {
                "timestamp": iso(first + dt.timedelta(seconds=5)),
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "last_token_usage": {
                            "input_tokens": 500,
                            "cached_input_tokens": 100,
                            "output_tokens": 50,
                            "reasoning_output_tokens": 10,
                            "total_tokens": 550,
                        }
                    },
                },
            },
            {
                "timestamp": iso(second),
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "last_token_usage": {
                            "input_tokens": 700,
                            "cached_input_tokens": 200,
                            "output_tokens": 70,
                            "reasoning_output_tokens": 15,
                            "total_tokens": 770,
                        }
                    },
                },
            },
        ]
        path.write_text("\n".join(json.dumps(line) for line in lines) + "\n", encoding="utf-8")

    def write_opencode(self):
        connection = sqlite3.connect(self.opencode)
        connection.executescript(
            """
            CREATE TABLE project (id TEXT PRIMARY KEY, name TEXT);
            CREATE TABLE session_v2 (
                id TEXT PRIMARY KEY, project_id TEXT, title TEXT, directory TEXT,
                time_created INTEGER, time_updated INTEGER
            );
            CREATE TABLE session_message (
                id TEXT PRIMARY KEY, session_id TEXT, type TEXT, time_created INTEGER, data TEXT
            );
            """
        )
        now_ms = ms(self.now)
        connection.execute("INSERT INTO project (id, name) VALUES ('p1', 'opencode-fixture')")
        connection.execute(
            "INSERT INTO session_v2 (id, project_id, title, directory, time_created, time_updated)"
            " VALUES ('ses-opencode', 'p1', 'OpenCode fixture session', '/tmp/opencode-fixture', ?, ?)",
            (now_ms - 3600_000, now_ms),
        )
        data = {
            "tokens": {
                "input": 300,
                "output": 40,
                "reasoning": 10,
                "cache": {"read": 1000, "write": 0},
            },
            "model": {"id": "deepseek-v4.1-flash", "providerID": "opencode-go"},
            "cost": 0,
            "time": {"created": now_ms - 1800_000, "completed": now_ms - 1700_000},
        }
        connection.execute(
            "INSERT INTO session_message (id, session_id, type, time_created, data) VALUES (?, ?, ?, ?, ?)",
            ("msg-opencode", "ses-opencode", "assistant", now_ms - 1800_000, json.dumps(data)),
        )
        connection.commit()
        connection.close()

    def run_scan(self):
        if not BINARY.exists():
            self.skipTest(f"binary not built: {BINARY}")
        env = os.environ.copy()
        env.update(
            {
                "LSB_DATA_DIR": str(self.data),
                "CLAUDE_PROJECTS_DIR": str(self.claude / "projects"),
                "CODEX_SESSIONS_DIR": str(self.codex / "sessions"),
                "OPENCODE_DB": str(self.opencode),
                "TZ": "UTC",
            }
        )
        result = subprocess.run(
            [str(BINARY), "--dashboard-json", str(self.snapshot)],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertTrue(self.snapshot.exists(), result.stderr + result.stdout)
        return json.loads(self.snapshot.read_text(encoding="utf-8"))

    def test_scan_all_sources(self):
        self.write_claude()
        self.write_codex()
        self.write_opencode()
        snapshot = self.run_scan()

        tools = {row["name"] for row in snapshot["tools"]}
        self.assertEqual(tools, {"claude", "codex", "opencode"})
        self.assertGreaterEqual(snapshot["totals"]["requests"], 5)
        self.assertGreater(snapshot["totals"]["tokens"], 0)
        self.assertGreater(snapshot["totals"]["spend"], 0)
        self.assertEqual(snapshot["budgets"]["daily"], 10)

        sessions = {row["id"]: row for row in snapshot["sessions"]}
        self.assertIn("claude-test", sessions)
        self.assertEqual(sessions["claude-test"]["requests"], 2)
        self.assertIn("codex-test", sessions)
        self.assertEqual(sessions["codex-test"]["requests"], 2)
        self.assertIn("ses-opencode", sessions)

        jsonl = self.data / "events.jsonl"
        self.assertTrue(jsonl.exists())
        self.assertGreater(len(jsonl.read_text(encoding="utf-8").strip().splitlines()), 0)


if __name__ == "__main__":
    unittest.main()
