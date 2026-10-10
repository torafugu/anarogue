"""Bounded, asynchronous execution of the configured Rust simulator."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import re
import subprocess
import threading
import uuid


class QueueFull(Exception):
    pass


def validate_settings(value):
    if not isinstance(value, dict):
        raise ValueError("Run settings must be a JSON object")
    fields = {"seed", "strategy", "enemy_weight", "item_weight", "stairs_weight", "max_turns"}
    if set(value) - fields:
        raise ValueError("Unknown Run setting")
    strategy = value.get("strategy", "aggressive")
    if strategy not in ("aggressive", "cautious"):
        raise ValueError("strategy must be aggressive or cautious")
    settings = {"strategy": strategy}
    defaults = {"seed": 424242, "max_turns": 5000, "enemy_weight": 1 if strategy == "cautious" else 4,
                "item_weight": 2, "stairs_weight": 4 if strategy == "cautious" else 1}
    for field, default in defaults.items():
        number = value.get(field, default)
        maximum = 4294967295 if field == "seed" else 100000 if field == "max_turns" else 1000
        minimum = 1 if field == "max_turns" else 0
        if type(number) is not int or not minimum <= number <= maximum:
            raise ValueError(f"{field} must be an integer in {minimum}..{maximum}")
        settings[field] = number
    if not sum(settings[field] for field in ("enemy_weight", "item_weight", "stairs_weight")):
        raise ValueError("At least one goal weight must be positive")
    return settings


class RunJobs:
    """One worker, at most 16 outstanding jobs, and 64 retained job records.

    The executable and database are server configuration, never request fields.
    Job records are ephemeral; completed Runs remain in SQLite across restarts.
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
        self.lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="run-simulator")
        self.closed = False

    def submit(self, value):
        settings = validate_settings(value)
        with self.lock:
            if self.closed:
                raise QueueFull("Run service is stopping")
            if sum(job["status"] in ("queued", "running") for job in self.jobs.values()) >= self.capacity:
                raise QueueFull("Run queue is full; try again after a Run completes")
            while len(self.jobs) >= 64:
                oldest = next(key for key, job in self.jobs.items() if job["status"] in ("completed", "failed"))
                del self.jobs[oldest]
            job_id = uuid.uuid4().hex
            job = {"id": job_id, "status": "queued", "settings": settings, "run_id": None, "error": None}
            self.jobs[job_id] = job
            # Return an acceptance snapshot even if the worker finishes immediately.
            accepted = {**job, "settings": dict(settings)}
            self.executor.submit(self.execute, job_id)
            return accepted

    def get(self, job_id):
        with self.lock:
            job = self.jobs[job_id]
            return {**job, "settings": dict(job["settings"])}

    def execute(self, job_id):
        with self.lock:
            job = self.jobs[job_id]
            if self.closed:
                return
            job["status"] = "running"
            settings = dict(job["settings"])
        command = [self.binary, "--db", self.database]
        for field, value in settings.items():
            command.extend(["--" + field.replace("_", "-"), str(value)])
        if self.revision:
            command.extend(["--revision", self.revision])
        try:
            result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8",
                                    errors="replace", timeout=self.timeout, check=False)
            if result.returncode:
                raise ValueError((result.stderr.strip() or f"Simulator exited with {result.returncode}")[-2000:])
            # Rust reports the committed catalogue key only after save_run succeeds.
            saved = re.search(r"^saved Run ([0-9a-f]{64}) to .+$", result.stderr, re.MULTILINE)
            if not saved:
                raise ValueError("Simulator did not report a saved Run; rebuild the Rust simulator")
            run_id = saved.group(1)
            self.store.get_run(run_id)  # Do not report completion before the row is readable.
            summary = json.loads(result.stdout)
            with self.lock:
                job.update(status="completed", run_id=run_id, summary=summary)
        except subprocess.TimeoutExpired:
            self.fail(job, f"Run exceeded the {self.timeout:g}-second execution limit")
        except (OSError, ValueError, KeyError) as exc:
            self.fail(job, str(exc))
        except Exception:
            self.fail(job, "Could not read the saved Run")

    def fail(self, job, message):
        with self.lock:
            job.update(status="failed", error=message)

    def close(self):
        with self.lock:
            self.closed = True
            for job in self.jobs.values():
                if job["status"] == "queued":
                    job.update(status="failed", error="Run service stopped before execution")
        self.executor.shutdown(wait=True, cancel_futures=True)
