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

/** One data row with an optional header; retain full numeric precision. */
export function meanMetricsDelimited(data: MeanMetrics, filters: URLSearchParams, format: "csv" | "tsv", includeHeader = true): string {
  const delimiter = format === "csv" ? "," : "\t";
  const conditions = filterFields.map(([, key]) => filters.get(key) || "All");
  const rows = [
    [...filterFields.map(([label]) => label), "Runs", "Finished", "Unfinished", ...meanMetricFields.map(([label]) => label)],
    [...conditions, data.runs, data.runs - data.unfinished, data.unfinished,
      ...meanMetricFields.map(([, key]) => data.means[key] ?? "")],
  ];
  const cell = (value: string | number): string => {
    const text = String(value);
    return text.includes(delimiter) || /["\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
  };
  return (includeHeader ? rows : rows.slice(1)).map(row => row.map(cell).join(delimiter)).join("\r\n") + "\r\n";
}
