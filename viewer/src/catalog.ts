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
  let response: Response;
  try {
    response = await fetch(path, { ...init, signal: init?.signal ?? AbortSignal.timeout(15000) });
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);
    throw new Error(`Run API ${path}: ${reason}. Check the Viewer /api proxy and API host/port.`);
  }
  if (!response.ok) {
    const body = await response.json().catch(() => null) as {error?: string} | null;
    throw new Error(`Run API ${path}: HTTP ${response.status}${body?.error ? ` — ${body.error}` : ""}`);
  }
  if (!response.headers.get("Content-Type")?.includes("application/json")) {
    throw new Error(`Run API ${path}: expected JSON, received ${response.headers.get("Content-Type") ?? "unknown content type"}. Start Viewer with Vite; static hosting needs an /api reverse proxy.`);
  }
  return response.json() as Promise<T>;
}
