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

## Production build

```bash
npm run build
npm run preview
```

The static build is written to `viewer/dist/`. Vite preview also proxies the API;
a static host needs its own same-origin `/api` reverse proxy.

## Current scope

- Persistent Run selection with strategy/result/seed filters and pagination.
- Aggregates grouped by policy weights, strategy, simulation/schema versions and
  code revision. Means and clear rate exclude unfinished Runs.
- Cross-file same-seed comparison for compatible versions/revisions.
- Summary metrics, HP history, route maps and searchable event streams.
- Decision rules, observations, benefit/risk, probabilities and raw event JSON.
- Background catalogue updates preserve the current detail view.
- Legacy/offline JSONL reading and sample import remain available.

See [Run store guide](../docs/run-store.md) for import identity, unfinished status,
API routes, known revision limits and operational details.
