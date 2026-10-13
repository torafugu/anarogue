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
