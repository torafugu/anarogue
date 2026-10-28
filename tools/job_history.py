"""Durable job snapshots; execution is owned by one API process per database."""
import json
from contextlib import closing
from datetime import datetime, timezone


def timestamp():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


class JobHistory:
    def __init__(self, store):
        self.store = store
        with closing(store.connect()) as db, db:
            db.execute("""CREATE TABLE IF NOT EXISTS run_jobs (
                id TEXT PRIMARY KEY, created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL, payload TEXT NOT NULL)""")

    def save(self, job):
        job["updated_at"] = timestamp()
        with closing(self.store.connect()) as db, db:
            db.execute("""INSERT INTO run_jobs VALUES (?,?,?,?) ON CONFLICT(id)
                DO UPDATE SET updated_at=excluded.updated_at,payload=excluded.payload""",
                (job["id"], job["created_at"], job["updated_at"], json.dumps(job, ensure_ascii=False, allow_nan=False)))

    def get(self, key):
        with closing(self.store.connect()) as db:
            row = db.execute("SELECT payload FROM run_jobs WHERE id=?", (key,)).fetchone()
            if row is None:
                raise KeyError(key)
            return json.loads(row[0])

    def list(self, limit=100, offset=0):
        with closing(self.store.connect()) as db:
            rows = db.execute("SELECT payload FROM run_jobs ORDER BY created_at DESC,rowid DESC LIMIT ? OFFSET ?", (limit, offset)).fetchall()
            total = db.execute("SELECT COUNT(*) FROM run_jobs").fetchone()[0]
        jobs = []
        for row in rows:
            job = json.loads(row[0])
            job["settings"] = {k: v for k, v in job["settings"].items() if k != "dsl"}
            if "preset" in job:
                job["preset"] = {k: v for k, v in job["preset"].items() if k != "settings"}
            if isinstance(job.get("current_settings"), dict):
                job["current_settings"].pop("dsl", None)
            jobs.append(job)
        return {"jobs": jobs, "total": total, "limit": limit, "offset": offset}

    def recover(self):
        with closing(self.store.connect()) as db:
            rows = db.execute("SELECT payload FROM run_jobs WHERE json_extract(payload,'$.status') IN ('queued','running')").fetchall()
        for row in rows:
            job = json.loads(row[0])
            job.update(status="failed", interrupted=True, current_settings=None,
                       error="API restarted before completion. Saved Runs remain available; start a new job to run again.")
            self.save(job)
