"""Cross-runtime contract checks against the built Rust CLI (no Godot needed)."""
import hashlib
import json
import os
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import urlopen

from run_store import RunStore, canonical, make_server, summarize

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("ANAROGUE_RUST_BINARY", ROOT / "simulation-core/target/debug/anarogue-sim"))


@unittest.skipUnless(BINARY.is_file(), "Build the Rust CLI or set ANAROGUE_RUST_BINARY")
class RustStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = Path(self.temp.name) / "nested/runs.sqlite3"
        self.log = Path(self.temp.name) / "日本語.jsonl"

    def run_cli(self, *arguments):
        result = subprocess.run([str(BINARY), *map(str, arguments)], capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_rust_first_python_reimport_matches_identity_payloads_and_summary(self):
        revision = '検証版 "\\ 🦀\nnext'
        summary = self.run_cli("--db", self.db, "--output", self.log, "--revision", revision)
        events = [json.loads(line) for line in self.log.read_text().splitlines()]
        store = RunStore(self.db)
        run = store.list_runs()["runs"][0]
        key = hashlib.sha256(canonical(events[0]).encode()).hexdigest()
        self.assertEqual(run["id"], key)
        self.assertEqual(run["code_revision"], revision)
        self.assertEqual(store.events(key), events)
        expected = summarize(events)
        for field, value in expected.items():
            self.assertEqual(run[field], value, field)
        self.assertEqual(run["score"], summary["final_score"])
        # Compare exact serialized strings as well as parsed JSON: importing the
        # same export must not report conflicting events or create a second Run.
        import sqlite3
        with sqlite3.connect(self.db) as connection:
            payloads = [row[0] for row in connection.execute("SELECT payload FROM events ORDER BY sequence")]
        self.assertEqual(payloads, [canonical(event) for event in events])
        self.assertEqual(store.import_file(self.log), [key])
        self.assertEqual(store.list_runs()["total"], 1)
        self.assertEqual(store.stats()["groups"][0]["finished"], 1)
        self.assertEqual(store.stats()["groups"][0]["clear_rate"], 1)

    def test_python_initialized_database_and_running_api_see_direct_writes(self):
        store = RunStore(self.db)
        store.import_file(ROOT / "examples/reference-v8/cautious-seed-1.jsonl")
        server = make_server(store, port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.run_cli("--db", self.db, "--strategy", "aggressive", "--seed", 424242)
        with urlopen(f"http://127.0.0.1:{server.server_port}/api/runs") as response:
            data = json.load(response)
        self.assertEqual(data["total"], 2)
        run = data["runs"][0]
        with urlopen(f"http://127.0.0.1:{server.server_port}/api/runs/{run['id']}/events") as response:
            events = json.load(response)["events"]
        self.assertEqual(events[0]["event"], "run_start")
        self.assertEqual(run["score"], 20)
        self.assertFalse(self.log.exists())

    def test_turn_limited_runs_remain_unfinished_and_repeated_trials_accumulate(self):
        first = self.run_cli("--db", self.db, "--max-turns", 1)
        second = self.run_cli("--db", self.db, "--max-turns", 1)
        self.assertEqual(first, second)
        store = RunStore(self.db)
        runs = store.list_runs()["runs"]
        self.assertEqual(len(runs), 2)
        self.assertNotEqual(runs[0]["run_id"], runs[1]["run_id"])
        self.assertTrue(all(run["status"] == "unfinished" for run in runs))
        group = store.stats()["groups"][0]
        self.assertEqual(group["finished"], 0)
        self.assertIsNone(group["mean_score"])
        self.assertIsNone(group["clear_rate"])


if __name__ == "__main__":
    unittest.main()
