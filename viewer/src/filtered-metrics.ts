export interface MeanMetrics {
  runs: number;
  unfinished: number;
  means: Record<string, number | null>;
}

export const meanMetricFields = [
  ["Score", "score"], ["Level", "level"], ["Turns", "turns"], ["Depth", "max_depth"],
  ["Kills", "kills"], ["Damage", "damage_taken"], ["Gold", "gold"], ["Decisions", "decisions"],
  ["Potions found", "potions_picked_up"], ["Potions used", "potions_used"], ["Healing", "hp_healed"],
] as const;

const filterFields = [
  ["Strategy", "strategy_id"], ["Result", "status"], ["Seed", "scenario_seed"],
  ["Enemy", "enemy_weight"], ["Treasure", "item_weight"], ["Stairs", "stairs_weight"],
  ["Temperature", "temperature"],
] as const;

/** One header and one data row; retain full numeric precision for spreadsheets. */
export function meanMetricsDelimited(data: MeanMetrics, filters: URLSearchParams, format: "csv" | "tsv"): string {
  const delimiter = format === "csv" ? "," : "\t";
  const condition = filterFields.map(([label, key]) => `${label}=${filters.get(key) || "All"}`).join("; ");
  const rows = [
    ["Filters", "Runs", "Finished", "Unfinished", ...meanMetricFields.map(([label]) => label)],
    [condition, data.runs, data.runs - data.unfinished, data.unfinished,
      ...meanMetricFields.map(([, key]) => data.means[key] ?? "")],
  ];
  const cell = (value: string | number): string => {
    const text = String(value);
    return text.includes(delimiter) || /["\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
  };
  return rows.map(row => row.map(cell).join(delimiter)).join("\r\n") + "\r\n";
}
