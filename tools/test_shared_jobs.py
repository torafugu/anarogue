import json
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.request import Request, urlopen

from run_jobs import RunJobs
from run_store import RunStore, make_server

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("ANAROGUE_RUST_BINARY", ROOT / "simulation-core/target/debug/anarogue-sim"))


class SharedJobTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.store = RunStore(Path(directory.name) / "runs.sqlite3")

    def runner(self):
        runner = RunJobs(self.store, BINARY)
        self.addCleanup(runner.close)
        return runner

    def wait(self, runner, key):
        for _ in range(1000):
            job = runner.get(key)
            if job["status"] in ("completed", "failed", "cancelled"):
                return job
            time.sleep(.01)
        self.fail("Job timed out")

    def test_recovery_preserves_finished_and_marks_incomplete_without_reexecuting(self):
        runner = self.runner()
        with patch.object(runner.executor, "submit"):
            queued = runner.submit({})
            running = runner.submit_batch({"enemy_weights":[1], "item_weights":[1], "stairs_weights":[1]})
            completed = runner.submit({})
        runner.jobs[running["id"]].update(status="running", completed=1, run_id="saved-run")
        runner.history.save(runner.jobs[running["id"]])
        runner.jobs[completed["id"]].update(status="completed", run_id="finished-run")
        runner.history.save(runner.jobs[completed["id"]])
        # Simulate process loss rather than graceful queue cancellation.
        runner.closed = True
        runner.executor.shutdown()
        restored = self.runner()
        for key in (queued["id"], running["id"]):
            snapshot = restored.get(key)
            self.assertEqual(snapshot["status"], "failed")
            self.assertTrue(snapshot["interrupted"])
        self.assertEqual(restored.get(running["id"])["completed"], 1)
        self.assertEqual(restored.get(running["id"])["run_id"], "saved-run")
        self.assertEqual(restored.get(completed["id"])["status"], "completed")
        self.assertEqual(restored.jobs, {}, "Historical jobs are never re-enqueued")
        self.assertEqual(restored.list()["total"], 3)

    def test_history_pagination_survives_memory_eviction_and_omits_dsl_from_list(self):
        runner = self.runner()
        keys = []
        with patch.object(runner.executor, "submit"):
            for _ in range(67):
                job = runner.submit({})
                keys.append(job["id"])
                runner.jobs[job["id"]].update(status="completed")
                runner.history.save(runner.jobs[job["id"]])
        self.assertEqual(len(runner.jobs), 64)
        self.assertEqual(runner.get(keys[0])["id"], keys[0])
        self.assertEqual(runner.list(20, 60)["total"], 67)
        self.assertEqual(len(runner.list(20, 60)["jobs"]), 7)
        runner.jobs[keys[-1]]["settings"]["dsl"] = "private source"
        runner.history.save(runner.jobs[keys[-1]])
        self.assertNotIn("dsl", runner.list()["jobs"][0]["settings"])
        self.assertEqual(runner.get(keys[-1])["settings"]["dsl"], "private source")

    @unittest.skipUnless(BINARY.is_file(), "Build Rust first")
    def test_independent_clients_share_job_cancel_and_saved_results(self):
        runner = self.runner()
        server = make_server(self.store, port=0, jobs=runner)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close); self.addCleanup(server.shutdown)
        base = f"http://127.0.0.1:{server.server_port}"
        entered, release = threading.Event(), threading.Event()
        self.addCleanup(release.set)
        simulate = runner.simulate
        def delayed(settings):
            entered.set(); release.wait(5)
            return simulate(settings)
        with patch.object(runner, "simulate", side_effect=delayed):
            request = Request(base + "/api/batches", data=json.dumps({"max_turns":2}).encode(), headers={"Content-Type":"application/json"})
            with urlopen(request) as response:
                accepted = json.load(response)
            self.assertTrue(entered.wait(2))
            with urlopen(base + "/api/jobs?limit=20&offset=0") as response:
                self.assertEqual(json.load(response)["jobs"][0]["id"], accepted["id"])
            with urlopen(Request(base + f'/api/jobs/{accepted["id"]}/cancel', data=b'{}', headers={"Content-Type":"application/json"})) as response:
                self.assertTrue(json.load(response)["cancel_requested"])
            release.set()
            job = self.wait(runner, accepted["id"])
        self.assertEqual(job["status"], "cancelled")
        self.assertEqual(job["completed"], 1)
        with urlopen(base + f'/api/runs?job_id={job["id"]}') as response:
            results = json.load(response)
        self.assertEqual(results["total"], 1)
        self.assertEqual(results["runs"][0]["id"], job["run_id"])
        runner.close()
        restored = self.runner()
        self.assertEqual(restored.get(job["id"])["status"], "cancelled")
        self.store.clear_runs(self.store.database_counts())
        self.assertEqual(restored.list()["total"], 0)


if __name__ == "__main__":
    unittest.main()
