import copy
import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from run_store import LogWatcher, RunStore, make_server

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "examples/reference-v8/aggressive-seed-424242.jsonl"


def text(events):
    return "\n".join(json.dumps(event) for event in events) + "\n"


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = RunStore(Path(self.temp.name) / "runs.sqlite3")
        self.events = [json.loads(line) for line in REFERENCE.read_text().splitlines()]

    def test_persistence_idempotency_and_export(self):
        key = self.store.import_text(text(self.events))[0]
        self.assertEqual(self.store.import_file(REFERENCE), [key])
        reopened = RunStore(self.store.path)
        self.assertEqual(reopened.list_runs()["total"], 1)
        self.assertEqual(reopened.events(key), self.events)
        summary = reopened.list_runs()["runs"][0]
        self.assertEqual((summary["score"], summary["max_depth"], summary["turns"], summary["status"]), (20, 5, 108, "cleared"))
        self.assertEqual(summary["goal_policy"]["enemy_weight"], 4)
        self.assertEqual(summary["event_count"], len(self.events))

    def test_append_snapshot_and_completed_immutability(self):
        key = self.store.import_text(text(self.events[:20]))[0]
        self.assertEqual(self.store.list_runs()["runs"][0]["status"], "unfinished")
        self.store.import_text(text(self.events[:40]))
        self.store.import_text(text(self.events[:10]))
        self.assertEqual(len(self.store.events(key)), 40)
        self.store.import_text(text(self.events))
        extra = copy.deepcopy(self.events[-1])
        extra["sequence"] += 1
        with self.assertRaisesRegex(ValueError, "completed"):
            self.store.import_text(text([*self.events, extra]))
        self.assertEqual(self.store.events(key), self.events)

    def test_conflict_rolls_back_entire_multi_run_import(self):
        key = self.store.import_text(text(self.events[:20]))[0]
        other = copy.deepcopy(self.events[:20])
        for event in other:
            event["run_id"] = "new-run"
        bad = copy.deepcopy(self.events[:30])
        bad[5]["hp"] = 999
        with self.assertRaisesRegex(ValueError, "conflicting event"):
            self.store.import_text(text([*other, *bad]))
        self.assertEqual(self.store.list_runs()["total"], 1)
        self.assertEqual(len(self.store.events(key)), 20)

    def test_versions_with_same_external_run_id_are_separate(self):
        self.store.import_file(REFERENCE)
        self.store.import_file(ROOT / "examples/reference-v6/aggressive-seed-424242.jsonl")
        self.assertEqual(self.store.list_runs()["total"], 2)
        self.assertEqual(self.store.list_runs({"simulation_version": 8})["total"], 1)
        self.assertEqual(len(self.store.stats()["groups"]), 2)

    def test_partial_line_and_watched_append(self):
        path = Path(self.temp.name) / "live.jsonl"
        watcher = LogWatcher(self.store, [Path(self.temp.name)])
        path.write_text(text(self.events[:20]) + '{"run_id":')
        watcher.scan()
        key = self.store.list_runs()["runs"][0]["id"]
        self.assertEqual(len(self.store.events(key)), 20)
        path.write_text(text(self.events[:30]))
        watcher.scan()
        self.assertEqual(len(self.store.events(key)), 30)
        watcher.scan()
        self.assertEqual(self.store.list_runs()["total"], 1)
        path.write_text(text(self.events[:30]) + '{bad}\n')
        watcher.scan()
        self.assertEqual(len(self.store.events(key)), 30)

    def test_bad_sequence_and_malformed_logs_are_rejected(self):
        for source in ['', '   \n', '[]\n', '{bad}\n', text(self.events[1:4]), text([self.events[0], self.events[2]]), text([self.events[0], self.events[0]])]:
            with self.assertRaises(ValueError):
                self.store.import_text(source)
        self.assertEqual(self.store.list_runs()["total"], 0)

    def test_stats_split_policy_revision_and_exclude_unfinished(self):
        self.store.import_text(text(self.events), revision="abc")
        partial = copy.deepcopy(self.events[:20])
        for event in partial:
            event["run_id"] = "unfinished-run"
        self.store.import_text(text(partial), revision="abc")
        groups = self.store.stats()["groups"]
        self.assertEqual(len(groups), 1)
        group = groups[0]
        self.assertEqual((group["runs"], group["finished"], group["cleared"], group["mean_score"], group["clear_rate"]), (2, 1, 1, 20, 1))
        variant = copy.deepcopy(self.events)
        for event in variant:
            event["run_id"] = "different-policy"
        variant[0]["details"]["goal_policy"]["enemy_weight"] = 1
        self.store.import_text(text(variant), revision="abc")
        self.assertEqual(len(self.store.stats()["groups"]), 2)
        revision_variant = copy.deepcopy(self.events)
        for event in revision_variant:
            event["run_id"] = "different-revision"
        self.store.import_text(text(revision_variant), revision="def")
        self.assertEqual(len(self.store.stats()["groups"]), 3)
        self.assertEqual(self.store.list_runs({"status": "unfinished"})["total"], 1)

    def test_concurrent_imports_do_not_duplicate_events(self):
        errors = []
        def import_run():
            try:
                self.store.import_text(text(self.events))
            except Exception as exc:
                errors.append(exc)
        threads = [threading.Thread(target=import_run) for _ in range(3)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(errors, [])
        self.assertEqual(self.store.list_runs()["total"], 1)

    def test_http_search_events_stats_export_and_import(self):
        server = make_server(self.store, port=0)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        base = f"http://127.0.0.1:{server.server_port}"
        def get(path):
            with urlopen(base + path, timeout=5) as response:
                return json.load(response)
        request = Request(base + "/api/import", data=text(self.events).encode(), headers={"Content-Type": "application/x-ndjson"})
        with urlopen(request, timeout=5) as response:
            key = json.load(response)["run_ids"][0]
        self.assertEqual(get("/api/runs?strategy_id=aggressive_v1&scenario_seed=424242&limit=1")["total"], 1)
        self.assertEqual(get("/api/runs?strategy_id=cautious_v1")["runs"], [])
        self.assertEqual(get("/api/runs?offset=1")["runs"], [])
        self.assertEqual(get(f"/api/runs/{key}")["score"], 20)
        self.assertEqual(get(f"/api/runs/{key}/events")["events"], self.events)
        with urlopen(base + f"/api/runs/{key}/log") as response:
            self.assertEqual([json.loads(line) for line in response.read().decode().splitlines()], self.events)
        self.assertEqual(get("/api/stats")["groups"][0]["finished"], 1)
        for path, expected in [("/api/runs/no-such-run/events", 404), ("/api/runs?limit=0", 400), ("/api/runs?offset=-1", 400), ("/missing", 404)]:
            with self.assertRaises(HTTPError) as error:
                get(path)
            self.assertEqual(error.exception.code, expected)
        with self.assertRaises(HTTPError) as error:
            urlopen(Request(base + "/api/import", data=b"bad", headers={"Content-Type": "application/x-ndjson"}))
        self.assertEqual(error.exception.code, 400)


if __name__ == "__main__":
    unittest.main()
