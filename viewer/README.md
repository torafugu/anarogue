# AnaRogue Run Viewer

A browser-based Run catalogue and analysis client backed by the local SQLite API.

## Development

From the repository root, start the data service:

```bash
python3 tools/run_store.py import examples/reference-v8
python3 tools/run_store.py serve --watch logs
```

Then, in another terminal:

```bash
cd viewer
npm ci
npm run dev
```

Vite proxies `/api` to `http://127.0.0.1:8765`. Choose a stored Run directly;
the list and aggregate results refresh automatically every three seconds.
Import JSONL by file picker or drag/drop to save existing logs in SQLite. Offline
imports are explicitly browser-local and are not automatically uploaded later.

### Stored Runs connection troubleshooting

Open both `http://127.0.0.1:8765/api/runs` and `/api/runs` on the Viewer
origin (for example `http://localhost:5173/api/runs`). Both should return JSON.
If only the first works, check how the Viewer is served: use `npm run dev`
or `npm run preview`, or configure a reverse proxy for static hosting.
The API must be reachable from the machine running Vite. If Vite and Python
run on different machines or in different containers, their loopback addresses
refer to different hosts.

For a non-default API address, create `viewer/.env.local`:

```dotenv
ANAROGUE_RUN_API_URL=http://127.0.0.1:8765
```

Set the address to the API host/port reachable from Vite and restart Vite.
This variable configures the server-side proxy for both dev and preview.
Stored Runs reports the failed endpoint and error details. A statistics failure
does not prevent selection of Runs. An empty catalogue (`0 Runs`) means the API
is reachable; check the database path, filters and JSONL import instead.

## Production build

```bash
npm run build
npm run preview
```

The static build is written to `viewer/dist/`. Vite preview also proxies the API;
a static host needs its own same-origin `/api` reverse proxy.

## Current scope

### Weight and Score analysis

The **Weight and Score analysis** panel shows three Pearson correlations and
three mean-Score plots per Strategy: Enemy, Treasure and Stairs weight. The
Conditions selector separates Seed/scenario, simulation and schema versions,
producer revision, non-weight policy settings (such as temperature) and recorded
Max turns. Groups with more observations appear first. Strategy and Seed filters
apply; the Result filter deliberately does not apply to this panel. All matching
Runs are analyzed, not just the current catalogue page.

Unfinished Runs contribute their last saved Score. Each stored Run has equal
weight, including repeated trials. Expand **Values and counts** to see exact
means, sample counts and unfinished counts for every weight value. All plots in
a selected condition group share the same Score scale. No correlation is shown
when there are fewer than two Runs, constant weights or constant Score; the
reason is displayed instead of treating it as zero. Missing/invalid weights are
excluded and counted. A curved relationship can have near-zero Pearson r;
uneven combinations and repeated trials can change both r and marginal means.
These are descriptive statistics, without significance tests or causal claims.

New Runs executed by the updated Python API record Max turns in catalogue
summary metadata. Historical/imported logs without that metadata show an
explicit unknown-limit warning and stay separate from known-limit Runs.
This optional metadata is not part of raw JSONL exports. Restart the API and
Viewer after updating. The panel polls automatically with the catalogue.

### Other features

- Persistent Run selection with strategy/result/seed filters and pagination.
- Aggregates grouped by policy weights, strategy, simulation/schema versions and
  code revision. Means and clear rate exclude unfinished Runs.
- Rank weight combinations by mean score, clear rate or mean depth within the
  active filters. The aggregate table covers all matching Runs, independent of
  catalogue pagination. Filter to the AutoRun Seed for a same-dungeon comparison.
- Cross-file same-seed comparison for compatible versions/revisions.
- Summary metrics, HP history, route maps and searchable event streams.
- Decision rules, observations, benefit/risk, probabilities and raw event JSON.
- Background catalogue updates preserve the current detail view.
- Legacy/offline JSONL reading and sample import remain available.

See [Run store guide](../docs/run-store.md) for import identity, unfinished status,
API routes, known revision limits and operational details.
