export interface StoredRun {
  id: string;
  run_id: string;
  started_at: string;
  strategy_id: string;
  scenario_seed: number | null;
  simulation_version: number;
  schema_version: number;
  code_revision: string;
  goal_policy: Record<string, number>;
  status: string;
  event_count: number;
  max_depth: number;
  score: number;
  level: number;
  turns: number;
}

export interface RunGroup {
  strategy_id: string;
  simulation_version: number;
  schema_version: number;
  code_revision: string;
  goal_policy: Record<string, number>;
  runs: number;
  finished: number;
  cleared: number;
  clear_rate: number | null;
  mean_score: number | null;
  mean_depth: number | null;
  mean_turns: number | null;
}

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(path, { ...init, signal: init?.signal ?? AbortSignal.timeout(15000) });
  if (!response.ok) {
    const body = await response.json().catch(() => null) as {error?: string} | null;
    throw new Error(body?.error ?? `Run API: HTTP ${response.status}`);
  }
  return response.json() as Promise<T>;
}
