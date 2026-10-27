import { api, type RunGroup, type StoredRun } from "./catalog.ts";

type PolicyGroup = Pick<RunGroup, "strategy_id" | "simulation_version" | "schema_version" | "code_revision" | "goal_policy">;

/** Human label only: never use names/results/dates as comparison identity. */
export function rankRunLabel(group: RunGroup, strategyName: string): string {
  const names = [...new Set(group.preset_names ?? [])];
  if (!names.length || group.has_legacy_runs) names.push(strategyName);
  const depth = group.depth_min === undefined || group.depth_max === undefined ? "Depth unknown"
    : group.depth_min === group.depth_max ? `D${group.depth_min}` : `D${group.depth_min}–${group.depth_max}`;
  const results = [
    ["cleared", group.cleared], ["defeated", group.defeated ?? 0], ["restarted", group.restarted ?? 0],
    ["unfinished", group.runs - group.finished],
    ["other finished", Math.max(0, group.finished - group.cleared - (group.defeated ?? 0) - (group.restarted ?? 0))],
  ] as const;
  const result = results.filter(([, count]) => count > 0).map(([name, count]) => `${name} ${count}`).join(", ") || "No results";
  const formatDate = (value?: string | null) => value && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value.replaceAll("-", "") : null;
  const first = formatDate(group.first_run_date), last = formatDate(group.last_run_date);
  const date = first && last ? (first === last ? first : `${first}–${last}`) + (group.undated_runs ? " + date unknown" : "") : "Date unknown";
  return `${[...new Set(names)].join(", ")} / ${depth} / ${result} / ${date}`;
}
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
