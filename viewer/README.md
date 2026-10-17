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

The Viewer starts on an analysis screen. Select one or more checkbox rows in
the ranking table and press **Compare selected** to open a separate **Same-seed
comparison** screen. Selections identify Strategy, full policy, versions and
revision, so sorting and polling do not change which groups are selected.
Rows without a defined rank can also be selected. Run details are not loaded
automatically on the analysis screen.

The comparison screen loads only selected groups under the captured filters,
across all catalogue pages. Choose **Seed / conditions** to compare a common
Seed/scenario, versions, revision and known/unknown Max turns. The page reports
how many selected policies have matching Runs. Select a card to expand that
Run's metrics, maps and events. Runs without a Seed cannot form a same-seed
group, but direct browsing and imported logs remain inspectable.

Switching Run cards clears the previous inspection while loading. A successful
load verifies the event Run ID against the selected Run, redraws all inspection
sections, and resets event search/category filters. The header shows the loaded
database key, event count and recorded policy. Fetch/parse/render failures leave
no prior Run content behind and display **Retry selected Run**. Rapid selections
cancel earlier requests and only the latest selection can update inspection.

`npm run test:inspection` runs the real browser regression for switching between
different Run contents, stale request handling and failure/retry. Install its
browser with `npx playwright install chromium`; CI installs Chromium and runs
this test automatically.

**Back to analysis** and browser Back/Forward preserve filters and selection in
the current tab. Changing filters clears the selection; **Clear selection**
leaves filters intact. Page reload resets temporary navigation state.
Comparison is a snapshot; compare again to include new Runs. Correlation charts,
direct Run browsing and import guidance are collapsed initially to reduce the
information shown at once.

Use **Strategy** together with **Policy filters** (Enemy, Treasure, Stairs and
Temperature) to narrow the catalogue, ranking, weight analysis and stored
same-seed comparison. Policy filters match exact numeric values from 0 to 1000;
blank means unrestricted, while `0` selects numeric zero. Missing or string-valued
settings do not match zero. Filters combine with AND. **Clear filters** resets
Strategy, Result, Seed and all Policy values. Changing a filter returns to the
first catalogue page and clears the prior selection/detail view; an old,
nonmatching Run is not retained.

For example, select Aggressive, fix Enemy and Stairs, and leave Treasure blank
to inspect Treasure's association with Score under those fixed settings. To
study Enemy in Cautious, fix Treasure and Stairs instead. Fixing a weight removes
its variation, so its correlation correctly becomes undefined; the remaining
varying weights can still be analyzed. The Result filter continues to apply to
catalogue/ranking/comparison but deliberately not to weight analysis.

The **Weight and Score analysis** panel shows three Pearson correlations and
three mean-Score plots per Strategy: Enemy, Treasure and Stairs weight. The
Conditions selector separates Seed/scenario, simulation and schema versions,
producer revision, non-weight policy settings (such as temperature) and recorded
Max turns. Groups with more observations appear first. Strategy, Policy and Seed filters
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

### Filtered Run averages

Between the correlation graphs and Rank list, **Filtered Run averages** displays
Score, Level, Turns, Depth, Kills, Damage, Gold, Decisions, Potions found,
Potions used and Healing. `/api/mean-metrics` computes an arithmetic mean per Run
over every match, beyond catalogue pagination. Strategy, Result, Seed and all
Policy filters apply. Unfinished Runs contribute their latest saved snapshot;
the heading reports matching, finished and unfinished counts. Empty results show
“—”. These averages are independent of the correlation condition group and Rank
selection; ranking continues to use finished Runs only. Restart the updated Run
API when upgrading an existing Viewer session.
