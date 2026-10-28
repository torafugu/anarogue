"""Bounded, asynchronous execution of the configured Rust simulator."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from copy import deepcopy
from itertools import product
import json
import re
import subprocess
import threading
import uuid
from job_history import JobHistory, timestamp


class QueueFull(Exception):
    pass

MAX_BATCH_RUNS = 2000
MAP_FIELDS = ("enemy_amount", "treasure_amount", "map_depth")
TERMINAL_JOBS = ("completed", "failed", "cancelled")


def validate_batch(value):
    if not isinstance(value, dict):
        raise ValueError("AutoRun settings must be a JSON object")
    fields = {"seed", "max_turns", "strategies", "enemy_weights", "item_weights", "stairs_weights", "dsl", *MAP_FIELDS}
    if set(value) - fields:
        raise ValueError("Unknown AutoRun setting")
    single = validate_settings({key: value[key] for key in ("seed", "max_turns", *MAP_FIELDS) if key in value})
    settings = {key: single[key] for key in ("seed", "max_turns", *MAP_FIELDS)}
    if "dsl" in value:
        settings["dsl"] = validate_settings({"dsl": value["dsl"]})["dsl"]
    strategies = value.get("strategies", ["aggressive", "cautious"])
    if not isinstance(strategies, list) or not strategies or any(
            item not in ("aggressive", "cautious") for item in strategies):
        raise ValueError("strategies must contain aggressive and/or cautious")
    settings["strategies"] = list(dict.fromkeys(strategies))
    for field in ("enemy_weights", "item_weights", "stairs_weights"):
        values = value.get(field, list(range(5)))
        if not isinstance(values, list) or not 1 <= len(values) <= 1001 or any(
                type(number) is not int or not 0 <= number <= 1000 for number in values):
            raise ValueError(f"{field} must contain integers in 0..1000")
        settings[field] = sorted(set(values))
    counts = [len(settings[field]) for field in ("enemy_weights", "item_weights", "stairs_weights")]
    zero = all(0 in settings[field] for field in ("enemy_weights", "item_weights", "stairs_weights"))
    total = len(settings["strategies"]) * (counts[0] * counts[1] * counts[2] - int(zero))
    if not 1 <= total <= MAX_BATCH_RUNS:
        raise ValueError(f"AutoRun must contain 1..{MAX_BATCH_RUNS} Runs (all-zero weights are excluded)")
    return settings, total


def batch_combinations(settings):
    for strategy, enemy, item, stairs in product(settings["strategies"], settings["enemy_weights"],
                                                settings["item_weights"], settings["stairs_weights"]):
        if enemy + item + stairs:
            yield {"strategy": strategy, "seed": settings["seed"], "max_turns": settings["max_turns"],
                   "enemy_weight": enemy, "item_weight": item, "stairs_weight": stairs,
                   **{key: settings[key] for key in MAP_FIELDS},
                   **({"dsl": settings["dsl"]} if "dsl" in settings else {})}


def validate_settings(value):
    if not isinstance(value, dict):
        raise ValueError("Run settings must be a JSON object")
    fields = {"seed", "strategy", "enemy_weight", "item_weight", "stairs_weight", "max_turns", "dsl", *MAP_FIELDS}
    if set(value) - fields:
        raise ValueError("Unknown Run setting")
    strategy = value.get("strategy", "aggressive")
    if strategy not in ("aggressive", "cautious"):
        raise ValueError("strategy must be aggressive or cautious")
    settings = {"strategy": strategy}
    if "dsl" in value:
        if not isinstance(value["dsl"], str) or len(value["dsl"].encode("utf-8")) > 16384:
            raise ValueError("DSL source must be a string of at most 16 KB")
        settings["dsl"] = value["dsl"]
    defaults = {"seed": 424242, "max_turns": 5000, "enemy_weight": 1 if strategy == "cautious" else 4,
                "item_weight": 2, "stairs_weight": 4 if strategy == "cautious" else 1,
                "enemy_amount": 100, "treasure_amount": 100, "map_depth": 5}
    for field, default in defaults.items():
        number = value.get(field, default)
        maximum = 4294967295 if field == "seed" else 100000 if field == "max_turns" else 1000
        if field in MAP_FIELDS:
            maximum = 100 if field == "map_depth" else 500
        minimum = 1 if field in ("max_turns", "map_depth") else 0
        if type(number) is not int or not minimum <= number <= maximum:
            raise ValueError(f"{field} must be an integer in {minimum}..{maximum}")
        settings[field] = number
    if not settings.get("dsl", "").strip() and not sum(settings[field] for field in ("enemy_weight", "item_weight", "stairs_weight")):
        raise ValueError("At least one goal weight must be positive")
    return settings


class RunJobs:
    """One worker, at most 16 outstanding jobs, and 64 cached job records.

    The executable and database are server configuration, never request fields.
    Job snapshots persist in SQLite; interrupted execution is not auto-restarted.
    """
    def __init__(self, store, binary, revision="", timeout=120, capacity=16):
        self.store = store
        self.binary = str(Path(binary).resolve())
        self.database = str(Path(store.path).resolve())
        self.revision = revision
        self.timeout = timeout
        if not 1 <= capacity <= 16:
            raise ValueError("Run queue capacity must be 1..16")
        self.capacity = capacity
        self.jobs = {}
        self.history = JobHistory(store)
        self.history.recover()
        self.lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="run-simulator")
        self.closed = False

    def validate_launch(self, kind, value):
        settings, total = validate_batch(value) if kind == "batch" else (validate_settings(value), 1)
        if settings.get("dsl", "").strip():
            first = next(batch_combinations(settings)) if kind == "batch" else settings
            overrides = self.validate_dsl(first)["policy_overrides"]
            for combination in batch_combinations(settings) if kind == "batch" else [settings]:
                if not sum(overrides.get(dsl_key, combination[key]) for dsl_key, key in
                           (("enemy_weight", "enemy_weight"), ("treasure_weight", "item_weight"), ("stairs_weight", "stairs_weight"))):
                    raise ValueError("DSL makes all goal weights zero in an AutoRun combination")
        return settings, total

    def submit(self, value, preset=None):
        settings, _total = self.validate_launch("run", value)
        return self.enqueue({"kind": "run", "settings": settings, "run_id": None, "error": None,
                             **({"preset": preset} if preset is not None else {})})

    def submit_batch(self, value, preset=None):
        settings, total = self.validate_launch("batch", value)
        return self.enqueue({"kind": "batch", "settings": settings, "total": total,
                             "completed": 0, "failed": 0, "current_settings": None,
                             "run_id": None, "error": None, "cancel_requested": False,
                             **({"preset": preset} if preset is not None else {})})

    def enqueue(self, fields):
        with self.lock:
            if self.closed:
                raise QueueFull("Run service is stopping")
            if sum(job["status"] in ("queued", "running") for job in self.jobs.values()) >= self.capacity:
                raise QueueFull("Run queue is full; try again after a Run completes")
            while len(self.jobs) >= 64:
                oldest = next(key for key, job in self.jobs.items() if job["status"] in TERMINAL_JOBS)
                del self.jobs[oldest]
            job_id = uuid.uuid4().hex
            job = {"id": job_id, "status": "queued", "created_at": timestamp(), **fields}
            self.history.save(job)
            self.jobs[job_id] = job
            # Return an acceptance snapshot even if the worker finishes immediately.
            accepted = deepcopy(job)
            self.executor.submit(self.execute, job_id)
            return accepted

    def get(self, job_id):
        with self.lock:
            return deepcopy(self.jobs[job_id]) if job_id in self.jobs else self.history.get(job_id)

    def list(self, limit=100, offset=0):
        with self.lock:
            return self.history.list(limit, offset)

    def cancel(self, job_id):
        with self.lock:
            job = self.jobs[job_id] if job_id in self.jobs else self.history.get(job_id)
            if job["kind"] != "batch":
                raise ValueError("Only AutoRun jobs can be cancelled")
            if job["status"] not in TERMINAL_JOBS:
                job["cancel_requested"] = True
                if job["status"] == "queued":
                    job["status"] = "cancelled"
                self.history.save(job)
            return deepcopy(job)

    def execute(self, job_id):
        with self.lock:
            job = self.jobs[job_id]
            if self.closed or job["status"] in TERMINAL_JOBS:
                return
            job["status"] = "running"
            self.history.save(job)
            settings = dict(job["settings"])
        if job["kind"] == "batch":
            self.execute_batch(job, settings)
            return
        try:
            run_id, summary = self.simulate(settings)
            if "preset" in job:
                self.store.record_run_preset(run_id, job["preset"])
            self.store.record_run_job(run_id, job_id)
            with self.lock:
                job.update(status="completed", run_id=run_id, summary=summary)
                self.history.save(job)
        except Exception as exc:
            self.fail(job, str(exc))

    def execute_batch(self, job, settings):
        for combination in batch_combinations(settings):
            with self.lock:
                if self.closed or job["cancel_requested"]:
                    job.update(status="cancelled", current_settings=None)
                    self.history.save(job)
                    return
                job["current_settings"] = combination
                self.history.save(job)
            try:
                run_id, _summary = self.simulate(combination)
                if "preset" in job:
                    self.store.record_run_preset(run_id, job["preset"])
                self.store.record_run_job(run_id, job["id"])
                with self.lock:
                    job["completed"] += 1
                    job["run_id"] = run_id
                    self.history.save(job)
            except Exception as exc:
                with self.lock:
                    job["failed"] += 1
                    job["error"] = str(exc)
                # Infrastructure failure must not waste the rest of a sweep.
                self.fail(job, str(exc))
                return
        with self.lock:
            job.update(status="cancelled" if job["cancel_requested"] else "completed", current_settings=None)
            self.history.save(job)

    def simulate(self, settings):
        command = [self.binary, "--db", self.database]
        for field, value in settings.items():
            if field == "dsl":
                continue
            command.extend(["--" + field.replace("_", "-"), str(value)])
        if settings.get("dsl", "").strip():
            command.extend(["--dsl-stdin", "yes"])
        if self.revision:
            command.extend(["--revision", self.revision])
        try:
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                    errors="replace", timeout=self.timeout, check=False,
                                    **({"input": settings["dsl"]} if settings.get("dsl", "").strip() else {}))
            if result.returncode:
                raise ValueError((result.stderr.strip() or f"Simulator exited with {result.returncode}")[-2000:])
            # Rust reports the committed catalogue key only after save_run succeeds.
            saved = re.search(r"^saved Run ([0-9a-f]{64}) to .+$", result.stderr, re.MULTILINE)
            if not saved:
                raise ValueError("Simulator did not report a saved Run; rebuild the Rust simulator")
            run_id = saved.group(1)
            self.store.get_run(run_id)  # Do not report completion before the row is readable.
            summary = json.loads(result.stdout)
            self.store.record_execution_settings(run_id, settings)
            return run_id, summary
        except subprocess.TimeoutExpired:
            raise ValueError(f"Run exceeded the {self.timeout:g}-second execution limit") from None
        except (OSError, ValueError, KeyError) as exc:
            raise ValueError(str(exc)) from exc
        except Exception:
            raise ValueError("Could not read the saved Run") from None

    def validate_dsl(self, value):
        settings = validate_settings(value)
        command = [self.binary, "--validate-dsl", "yes", "--strategy", settings["strategy"]]
        for field in ("enemy_weight", "item_weight", "stairs_weight"):
            command.extend(["--" + field.replace("_", "-"), str(settings[field])])
        try:
            result = subprocess.run(command, input=settings.get("dsl", ""), capture_output=True,
                                    text=True, encoding="utf-8", errors="replace", timeout=5, check=False)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError(f"DSL validation unavailable: {exc}. Rebuild the Rust simulator.") from None
        if result.returncode:
            raise ValueError(result.stderr.split("\nusage:")[0].strip()[-2000:])
        try:
            report = json.loads(result.stdout)
            if report.get("valid") is not True or not isinstance(report.get("policy_overrides"), dict):
                raise ValueError("invalid validator response")
            return report
        except (ValueError, AttributeError):
            raise ValueError("Invalid DSL validation response; rebuild the Rust simulator") from None

    def fail(self, job, message):
        with self.lock:
            job.update(status="failed", error=message)
            self.history.save(job)

    def close(self):
        with self.lock:
            if self.closed:
                return
            self.closed = True
            for job in self.jobs.values():
                if job["status"] == "queued":
                    job.update(status="failed", error="Run service stopped before execution")
                    self.history.save(job)
        self.executor.shutdown(wait=True, cancel_futures=True)
