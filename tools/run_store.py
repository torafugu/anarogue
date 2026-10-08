"""Persistent run catalogue and local HTTP API; Python standard library only."""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import sqlite3
import threading
from collections import defaultdict
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

LOG = logging.getLogger(__name__)
TERMINAL = {"player_defeated": "defeated", "dungeon_cleared": "cleared", "restart": "restarted"}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def parse_log(text, allow_partial=False):
    groups = defaultdict(list)
    lines = text.splitlines(keepends=True)
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            if allow_partial and line_number == len(lines) and not line.endswith("\n"):
                break  # A producer may be writing its final line right now.
            raise ValueError(f"Line {line_number}: invalid JSON") from exc
        if not isinstance(event, dict) or not isinstance(event.get("run_id"), str) or not event["run_id"]:
            raise ValueError(f"Line {line_number}: missing run_id")
        if type(event.get("sequence")) is not int or event["sequence"] < 1:
            raise ValueError(f"Line {line_number}: sequence must be a positive integer")
        if not isinstance(event.get("event"), str) or not isinstance(event.get("details", {}), dict):
            raise ValueError(f"Line {line_number}: invalid event or details")
        for field in ("turn", "depth", "schema_version", "hp", "gold"):
            if field in event and type(event[field]) is not int:
                raise ValueError(f"Line {line_number}: invalid {field}")
        if not isinstance(event.get("player_state", {}), dict):
            raise ValueError(f"Line {line_number}: invalid player_state")
        player = event.get("player_state", {})
        for field in ("hp", "gold", "score", "level", "xp"):
            if field in player and type(player[field]) is not int:
                raise ValueError(f"Line {line_number}: invalid player {field}")
        for field in ("damage", "healed", "simulation_version"):
            if field in event.get("details", {}) and type(event["details"][field]) is not int:
                raise ValueError(f"Line {line_number}: invalid details {field}")
        canonical(event)  # Also rejects NaN/Infinity.
        groups[event["run_id"]].append(event)
    if not groups and not allow_partial:
        raise ValueError("No Runs found in JSONL")
    for run_id, events in groups.items():
        if events[0]["event"] != "run_start" or events[0]["sequence"] != 1:
            raise ValueError(f"{run_id}: import must include run_start at sequence 1")
        if [e["sequence"] for e in events] != list(range(1, len(events) + 1)):
            raise ValueError(f"{run_id}: event sequences must be contiguous and ordered")
    return groups


class RunStore:
    def __init__(self, path):
        self.path = str(path)
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with closing(self.connect()) as db:
            version = db.execute("PRAGMA user_version").fetchone()[0]
            if version not in (0, 1):
                raise ValueError(f"Unsupported run database version {version}")
            db.executescript((Path(__file__).resolve().parents[1] / "schemas/run-store-v1.sql").read_text())

    def connect(self):
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    def import_text(self, text, revision="", allow_partial=False):
        groups = parse_log(text, allow_partial)
        imported = []
        with closing(self.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            for run_id, events in groups.items():
                first = events[0]
                details = first.get("details", {})
                key = hashlib.sha256(canonical(first).encode()).hexdigest()
                old = db.execute("SELECT * FROM runs WHERE id=?", (key,)).fetchone()
                existing = {r["sequence"]: r["payload"] for r in db.execute(
                    "SELECT sequence,payload FROM events WHERE run_key=?", (key,))}
                for event in events:
                    if event["sequence"] in existing and existing[event["sequence"]] != canonical(event):
                        raise ValueError(f"{run_id}: conflicting event at sequence {event['sequence']}; use a new run_id")
                if old and revision and old["code_revision"] not in ("", revision):
                    raise ValueError(f"{run_id}: conflicting code revision")
                if old and len(events) <= old["event_count"]:
                    imported.append(key)
                    continue  # Importing an old snapshot must never truncate a run.
                if old and old["status"] != "unfinished":
                    raise ValueError(f"{run_id}: completed runs cannot be extended")
                summary = summarize(events)
                values = (
                    key, run_id, str(first.get("time", "")),
                    str(first.get("strategy_id", details.get("strategy_id", "unknown"))),
                    str(first.get("scenario_id", details.get("scenario_id", ""))),
                    first.get("scenario_seed", details.get("scenario_seed")),
                    int(details.get("simulation_version", first.get("schema_version", 1))),
                    int(first.get("schema_version", 1)),
                    old["code_revision"] if old else str(details.get("code_revision", revision)),
                    canonical(details.get("goal_policy", {})), summary["status"], len(events),
                    summary["turns"], summary["max_depth"], summary["score"], canonical(summary),
                )
                db.execute("""INSERT INTO runs
                    (id,run_id,started_at,strategy_id,scenario_id,scenario_seed,simulation_version,
                     schema_version,code_revision,goal_policy,status,event_count,turns,max_depth,score,summary)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET status=excluded.status,
                    event_count=excluded.event_count,turns=excluded.turns,max_depth=excluded.max_depth,
                    score=excluded.score,summary=excluded.summary,updated_at=CURRENT_TIMESTAMP""", values)
                db.executemany("INSERT OR IGNORE INTO events VALUES (?,?,?)", [
                    (key, e["sequence"], canonical(e)) for e in events if e["sequence"] not in existing])
                imported.append(key)
        return imported

    def import_file(self, path, revision="", allow_partial=False):
        return self.import_text(Path(path).read_text(encoding="utf-8"), revision, allow_partial)

    @staticmethod
    def where(filters):
        allowed = {"strategy_id", "simulation_version", "schema_version", "status", "scenario_seed", "code_revision"}
        clauses, params = [], []
        for key in allowed:
            if key in filters and (filters[key] != "" or key == "code_revision"):
                clauses.append(f"{key}=?")
                params.append(filters[key])
        return (" WHERE " + " AND ".join(clauses) if clauses else ""), params

    @staticmethod
    def decode(row):
        result = dict(row)
        result.update(json.loads(result.pop("summary")))
        result["goal_policy"] = json.loads(result["goal_policy"])
        return result

    def list_runs(self, filters=None, limit=200, offset=0):
        where, params = self.where(filters or {})
        with closing(self.connect()) as db:
            total = db.execute("SELECT COUNT(*) FROM runs" + where, params).fetchone()[0]
            rows = db.execute("SELECT * FROM runs" + where +
                              " ORDER BY created_at DESC,rowid DESC LIMIT ? OFFSET ?", [*params, limit, offset])
            return {"runs": [self.decode(row) for row in rows], "total": total, "offset": offset, "limit": limit}

    def get_run(self, key):
        with closing(self.connect()) as db:
            row = db.execute("SELECT * FROM runs WHERE id=?", (key,)).fetchone()
            if row is None:
                raise KeyError(key)
            return self.decode(row)

    def events(self, key):
        with closing(self.connect()) as db:
            if not db.execute("SELECT 1 FROM runs WHERE id=?", (key,)).fetchone():
                raise KeyError(key)
            return [json.loads(row[0]) for row in db.execute(
                "SELECT payload FROM events WHERE run_key=? ORDER BY sequence", (key,))]

    def stats(self, filters=None):
        where, params = self.where(filters or {})
        with closing(self.connect()) as db:
            rows = db.execute("""SELECT strategy_id,simulation_version,schema_version,code_revision,
                goal_policy,COUNT(*) AS runs,
                SUM(status!='unfinished') AS finished,
                SUM(status='cleared') AS cleared,
                SUM(status='defeated') AS defeated,
                AVG(CASE WHEN status!='unfinished' THEN score END) AS mean_score,
                AVG(CASE WHEN status!='unfinished' THEN max_depth END) AS mean_depth,
                AVG(CASE WHEN status!='unfinished' THEN turns END) AS mean_turns
                FROM runs""" + where + " GROUP BY strategy_id,simulation_version,schema_version,code_revision,goal_policy", params)
            result = []
            for row in rows:
                group = dict(row)
                group["goal_policy"] = json.loads(group["goal_policy"])
                group["clear_rate"] = group["cleared"] / group["finished"] if group["finished"] else None
                result.append(group)
            return {"groups": result}


def summarize(events):
    last = events[-1]
    player = last.get("player_state", {})
    summary = {"turns": max(e.get("turn", 0) for e in events),
               "max_depth": max(e.get("depth", 1) for e in events),
               "score": player.get("score", 0), "level": player.get("level", 1),
               "xp": player.get("xp", 0), "hp": player.get("hp", last.get("hp", 0)),
               "gold": player.get("gold", last.get("gold", 0)),
               "status": "unfinished", "kills": 0, "damage_taken": 0,
               "potions_picked_up": 0, "potions_used": 0, "hp_healed": 0}
    for event in events:
        details = event.get("details", {})
        result = details.get("result")
        if event["event"] == "battle_result":
            summary["status"] = TERMINAL.get(result, summary["status"])
            summary["kills"] += result == "enemy_defeated"
            if result == "player_hit":
                summary["damage_taken"] += details.get("damage", 0)
        if event["event"] == "item_result":
            summary["potions_picked_up"] += result == "item_picked_up"
            summary["potions_used"] += result == "item_used"
            if result == "item_used":
                summary["hp_healed"] += details.get("healed", 0)
    return summary


class LogWatcher:
    def __init__(self, store, paths, revision=""):
        self.store, self.paths, self.revision = store, paths, revision
        self.signatures = {}
        self.lock = threading.Lock()

    def scan(self):
        with self.lock:
            for path in log_paths(self.paths):
                try:
                    stat = path.stat()
                    signature = (stat.st_mtime_ns, stat.st_size)
                    if self.signatures.get(path) == signature:
                        continue
                    self.store.import_file(path, self.revision, allow_partial=True)
                    self.signatures[path] = signature
                except (OSError, ValueError, sqlite3.Error) as exc:
                    LOG.warning("Could not import %s: %s", path, exc)


def log_paths(paths):
    files = set()
    for value in paths:
        path = Path(value)
        if path.is_dir():
            files.update(path.rglob("*.jsonl"))
        elif path.is_file():
            files.add(path)
    return sorted(files)


def make_server(store, host="127.0.0.1", port=8765):
    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, value, content_type="application/json"):
            payload = (canonical(value) if content_type == "application/json" else value).encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type + "; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(payload)

        def do_GET(self):
            try:
                url = urlsplit(self.path)
                query = {k: v[-1] for k, v in parse_qs(url.query, keep_blank_values=True).items()}
                if url.path == "/api/runs":
                    limit, offset = int(query.get("limit", 200)), int(query.get("offset", 0))
                    if not 1 <= limit <= 500 or offset < 0:
                        raise ValueError("Invalid pagination")
                    self.reply(200, store.list_runs(query, limit, offset))
                elif url.path == "/api/stats":
                    self.reply(200, store.stats(query))
                elif url.path.startswith("/api/runs/"):
                    key, _, suffix = url.path[len("/api/runs/"):].partition("/")
                    if not suffix:
                        self.reply(200, store.get_run(unquote(key)))
                        return
                    events = store.events(unquote(key))
                    if suffix == "events":
                        self.reply(200, {"events": events})
                    elif suffix == "log":
                        self.reply(200, "\n".join(canonical(e) for e in events) + "\n", "application/x-ndjson")
                    else:
                        self.reply(404, {"error": "Unknown endpoint"})
                else:
                    self.reply(404, {"error": "Unknown endpoint"})
            except KeyError:
                self.reply(404, {"error": "Run not found"})
            except (ValueError, TypeError) as exc:
                self.reply(400, {"error": str(exc)})

        def do_POST(self):
            # Import is same-origin only. Vite proxies /api to this local server.
            if self.path != "/api/import":
                self.reply(404, {"error": "Unknown endpoint"})
                return
            if self.headers.get("Content-Type", "").split(";")[0] != "application/x-ndjson":
                self.reply(415, {"error": "Use application/x-ndjson"})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 25 * 1024 * 1024:
                    raise ValueError("Import size must be 1 byte to 25 MB")
                keys = store.import_text(self.rfile.read(length).decode("utf-8"))
                self.reply(200, {"run_ids": keys})
            except (ValueError, TypeError, OverflowError, sqlite3.Error) as exc:
                self.reply(400, {"error": str(exc)})

        def log_message(self, format, *args):
            LOG.debug(format, *args)

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", default="logs/runs.sqlite3")
    parser.add_argument("--revision", default="", help="Producer code revision, if known")
    commands = parser.add_subparsers(dest="command", required=True)
    importer = commands.add_parser("import", help="Import existing JSONL files/directories")
    importer.add_argument("paths", nargs="+")
    serve = commands.add_parser("serve", help="Serve the Run API and watch append-only JSONL")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8765)
    serve.add_argument("--watch", nargs="*", default=[])
    serve.add_argument("--interval", type=float, default=3)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    store = RunStore(args.db)
    if args.command == "import":
        files = log_paths(args.paths)
        if not files:
            parser.error("No JSONL files found")
        for path in files:
            print(f"{path}: {len(store.import_file(path, args.revision))} Run(s)")
        return
    if args.interval <= 0:
        parser.error("interval must be positive")
    watcher = LogWatcher(store, args.watch, args.revision)
    watcher.scan()
    stop = threading.Event()

    def watch():
        while not stop.wait(args.interval):
            watcher.scan()

    worker = threading.Thread(target=watch, daemon=True)
    worker.start()
    server = make_server(store, args.host, args.port)
    LOG.info("Run API: http://%s:%s/api/runs", *server.server_address)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()


if __name__ == "__main__":
    main()
