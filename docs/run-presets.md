# Named Run presets

The **Web Viewer creates/runs settings; Godot selects runs and monitors them**. Presets live
in SQLite alongside Runs and are shared by clients using the same API/database.
They survive API and application restarts. No browser-local storage is used.

Viewer can also launch **Run saved preset** directly. Its **Jobs** panel and
Godot **Home → Jobs** share history, progress and cancellation across devices.
See [shared jobs and embedded Web Replay](shared-viewer.md).

1. Start the Run API and Web Viewer as usual (`python3 tools/run_store.py serve`,
   then `cd viewer && npm ci && npm run dev`).
2. In **Map presets**, save a name, Enemy amount, Treasure amount and Map depth.
   Open **Run presets** and enter a name, Strategy, base goal
   weights, Seed, Max turns, select that Map preset and add optional [Player DSL](player-dsl.md).
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
Names must be unique (case-insensitive), 1–80 characters. No Run presets are created
automatically; an empty launcher explains where to create the first one.
A **Default map** (Enemy 100%, Treasure 100%, Depth 5) is created on first setup.

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

## Reusable Map presets

**Map presets** has New, Duplicate, Save, Reload and Delete controls. Enemy and
Treasure amounts are integers from 0 to 500 (%); Depth is 1 to 100. Map presets
contain these three fields only. Seed remains a Run setting so one environment
can be reused across seeds, Strategies, DSL programs and weight sweeps.

Run presets select a Map **ID and version**, show its name and a read-only
Enemy/Treasure/Depth summary, and pin that exact version when saved. Editing a Map
creates a new version and does not change existing Run presets, queued jobs or
historical results. The Run editor keeps an older selected version labeled
“saved version”; choose the latest version from the same dropdown and save the
Run preset to adopt the change. You can still edit DSL/weights while retaining
an older Map version. Native Godot shows the selected Map name/version and values.
Inspection also shows the Map snapshot used by the stored Run.

Map deletion is rejected with 409 while any saved Run preset references it,
including an older version. Reassign or delete those Run presets first. Once
removed, historical jobs and Runs still retain their complete Map snapshot.
**Delete all Runs** preserves both types of presets.

On API startup, existing Run presets are migrated without changing launch
settings or Run preset versions. Equal Enemy/Treasure/Depth combinations share
one Map preset, with generated names such as `Map E200 T50 D8`; rename them as
needed. No Runs are rewritten and no database reset is needed.

## API

| Method | Endpoint | Body / result |
| --- | --- | --- |
| GET | `/api/presets` | `{presets: [...]}` |
| GET | `/api/presets/{id}` | Complete saved preset |
| POST | `/api/presets/validate` | `{kind, settings, map_preset: {id, version}}` → `{valid, total, settings}`; no save/job |
| POST | `/api/presets` | `{name, kind: "run" or "batch", settings, map_preset: {id, version}}`; validates then creates version 1 |
| PUT | `/api/presets/{id}` | `{name, kind, settings, map_preset: {id, version}, version}`; validates then increments version |
| DELETE | `/api/presets/{id}` | `{version}`; preserves all historical Runs |
| POST | `/api/presets/{id}/run` | `{version}` → HTTP 202 job; server resolves saved settings |
| GET | `/api/map-presets` | `{presets: [...]}` (latest versions) |
| GET | `/api/map-presets/{id}` | Current Map preset |
| POST | `/api/map-presets` | `{name, settings: {enemy_amount, treasure_amount, map_depth}}` |
| PUT | `/api/map-presets/{id}` | Same body plus loaded `version`; creates next version |
| DELETE | `/api/map-presets/{id}` | `{version}`; rejected while a Run preset references it |

Run preset responses include `map_preset` with the complete saved Map snapshot;
resolved Map numbers also remain in `settings` for existing API/Godot clients.
New clients send Map ID/version separately and omit inline Map numbers. Conflicting
inline numbers return 400. For backward compatibility, older clients that send
only inline Map settings get a matching Map preset created/reused on save.
CLI and direct job settings remain unchanged. Missing Map IDs/versions return 404.

Mutation requests require JSON and same-origin browser requests. Invalid settings
return 400, missing presets 404, duplicate names/stale versions 409, queue full 429,
unavailable Run service 503. Existing `/api/jobs`, `/api/batches` and CLI APIs remain
available for scripts. The additive tables do not change Run schema version 1
or require a data reset. Restart the API, Viewer and Godot after updating.
