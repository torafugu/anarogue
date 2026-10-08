# Persistent Run store (v1)

The replay UI selects Runs, rather than files. A local Python 3 service imports
existing JSONL into SQLite, watches new/changed logs, and serves Godot and the Web
viewer. The Rust simulator can also save directly to the same SQLite database;
JSONL remains available as an optional output and exchange format.

## Start

From the repository root, with Python 3.10 or newer:

```bash
python3 tools/run_store.py import examples/reference-v8
python3 tools/run_store.py serve --watch logs
```

The default database is `logs/runs.sqlite3`; the API listens on
`http://127.0.0.1:8765`. No Python packages or database server are required.
To use another database, put `--db /path/runs.sqlite3` before the subcommand.

Existing Godot logs can also be imported or watched: pass the actual filesystem
path corresponding to Godot's `user://` directory. `--watch` accepts multiple
files/directories and discovers JSONL recursively, including files created later.
The service scans every three seconds; `--interval` changes this interval.

## Direct Rust persistence

From the repository root:

```bash
cargo run --release --manifest-path simulation-core/Cargo.toml -- \
  --strategy cautious --seed 424242 --max-turns 5000 \
  --db logs/runs.sqlite3
```

`--db` creates the database if needed and saves the complete Run and events in a
single transaction after simulation finishes. It uses the same v1 schema,
canonical event JSON, SHA-256 identity and summary fields as the Python importer.
The schema is shared in `schemas/run-store-v1.sql`. The Rust library API is
`anarogue_simulation::run_store::save_run(path, events)`; saving the same event
snapshot again is idempotent and an older snapshot cannot truncate history.
New CLI executions receive distinct Run IDs even for the same seed and timestamp.
The seed still reproduces the same simulation outcome.

Run the API against the same database to browse direct writes:

```bash
python3 tools/run_store.py serve
```

The API and producer are independent processes. The API need not be running to
save Runs; once running, Godot/Web discover completed writes through their normal
automatic catalogue refresh. No JSONL watcher or import step is required for
Rust's direct writes. Live incremental per-turn persistence is not implemented;
a crash before the final transaction leaves no partial Run from that execution.
Turn-limited executions without a terminal event retain `unfinished` status.

Add `--output logs/run.jsonl` to also export JSONL, and optionally
`--revision <producer-commit>` to record the source revision in `run_start` and
catalogue metadata. Importing that JSONL into the same DB does not duplicate it.
`--revision` requires `--db` or `--output` and must be nonempty. The CLI keeps the
original JSON summary on stdout and reports the saved catalogue ID on stderr.
SQLite is bundled with the Rust dependency; no system SQLite installation or
Python subprocess is needed for persistence.

Database and JSONL files are separate outputs: the DB is committed first. If the
subsequent JSONL write fails, the CLI exits with an error and the saved DB Run
remains. `--output` cannot point to the DB or its WAL/SHM sidecars, including file
aliases. Unknown DB schema versions and conflicting event history return errors.
WAL and a ten-second busy timeout permit API reads and serialize concurrent writers.

For Godot or other JSONL producers, continue writing into watched directories or
watch the actual Godot `user://` directory as described above.

Use a new producer Run ID for each distinct trial. The catalogue retains all
imported Runs even if their source files are moved or removed.

## Godot replay

Run `game/` after starting the API. The Run selector displays strategy, seed,
depth, result and a short database ID. Hovering shows the original Run ID,
start time and simulation version. There is no file selector or Refresh logs
button. The list updates every three seconds and keeps the selected Run and
playback frame. Selecting a Run loads an event snapshot and resets playback to
its beginning; background catalogue changes never replace that snapshot.

If the API is unavailable, the bundled sample remains playable and the status
shows `API offline`. The client retries automatically and switches to the
catalogue when it becomes available. An empty online database shows an import
hint. JSONL remains available for offline tools/tests through
`--replay=/absolute/path/run.jsonl`.

Configure another endpoint with `ANAROGUE_RUN_API` or `--run-api=http://host:8765`.
For a mobile client, the API must be reachable on the development computer's
network address; `127.0.0.1` on the phone points to the phone. The service can be
bound to that computer's LAN address with `serve --host <LAN-address>`. This is a
local development service without authentication; use it on a trusted network.

## Web viewer

```bash
cd viewer
npm ci
npm run dev
```

Vite proxies `/api` to port 8765; `npm run preview` uses the same proxy. A hosted
static deployment needs an equivalent same-origin `/api` reverse proxy.

The catalogue filters by strategy, result and seed and provides pages of 100
Runs. The list and aggregate table update automatically. Detail analysis keeps
its selected event, depth, search and filters until the user changes them. Runs
can be compared across source files when seed, simulation version, schema
version and code revision match. The comparison shows up to the latest 100
matching Runs. Existing HP, route, decision and combat analysis uses the
selected Run's events.

`Import JSONL`, drag/drop and `Import sample` save to the database when the API
is online. If offline, they remain browser-local and clearly report that the
log was not saved. Returning online does not silently upload those local logs.

## Data and import rules

- `runs`: catalogue identity, original Run ID, start time, strategy, seed,
  scenario, simulation/schema versions, code revision, policy weights and
  temperature, event count, terminal status and cached resource/combat summary.
- `events`: original JSON objects, ordered by `(database Run ID, sequence)`.
  Payloads retain observations, candidate benefit/risk and probability data.
- The database Run ID is SHA-256 of canonical `run_start`. This distinguishes
  reused external IDs across versions without rewriting replay payloads.
- Reimporting the same events is idempotent. An append adds only new sequences;
  an older snapshot cannot truncate an existing Run.
- Conflicting content for an existing sequence rejects the entire file import
  transaction. It must be a new Run, not a replacement for historical events.
- Inputs must include `run_start` at sequence 1 and contiguous ordered sequences
  per Run. Explicit imports reject malformed JSON. A watcher ignores a final
  incomplete JSON line while the producer is writing it; newline-terminated
  malformed lines reject the file and leave the stored data intact.
- Completed Runs cannot be extended. A Run lacking a terminal event is labelled
  `unfinished`: it may be running, interrupted, or stopped by a turn limit.
  This status is not proof that a producer process is currently alive.
- WAL mode and transactions allow readers during imports. Each HTTP request
  uses its own SQLite connection. The database format has `user_version=1`.

Code revision is read from `run_start.details.code_revision`, or supplied as
`--revision <producer-revision>` before `import`/`serve`. Old logs that lack this
information stay `revision unknown`; supply the producer revision on the first
import, since reimports preserve existing metadata. Do not assign today's revision
to historical runs. Unknown revisions cannot establish exact code compatibility. Aggregate
statistics group separately by strategy, goal-policy JSON, simulation version,
schema version and revision. Only finished Runs contribute to means and clear
rate; unfinished counts remain visible. Clear rate is clears / all finished
Runs, including defeated and restarted Runs.

## API

| Method / path | Result |
| --- | --- |
| `GET /api/runs` | `{runs, total, offset, limit}`; newest imported first |
| `GET /api/runs/<id>` | One Run's metadata and summary |
| `GET /api/runs/<id>/events` | `{events}` for replay/detail analysis |
| `GET /api/runs/<id>/log` | JSONL export with original event payloads |
| `GET /api/stats` | Aggregate groups; no event payloads loaded |
| `POST /api/import` | JSONL body (`application/x-ndjson`, up to 25 MB), `{run_ids}` |

List and stats filters: `strategy_id`, `scenario_seed`, `status`,
`simulation_version`, `schema_version`, `code_revision`. Empty `code_revision`
selects unknown revisions. Listing also accepts `limit` (1–500) and `offset`.
HTTP 400 indicates invalid import/pagination, 404 a missing Run/endpoint.

## Verification

```bash
python3 -m unittest discover -s tools -p test_run_store.py -v
GODOT=/path/to/godot python3 tools/test_run_api.py
cargo test --manifest-path simulation-core/Cargo.toml --all-targets
python3 -m unittest discover -s tools -p test_rust_run_store.py -v
```

The integration test uses a temporary database and ephemeral local port and
exercises Godot catalogue pagination (>500 Runs), event loading, selection,
playback reset, and background-update preservation. It does not modify user data.

Next extensions can add incremental event ingestion,
parameter sweeps, and benefit/risk or death-path aggregates using the stored
events. The current watcher rereads a changed file; for very large continuous
logs, rotating outputs per Run limits that cost.
