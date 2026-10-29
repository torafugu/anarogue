# Named Run presets

The **Web Viewer creates/runs settings; Godot selects runs and monitors them**. Presets live
in SQLite alongside Runs and are shared by clients using the same API/database.
They survive API and application restarts. No browser-local storage is used.

Viewer can also launch **Run saved preset** directly. Its **Jobs** panel and
Godot **Home → Jobs** share history, progress and cancellation across devices.
See [shared jobs and embedded Web Replay](shared-viewer.md).

1. Start the Run API and Web Viewer as usual (`python3 tools/run_store.py serve`,
   then `cd viewer && npm ci && npm run dev`).
2. Open **Run presets** at the top of Viewer. Enter a name, Strategy, base goal
   weights, Seed, Max turns, Map settings and optional [Player DSL](player-dsl.md).
3. **Validate settings / DSL** checks without running or saving. **Save preset**
   validates again and saves; invalid DSL cannot be saved. Blank DSL uses the
   existing AI. Rules retain their priority before automatic healing/Brute evasion.
4. In Godot → **Run**, select the named preset, review its summary and press
   **Run selected preset**. **Reload presets** fetches changes made in Viewer.
   The launcher contains no editable Strategy, numeric settings or DSL fields.
5. A single Run opens its result in Replay. An AutoRun shows the existing
   progress and stop-after-current controls. Replay remains available during a batch.

**New** starts from defaults. **Duplicate** copies the current editor into a new,
unsaved preset. Choosing a different preset, New or Reload asks before discarding
unsaved edits. **Delete preset** removes that configuration and preserves Runs.
Names must be unique (case-insensitive), 1–80 characters. No presets are created
automatically; an empty launcher explains where to create the first one.

Choose **Mode: AutoRun** to save one/both Strategies and comma-separated
Enemy/Treasure/Stairs value lists. Combinations exclude all-zero base weights,
remove duplicate list values and are limited to 2,000 Runs. Default lists 0–4
with both Strategies produce 248 Runs. DSL is validated against every effective
combination before saving and before execution. A fixed DSL weight overrides
that sweep dimension, so avoid it when distinct effective policies are wanted.

Every save increments a preset version. Edits/deletes require the version loaded
by the editor. A concurrent change returns HTTP 409 and preserves the draft.
Reload and review before saving again. Launch also requires the selected version;
an outdated Godot selection returns an error and asks for a reload.

At acceptance the API copies the complete preset into the job. Each resulting
Run stores that snapshot under `preset` (ID/name/version/mode/full settings),
independently of later edits or deletion. Viewer inspection shows its saved name
and version. Actual DSL source/hash and effective policy remain in the original
Run events. Preset metadata is in the database catalogue, not the JSONL schema.
**Delete all Runs** clears Run/event history and preserves presets.

## API

| Method | Endpoint | Body / result |
| --- | --- | --- |
| GET | `/api/presets` | `{presets: [...]}` |
| GET | `/api/presets/{id}` | Complete saved preset |
| POST | `/api/presets/validate` | `{kind, settings}` → `{valid, total, settings}`; no save/job |
| POST | `/api/presets` | `{name, kind: "run" or "batch", settings}`; validates then creates version 1 |
| PUT | `/api/presets/{id}` | `{name, kind, settings, version}`; validates then increments version |
| DELETE | `/api/presets/{id}` | `{version}`; preserves all historical Runs |
| POST | `/api/presets/{id}/run` | `{version}` → HTTP 202 job; server resolves saved settings |

Mutation requests require JSON and same-origin browser requests. Invalid settings
return 400, missing presets 404, duplicate names/stale versions 409, queue full 429,
unavailable Run service 503. Existing `/api/jobs`, `/api/batches` and CLI APIs remain
available for scripts. The additional table does not change Run schema version 1
or require a data reset. Restart the API, Viewer and Godot after updating.
