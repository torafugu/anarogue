import { api, type RunGroup, type StoredRun } from "./catalog.ts";

type PolicyGroup = Pick<RunGroup, "strategy_id" | "simulation_version" | "schema_version" | "code_revision" | "goal_policy">;
export function policyGroupKey(group: PolicyGroup): string {
  return JSON.stringify([group.strategy_id, group.simulation_version, group.schema_version, group.code_revision,
    Object.entries(group.goal_policy).sort(([a], [b]) => a.localeCompare(b))]);
}
export interface ComparisonCondition { key: string; label: string; runs: StoredRun[] }
export function comparisonConditions(runs: StoredRun[]): ComparisonCondition[] {
  const groups = new Map<string, ComparisonCondition>();
  for (const run of runs) {
    if (run.scenario_seed === null) continue;
    const limit = run.execution_settings?.max_turns ?? null;
    const key = JSON.stringify([run.scenario_seed, run.scenario_id ?? "", run.simulation_version, run.schema_version, run.code_revision, limit]);
    if (!groups.has(key)) groups.set(key, { key, label: `seed ${run.scenario_seed} · sim ${run.simulation_version}/schema ${run.schema_version} · ${run.code_revision || "revision unknown"} · max turns ${limit ?? "unknown"}`, runs: [] });
    groups.get(key)!.runs.push(run);
  }
  return [...groups.values()].sort((a, b) => a.label.localeCompare(b.label, undefined, { numeric: true }));
}
export async function loadRankRuns(query: URLSearchParams, selected: Set<string>, fetchPage = (params: URLSearchParams) => api<{ runs: StoredRun[]; total: number }>(`/api/runs?${params}`)): Promise<StoredRun[]> {
  const matches = new Map<string, StoredRun>();
  const params = new URLSearchParams(query);
  let offset = 0;
  while (true) {
    params.set("limit", "500"); params.set("offset", String(offset));
    const page = await fetchPage(new URLSearchParams(params));
    for (const run of page.runs) if (selected.has(policyGroupKey(run))) matches.set(run.id, run);
    offset += page.runs.length;
    if (!page.runs.length || offset >= page.total) break;
  }
  return [...matches.values()];
}
