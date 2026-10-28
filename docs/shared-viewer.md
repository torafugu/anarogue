# Viewer workspace and mobile companion

The Web Viewer creates presets, launches Run/AutoRun, tracks the shared queue,
analyzes results and embeds the **same Godot Replay** used by the native client.
The native Godot UI is a lightweight companion: select a preset, monitor jobs
started on another device, stop a batch after its current Run, or replay a result.
Both connect to one API/database; simulation continues on the server when either
client is closed. Use one Run API process per database.

## Viewer

In **Run presets**, save or select a preset and press **Run saved preset**. Unsaved
edits disable launch; save first. The server still validates the saved version
and DSL. Each click starts a new trial, subject to the existing queue limit.

**Jobs** refreshes every two seconds, with 20 jobs per page. It shows the preset
snapshot name/version, status, creation time, batch saved/total and failed counts,
current weights, and errors. Any client can request **Stop after current Run**.
**Inspect latest Run** opens the existing analysis, while **Replay latest Run**
opens a lazily loaded Godot Web player. The native client lists the same jobs via
**Home → Jobs → Monitor selected job / Replay latest Run**.

Inside **Inspect selected Run**, **Replay selected Turn** opens the Web player at
that event's Turn. Previous/Play/Next and arrow keys/space control playback. An
out-of-range Turn clamps to the final Turn. Closing Replay removes the iframe
and releases its player. The embedded mode hides the native Home/Run selector
and adapts the information/map layout to the available space. A missing or failed
Run shows an error rather than substituting an unrelated sample.

## Build and serve the Web player

1. Install Godot and the **matching export templates** through the editor's
   export-template manager (tested with Godot 4.5). Set `GODOT` to the executable
   if `godot`/`godot4` is not on PATH.
2. From the repository root:

   ```bash
   npm ci --prefix viewer
   npm run build:replay --prefix viewer
   python3 tools/run_store.py serve
   ```

3. In another terminal, run `npm run dev --prefix viewer`. For a production
   bundle, run `npm run build --prefix viewer` after exporting Replay. Serve
   `viewer/dist/` and proxy `/api` to the Python service. The existing Vite dev
   and preview servers already provide that proxy.

The export script uses the checked-in `game/web-export.cfg`, preserves any local
`game/export_presets.cfg`, and generates `viewer/public/replay/`. Generated HTML,
JS, WASM and PCK are served together, with `.wasm` as `application/wasm`; do not
rename individual files. They are excluded from git, included in the Viewer
production build, and uploaded together as a CI artifact. Re-export after Godot
source or asset changes. The browser downloads the engine only on opening Replay
(about 37 MB uncompressed for the tested build, before HTTP compression/cache).

Replay uses Compatibility/WebGL 2 and a single-threaded Web export, without
GDExtensions or SharedArrayBuffer isolation headers. Rust runs on the API server;
it is not compiled to WASM. The Web player obtains the API origin from its page,
and reads `/api/runs/{id}/events`. It does not access SQLite, local paths or the
native client's `127.0.0.1` configuration. Publish Viewer, `/replay` and `/api` on
the same origin. Embedded links accept a stored Run ID and optional Turn; no
arbitrary API destination is accepted.

For a phone's native Godot client, configure `ANAROGUE_RUN_API` or `--run-api=`
with the server's LAN address and bind the API to that reachable address.
`127.0.0.1` on the phone refers to the phone. The browser Viewer uses its existing
same-origin proxy. This remains the existing local/trusted-network service.

## Job history and restarts

Job snapshots are saved in an additive `run_jobs` SQLite table when queued,
started, cancelled, progressed and completed/failed. History survives both
client and API restarts. The memory cache still holds at most 64 jobs, while
older snapshots remain accessible through the paginated API.

On API startup, previously queued/running jobs become `failed` with
`interrupted: true` and an explanation. Their last acknowledged counters and
latest saved Run remain visible. They are **not automatically resumed/replayed**;
explicitly start a new job when desired. Graceful shutdown lets a current Run
finish and stops pending batch work. If the process dies immediately after Rust
commits but before Python records the result, a Run can appear in the catalogue
without the final job acknowledgement. Check saved Runs before retrying an
uncertain request. Job Run counts therefore advance only after persistence.

Deleting a preset preserves job and Run snapshots. **Delete all Runs** also
clears job history after checking that no jobs are active; saved presets remain.
No database reset or Rust rebuild is required by this feature.

## API

- `GET /api/jobs?limit=20&offset=0`: shared history with `{jobs,total,limit,offset}`;
  maximum page size 200. List entries omit DSL source and full preset settings.
- `GET /api/jobs/{id}`: full current/persisted snapshot, including settings.
- `POST /api/presets/{id}/run` with `{version}`: existing validated launch.
- `POST /api/jobs/{id}/cancel` with `{}`: existing stop-after-current for AutoRun.
- `GET /api/runs?job_id={id}`: saved results for a job, with existing pagination.

Jobs retain their original preset snapshot. Runs carry `job_id` as catalogue
metadata, without changing raw JSONL events or simulation behavior. Job list and
status reads are shared across clients; launches/cancellation retain same-origin
JSON requirements. Progress reports completed Runs, not individual simulation
Turns. API connection errors retain the previous view and polling retries.

## Validation

`tools/test_shared_jobs.py` covers persistence, interruption recovery, pagination,
memory eviction, independent HTTP clients, cancellation and saved result linkage.
`tools/test_run_launcher_api.py` includes the native shared-jobs client test.
After exporting the player, `npm run test:shared` in `viewer/` exercises two
independent browser clients, Viewer launch, remote cancellation, result linkage,
actual Godot WASM loading, Turn stepping/seeking and iframe cleanup. CI exports
and tests the Web player and publishes the combined Viewer bundle.
