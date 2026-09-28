# AnaRogue Run Viewer

A local, browser-based viewer for AnaRogue JSON Lines run logs.

## Development

```bash
cd viewer
npm install
npm run dev
```

Open the URL printed by Vite, then drop
`simple_rogue_battle_log.jsonl` onto the page. The viewer keeps the log in the
browser and does not upload it.

## Production build

```bash
npm run build
npm run preview
```

The static build is written to `viewer/dist/`.

## Current scope

- Load JSONL using drag and drop or the file picker.
- Select one run when Godot's append-only log contains multiple runs.
- Compare Aggressive and Cautious runs automatically when they share a scenario ID.
- View summary metrics, HP history, and movement by dungeon depth.
- Filter and search the event stream.
- Inspect decision rule, reason, observation, action, and raw event JSON.
- Read legacy events without `schema_version` with a compatibility warning.
