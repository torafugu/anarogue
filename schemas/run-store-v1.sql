PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS runs (
    id TEXT PRIMARY KEY, run_id TEXT NOT NULL, started_at TEXT NOT NULL,
    strategy_id TEXT NOT NULL, scenario_id TEXT NOT NULL,
    scenario_seed INTEGER, simulation_version INTEGER NOT NULL,
    schema_version INTEGER NOT NULL, code_revision TEXT NOT NULL,
    goal_policy TEXT NOT NULL, status TEXT NOT NULL,
    event_count INTEGER NOT NULL, turns INTEGER NOT NULL,
    max_depth INTEGER NOT NULL, score INTEGER NOT NULL,
    summary TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS events (
    run_key TEXT NOT NULL REFERENCES runs(id), sequence INTEGER NOT NULL,
    payload TEXT NOT NULL, PRIMARY KEY(run_key, sequence)
);
CREATE INDEX IF NOT EXISTS runs_comparison
    ON runs(scenario_seed, simulation_version, schema_version, code_revision);
CREATE INDEX IF NOT EXISTS runs_strategy ON runs(strategy_id, status);
PRAGMA user_version=1;
