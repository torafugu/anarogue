"""Named configurations survive restarts and launch immutable, validated snapshots."""
import json
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from urllib.request import Request, urlopen
from urllib.error import HTTPError

from run_jobs import RunJobs
from run_presets import RunPresets
from run_store import RunStore, make_server

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("ANAROGUE_RUST_BINARY", ROOT / "simulation-core/target/debug/anarogue-sim"))


@unittest.skipUnless(BINARY.is_file(), "Build the Rust simulator first")
class RunPresetTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "runs.sqlite3"
        self.store = RunStore(self.path)
        self.jobs = RunJobs(self.store, BINARY)
        self.addCleanup(self.jobs.close)
        self.server = make_server(self.store, port=0, jobs=self.jobs)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.presets = RunPresets(self.store)

    def request(self, path="/api/presets", value=None, method="POST", expected=200, headers=None):
        request = Request(f"http://127.0.0.1:{self.server.server_port}{path}",
                          data=json.dumps(value).encode() if value is not None else None,
                          headers={"Content-Type": "application/json", **(headers or {})}, method=method)
        try:
            response = urlopen(request)
        except HTTPError as exc:
            response = exc
        with response:
            result = json.load(response)
            self.assertEqual(response.code, expected, result)
            return result

    def create(self, **settings):
        return self.request(value={"name": "反撃型", "settings": {"max_turns": 2, **settings}}, expected=201)

    def finish(self, job):
        for _ in range(500):
            current = self.jobs.get(job["id"])
            if current["status"] in ("completed", "failed", "cancelled"):
                self.assertEqual(current["status"], "completed", current)
                return current
            time.sleep(.01)
        self.fail("Job timed out")

    def test_save_validate_restart_edit_duplicate_and_conflicts(self):
        for dsl in ['rule "x" { do waait }', 'rule "x" { when self.hp == bow do wait }']:
            report = self.request(value={"name": "Bad", "settings": {"dsl": dsl}}, expected=400)
            self.assertIn("line", report["error"])
        self.assertEqual(self.presets.list(), [])
        preset = self.create(strategy="cautious", item_weight=7, dsl='rule "Hold" { do wait }')
        self.assertEqual(self.jobs.jobs, {})
        self.assertEqual(RunPresets(RunStore(self.path)).get(preset["id"]), preset)
        changed = self.request(f'/api/presets/{preset["id"]}', {**{k: preset[k] for k in ("name", "kind", "settings", "version")}, "name": "改訂版"}, "PUT")
        self.assertEqual(changed["version"], 2)
        self.request(f'/api/presets/{preset["id"]}', {"name": "Stale", "settings": {}, "version": 1}, "PUT", 409)
        self.request(value={"name": "改訂版", "settings": {}}, expected=409)
        self.request(f'/api/presets/{preset["id"]}/run', {"version": 1}, expected=409)
        self.request(f'/api/presets/{preset["id"]}/run', {"version": 2, "settings": {}}, expected=400)
        self.assertEqual(self.store.database_counts()["runs"], 0)
        self.store.clear_runs(self.store.database_counts())
        self.assertEqual(len(self.presets.list()), 1, "Clearing Runs preserves authored presets")

    def test_queued_snapshot_survives_edit_and_deletion(self):
        preset = self.create(seed=42, strategy="cautious", item_weight=7, dsl='rule "Hold" { do wait }')
        entered, release = threading.Event(), threading.Event()
        simulate = self.jobs.simulate
        def delayed(settings):
            entered.set()
            release.wait(5)
            return simulate(settings)
        self.jobs.simulate = delayed
        self.addCleanup(release.set)
        accepted = self.request(f'/api/presets/{preset["id"]}/run', {"version": 1}, expected=202)
        self.assertTrue(entered.wait(2))
        self.request(f'/api/presets/{preset["id"]}', {"name": "Updated", "settings": {"seed": 9, "max_turns": 2}, "version": 1}, "PUT")
        self.request(f'/api/presets/{preset["id"]}', {"version": 1}, "DELETE", 409)
        self.request(f'/api/presets/{preset["id"]}', {"version": 2}, "DELETE")
        release.set()
        job = self.finish(accepted)
        run = self.store.get_run(job["run_id"])
        self.assertEqual(run["preset"], preset)
        self.assertEqual(run["scenario_seed"], 42)
        self.assertEqual(run["goal_policy"]["item_weight"], 7)
        self.assertIn("Hold", run["execution_settings"]["dsl"])
        self.assertEqual(self.presets.list(), [])

    def test_batch_validation_and_saved_batch_launch(self):
        settings = {"max_turns": 1, "enemy_weights": [0, 1], "item_weights": [0, 1], "stairs_weights": [0, 1], "dsl": 'rule "Hold" { do wait }'}
        report = self.request('/api/presets/validate', {"kind": "batch", "settings": settings})
        self.assertEqual(report["total"], 14)
        preset = self.request(value={"name": "Sweep", "kind": "batch", "settings": settings}, expected=201)
        self.assertEqual(self.jobs.jobs, {})
        job = self.finish(self.request(f'/api/presets/{preset["id"]}/run', {"version": 1}, expected=202))
        self.assertEqual(job["completed"], 14)
        self.assertTrue(all(run["preset"] == preset for run in self.store.list_runs()["runs"]))
        self.request(value={"name": "Bad sweep", "kind": "batch", "settings": {**settings, "dsl": "policy { enemy_weight = 0 treasure_weight = 0 stairs_weight = 0 }"}}, expected=400)

    def test_mutations_reject_cross_origin_and_allow_same_origin_proxy(self):
        self.request(value={"name": "Wrong", "settings": {}}, expected=403, headers={"Origin": "https://other.example"})
        self.request(value={"name": "Proxy", "settings": {}}, expected=201, headers={"Origin": "http://127.0.0.1:5173", "Sec-Fetch-Site": "same-origin"})
        self.request(value={"name": " ", "settings": {}}, expected=400)
        self.request(value={"name": "Bad", "settings": {"strategy": "unknown"}}, expected=400)


if __name__ == "__main__":
    unittest.main()
