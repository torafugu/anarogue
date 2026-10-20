import json
import os
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from run_jobs import QueueFull, RunJobs, validate_settings, validate_batch, batch_combinations
from run_store import RunStore, make_server

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("ANAROGUE_RUST_BINARY", ROOT / "simulation-core/target/debug/anarogue-sim"))


class RunJobTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.store = RunStore(Path(directory.name) / "runs.sqlite3")

    def runner(self, binary=BINARY, **options):
        runner = RunJobs(self.store, binary, **options)
        self.addCleanup(runner.close)
        return runner

    def wait_job(self, runner, job_id, timeout=10):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            job = runner.get(job_id)
            if job["status"] in ("completed", "failed", "cancelled"):
                return job
            time.sleep(.01)
        self.fail("Job did not finish")

    def api(self, runner):
        server = make_server(self.store, port=0, jobs=runner)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_port}"

    def post(self, base, settings, headers=None, path="/api/jobs"):
        request = Request(base + path, data=json.dumps(settings).encode(),
                          headers=headers or {"Content-Type": "application/json"})
        with urlopen(request, timeout=5) as response:
            return response.status, json.load(response)

    def test_validation_and_strategy_defaults(self):
        self.assertEqual(validate_settings({"strategy": "cautious"})["stairs_weight"], 4)
        self.assertEqual(validate_settings({})["enemy_weight"], 4)
        self.assertEqual(validate_settings({"seed": 4294967295})["seed"], 4294967295)
        for settings in [[], None, {"seed": True}, {"seed": -1}, {"seed": 4294967296},
                         {"seed": "42"}, {"strategy": "other"}, {"strategy": []},
                         {"max_turns": 0}, {"max_turns": 100001}, {"enemy_weight": 1001},
                         {"item_weight": .5}, {"enemy_weight": 0, "item_weight": 0, "stairs_weight": 0},
                         {"db": "other.sqlite3"}, {"binary": "other"}, {"revision": "user"}]:
            with self.subTest(settings=settings), self.assertRaises(ValueError):
                validate_settings(settings)

    def test_map_settings_validation_and_batch_propagation(self):
        default = validate_settings({})
        self.assertEqual([default[key] for key in ("enemy_amount", "treasure_amount", "map_depth")], [100, 100, 5])
        custom = {"enemy_amount": 0, "treasure_amount": 500, "map_depth": 8}
        settings, _ = validate_batch(custom)
        for combination in batch_combinations(settings):
            self.assertEqual({key: combination[key] for key in custom}, custom)
        for key, value in [("enemy_amount", -1), ("enemy_amount", 501), ("treasure_amount", 501),
                           ("map_depth", 0), ("map_depth", 101), ("map_depth", True), ("enemy_amount", 1.5)]:
            for validator in (validate_settings, validate_batch):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    validator({key: value})

    def test_map_settings_reach_simulator_and_saved_metadata(self):
        runner = self.runner()
        custom = {"enemy_amount": 0, "treasure_amount": 0, "map_depth": 2}
        job = self.wait_job(runner, runner.submit({**custom, "max_turns": 500})["id"])
        self.assertEqual(job["status"], "completed", job)
        row = self.store.get_run(job["run_id"])
        self.assertEqual(row["status"], "cleared")
        self.assertEqual(row["max_depth"], 2)
        self.assertEqual({key: row["execution_settings"][key] for key in custom}, custom)
        self.assertTrue(row["scenario_id"].endswith("-e0-t0-d2"))

    def test_batch_validation_and_exhaustive_combinations(self):
        settings, total = validate_batch({})
        combinations = list(batch_combinations(settings))
        self.assertEqual(total, 248)
        self.assertEqual(len(combinations), total)
        self.assertEqual(len({tuple(sorted(item.items())) for item in combinations}), total)
        self.assertEqual({item["strategy"] for item in combinations}, {"aggressive", "cautious"})
        self.assertTrue(all(item["enemy_weight"] + item["item_weight"] + item["stairs_weight"] for item in combinations))
        settings, total = validate_batch({"strategies": ["cautious", "cautious"], "enemy_weights": [2, 1, 2], "item_weights": [0], "stairs_weights": [0]})
        self.assertEqual(total, 2)
        self.assertEqual(settings["enemy_weights"], [1, 2])
        for invalid in [None, [], {"strategies": []}, {"strategies": [None]}, {"enemy_weights": []},
                        {"enemy_weights": [True]}, {"item_weights": [-1]}, {"stairs_weights": [1001]},
                        {"enemy_weights": [0], "item_weights": [0], "stairs_weights": [0]},
                        {"enemy_weights": list(range(20)), "item_weights": list(range(20)), "stairs_weights": list(range(20))},
                        {"seed": -1}, {"max_turns": 0}, {"binary": "other"}]:
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                validate_batch(invalid)

    def test_batch_cancel_finishes_only_current_run_and_preserves_progress(self):
        runner = self.runner(capacity=1)
        base = self.api(runner)
        entered, release = threading.Event(), threading.Event()
        def blocked(settings):
            entered.set()
            self.assertTrue(release.wait(5))
            return "saved-key", {}
        with patch.object(runner, "simulate", side_effect=blocked) as simulate:
            accepted = runner.submit_batch({})
            self.assertTrue(entered.wait(5))
            snapshot = runner.get(accepted["id"])
            snapshot["settings"]["enemy_weights"].clear()
            self.assertEqual(len(runner.get(accepted["id"])["settings"]["enemy_weights"]), 5)
            with self.assertRaises(QueueFull):
                runner.submit_batch({})
            status, stopping = self.post(base, {}, path=f"/api/jobs/{accepted['id']}/cancel")
            self.assertEqual(status, 200)
            self.assertTrue(stopping["cancel_requested"])
            release.set()
            cancelled = self.wait_job(runner, accepted["id"])
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertEqual(cancelled["completed"], 1)
            self.assertEqual(cancelled["run_id"], "saved-key")
            self.assertEqual(simulate.call_count, 1)

    def test_batch_failure_stops_remaining_combinations(self):
        runner = self.runner(binary=ROOT / "missing-simulator")
        base = self.api(runner)
        status, accepted = self.post(base, {}, path="/api/batches")
        self.assertEqual(status, 202)
        failed = self.wait_job(runner, accepted["id"])
        self.assertEqual((failed["status"], failed["failed"], failed["completed"]), ("failed", 1, 0))
        with self.assertRaises(HTTPError) as error:
            self.post(base, {}, path="/api/jobs/missing/cancel")
        self.assertEqual(error.exception.code, 404)
        with self.assertRaises(HTTPError) as error:
            self.post(base, {"enemy_weights": []}, path="/api/batches")
        self.assertEqual(error.exception.code, 400)

    @unittest.skipUnless(BINARY.is_file(), "Build the Rust simulator first")
    def test_real_batch_saves_all_248_combinations_and_statistics(self):
        runner = self.runner(revision="autorun-test")
        base = self.api(runner)
        status, accepted = self.post(base, {"seed": 42, "max_turns": 2}, path="/api/batches")
        self.assertEqual(status, 202)
        completed = self.wait_job(runner, accepted["id"], timeout=30)
        self.assertEqual(completed["status"], "completed", completed["error"])
        self.assertEqual((completed["completed"], completed["failed"]), (248, 0))
        runs = self.store.list_runs(limit=500)
        self.assertEqual(runs["total"], 248)
        expected, _total = validate_batch({"seed": 42, "max_turns": 2})
        policies = {(item["strategy_id"].removesuffix("_v1"), item["goal_policy"]["enemy_weight"],
                     item["goal_policy"]["item_weight"], item["goal_policy"]["stairs_weight"]) for item in runs["runs"]}
        self.assertEqual(policies, {(item["strategy"], item["enemy_weight"], item["item_weight"], item["stairs_weight"])
                                    for item in batch_combinations(expected)})
        self.assertTrue(all(item["scenario_seed"] == 42 and item["turns"] <= 2 for item in runs["runs"]))
        with urlopen(base + "/api/stats?scenario_seed=42") as response:
            self.assertEqual(len(json.load(response)["groups"]), 248)
        with urlopen(base + "/api/weight-analysis?scenario_seed=42") as response:
            analysis = json.load(response)
        self.assertEqual(len(analysis["cohorts"]), 1)
        self.assertEqual(analysis["cohorts"][0]["conditions"]["max_turns"], 2)
        self.assertEqual([group["n"] for group in analysis["cohorts"][0]["strategies"]], [124, 124])

    def test_queue_bound_and_missing_executable(self):
        runner = self.runner(binary=ROOT / "missing-simulator", capacity=1)
        entered, release = threading.Event(), threading.Event()
        def blocked(*args, **kwargs):
            entered.set()
            self.assertTrue(release.wait(5))
            raise FileNotFoundError("Simulator missing")
        with patch("run_jobs.subprocess.run", side_effect=blocked):
            accepted = runner.submit({})
            self.assertEqual(accepted["status"], "queued")
            self.assertTrue(entered.wait(5))
            self.assertEqual(runner.get(accepted["id"])["status"], "running")
            with self.assertRaises(QueueFull):
                runner.submit({})
            self.assertEqual(self.store.list_runs()["total"], 0)
            release.set()
            failed = self.wait_job(runner, accepted["id"])
            self.assertEqual(failed["status"], "failed")
            self.assertIn("missing", failed["error"])
        failed = self.wait_job(runner, runner.submit({})["id"])
        self.assertEqual(failed["status"], "failed")

    def test_timeout_nonzero_exit_and_missing_saved_key(self):
        runner = self.runner(timeout=.01)
        outcomes = [subprocess.TimeoutExpired("sim", .01),
                    subprocess.CompletedProcess([], 1, "", "invalid arguments"),
                    subprocess.CompletedProcess([], 0, "{}", "")]
        for outcome in outcomes:
            with patch("run_jobs.subprocess.run", **({"side_effect": outcome} if isinstance(outcome, Exception) else {"return_value": outcome})):
                failed = self.wait_job(runner, runner.submit({})["id"])
                self.assertEqual(failed["status"], "failed")
                self.assertTrue(failed["error"])
        self.assertEqual(self.store.list_runs()["total"], 0)

    def test_http_rejects_invalid_settings_origin_and_media_type(self):
        base = self.api(self.runner())
        for settings, headers, expected in [({"seed": -1}, None, 400),
                                            ({}, {"Content-Type": "text/plain"}, 415),
                                            ({}, {"Content-Type": "application/json", "Origin": "https://other.example"}, 403)]:
            with self.assertRaises(HTTPError) as error:
                self.post(base, settings, headers)
            self.assertEqual(error.exception.code, expected)
        with self.assertRaises(HTTPError) as error:
            urlopen(base + "/api/jobs/no-such-job")
        self.assertEqual(error.exception.code, 404)
        # A readable catalogue remains available without a Run worker.
        other = self.api(None)
        with self.assertRaises(HTTPError) as error:
            self.post(other, {})
        self.assertEqual(error.exception.code, 503)

    @unittest.skipUnless(BINARY.is_file(), "Build the Rust simulator first")
    def test_real_http_execution_stores_and_replays_requested_run(self):
        old_key = self.store.import_file(ROOT / "examples/reference-v8/aggressive-seed-424242.jsonl")[0]
        runner = self.runner(revision="launcher-test")
        base = self.api(runner)
        settings = {"seed": 42, "strategy": "cautious", "max_turns": 20,
                    "enemy_weight": 3, "item_weight": 7, "stairs_weight": 2}
        status, accepted = self.post(base, settings)
        self.assertEqual(status, 202)
        completed = self.wait_job(runner, accepted["id"])
        self.assertEqual(completed["status"], "completed", completed["error"])
        with urlopen(base + "/api/jobs/" + accepted["id"]) as response:
            self.assertEqual(json.load(response)["run_id"], completed["run_id"])
        with urlopen(base + f"/api/runs/{completed['run_id']}/events") as response:
            events = json.load(response)["events"]
        self.assertEqual(events[0]["scenario_seed"], 42)
        self.assertEqual(events[0]["strategy_id"], "cautious_v1")
        self.assertEqual(events[0]["details"]["code_revision"], "launcher-test")
        self.assertEqual(events[0]["details"]["goal_policy"],
                         {"enemy_weight": 3, "item_weight": 7, "stairs_weight": 2, "temperature": 8})
        self.assertLessEqual(self.store.get_run(completed["run_id"])["turns"], 20)
        self.assertEqual(self.store.list_runs()["total"], 2)
        self.assertEqual(self.store.get_run(old_key)["score"], 20)
        second = self.wait_job(runner, self.post(base, settings)[1]["id"])
        self.assertEqual(second["status"], "completed", second["error"])
        self.assertNotEqual(second["run_id"], completed["run_id"])


if __name__ == "__main__":
    unittest.main()
