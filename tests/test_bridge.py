import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path

from bridge import litellm_bridge as bridge


UTC = dt.timezone.utc


def event(request_id, when, session, project, model, tokens, cost, cache_read=0, output=0):
    return bridge.SpendEvent(
        request_id=request_id,
        start_time=bridge.iso_utc(when),
        end_time=bridge.iso_utc(when + dt.timedelta(seconds=10)),
        session_id=session,
        project_label=project,
        task_label=project,
        client="litellm",
        model=model,
        provider="openai",
        prompt_tokens=max(0, tokens - output),
        completion_tokens=output,
        total_tokens=tokens,
        cache_read_tokens=cache_read,
        cache_write_tokens=0,
        reasoning_tokens=0,
        cost_usd=cost,
        status="success",
    )


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = Path(self.tmp.name) / "bridge.sqlite"
        self.conn = bridge.open_db(self.db)
        self.now = dt.datetime(2026, 11, 3, 12, 0, tzinfo=UTC)
        bridge.upsert_events(
            self.conn,
            [
                event("r1", dt.datetime(2026, 11, 3, 10, 0, tzinfo=UTC), "ses_a", "auth refactor", "gpt-5.1", 1000, 0.01, 200, 100),
                event("r2", dt.datetime(2026, 11, 3, 11, 0, tzinfo=UTC), "ses_a", "auth refactor", "claude-sonnet-4.5", 500, 0.02),
                event("r3", dt.datetime(2026, 11, 3, 9, 0, tzinfo=UTC), "ses_b", "sql review", "gpt-5.1", 300, 0.005),
                event("r4", dt.datetime(2026, 11, 1, 9, 0, tzinfo=UTC), "ses_c", "auth refactor", "gpt-5.1", 4000, 0.1),
                event("r5", dt.datetime(2026, 10, 20, 9, 0, tzinfo=UTC), "ses_d", "old", "gpt-5.1", 5000, 0.2),
            ],
        )
        self.cfg = bridge.Config(
            litellm_url="http://127.0.0.1:4000",
            litellm_key="sk-test",
            hub_url="http://127.0.0.1:17321",
            hub_secret="",
            device_id="litellm-proxy",
            interval=60,
            db_path=self.db,
            since="2024-01-01",
            page_size=1000,
            max_pages=10,
        )

    def tearDown(self):
        self.conn.close()
        self.tmp.cleanup()

    def test_parse_spend_log_metadata(self):
        row = {
            "request_id": "req-1",
            "startTime": "2026-11-03T10:00:00.123456+00:00",
            "endTime": "2026-11-03T10:00:03.000000+00:00",
            "model_group": "gpt-5.1",
            "custom_llm_provider": "openai",
            "spend": 0.012,
            "total_tokens": 1500,
            "prompt_tokens": 1200,
            "completion_tokens": 300,
            "session_id": "ses_x",
            "metadata": json.dumps(
                {
                    "spend_logs_metadata": {
                        "project": "billing",
                        "task": "refactor checkout",
                        "title": "Checkout refactor",
                    },
                    "usage_object": {
                        "prompt_tokens_details": {"cached_tokens": 400},
                        "completion_tokens_details": {"reasoning_tokens": 50},
                    },
                }
            ),
        }
        parsed = bridge.parse_spend_log(row)
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed.session_id, "ses_x")
        self.assertEqual(parsed.project_label, "billing")
        self.assertEqual(parsed.task_label, "refactor checkout")
        self.assertEqual(parsed.cache_read_tokens, 400)
        self.assertEqual(parsed.reasoning_tokens, 50)
        self.assertEqual(parsed.cost_usd, 0.012)

    def test_build_payload_totals_and_sessions(self):
        payload = bridge.build_payload(self.conn, self.cfg, self.now)
        today = payload["today"]
        month = payload["month"]
        all_time = payload["allTime"]

        self.assertEqual(today["totalTokens"], 1800)
        self.assertAlmostEqual(today["costUsd"], 0.035, places=6)
        self.assertEqual(month["totalTokens"], 5800)
        self.assertAlmostEqual(month["costUsd"], 0.135, places=6)
        self.assertEqual(all_time["totalTokens"], 10800)
        self.assertAlmostEqual(all_time["costUsd"], 0.335, places=6)

        self.assertIn("litellm:ses_a", today["sessions"])
        self.assertEqual(today["sessions"]["litellm:ses_a"]["projectLabel"], "auth refactor")
        self.assertEqual(today["sessions"]["litellm:ses_a"]["messageCount"], 2)
        self.assertIn("auth refactor", today["projects"])
        self.assertIn("sql review", today["projects"])
        self.assertNotIn("sessions", all_time)
        self.assertIn("old", all_time["projects"])
        self.assertEqual(payload["trackedClients"], ["litellm"])

    def test_fit_payload_trims_sessions(self):
        payload = bridge.build_payload(self.conn, self.cfg, self.now)
        big = dict(payload)
        big["today"] = dict(payload["today"])
        big["today"]["sessions"] = {
            f"litellm:s{i}": {
                "client": "litellm",
                "sessionId": f"s{i}",
                "totalTokens": 100,
                "costUsd": 0.01,
                "lastUsedAt": f"2026-11-03T10:{i % 60:02d}:00Z",
                "projectLabel": "x" * 200,
            }
            for i in range(3000)
        }
        fitted, size = bridge.fit_payload(big)
        self.assertLessEqual(size, bridge.MAX_PAYLOAD_BYTES)
        self.assertLess(len(fitted["today"]["sessions"]), 3000)


if __name__ == "__main__":
    unittest.main()
