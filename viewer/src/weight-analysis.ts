export interface WeightPoint { weight: number; n: number; mean_score: number; unfinished: number }
export interface WeightAxis { n: number; pearson_r: number | null; undefined_reason: string | null; values: WeightPoint[] }
export interface WeightStrategy { strategy_id: string; n: number; unfinished: number; axes: Record<string, WeightAxis> }
export interface WeightCohort {
  id: string;
  conditions: { scenario_seed: number | null; scenario_id: string; simulation_version: number; schema_version: number; code_revision: string; max_turns: number | null; other_policy: Record<string, unknown> };
  strategies: WeightStrategy[];
}
export interface WeightAnalysis { cohorts: WeightCohort[]; excluded_runs: number }
const axes = [["enemy_weight", "Enemy"], ["item_weight", "Treasure"], ["stairs_weight", "Stairs"]] as const;
const escape = (value: unknown): string => String(value).replace(/[&<>"']/g, char => ({"&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;"})[char]!);
const number = (value: number): string => Number(value.toFixed(2)).toString();
const reasonLabels: Record<string, string> = { fewer_than_two_runs: "At least two Runs are needed", constant_weight: "Weight has no variation", constant_score: "Score has no variation" };

function chart(points: WeightPoint[], name: string, min: number, max: number): string {
  if (!points.length) return '<p>No observations.</p>';
  const xMin = points[0].weight, xMax = points.at(-1)!.weight;
  const x = (weight: number) => xMax === xMin ? 210 : 50 + 320 * (weight - xMin) / (xMax - xMin);
  const y = (score: number) => 170 - 145 * (score - min) / (max - min);
  const title = `${name} weight versus mean Score`;
  const ticks = [min, (min + max) / 2, max];
  return `<svg class="weight-chart" viewBox="0 0 400 215" role="img" aria-label="${escape(title)}"><title>${escape(title)}. Exact values and counts are in the table below.</title>
    ${ticks.map(tick => `<line x1="50" y1="${y(tick)}" x2="370" y2="${y(tick)}" class="weight-grid"/><text x="43" y="${y(tick) + 4}" text-anchor="end">${number(tick)}</text>`).join("")}
    <polyline points="${points.map(point => `${x(point.weight)},${y(point.mean_score)}`).join(" ")}"/>
    ${points.map((point, index) => `<circle cx="${x(point.weight)}" cy="${y(point.mean_score)}" r="4"><title>weight ${point.weight}: mean Score ${number(point.mean_score)}, n=${point.n}, unfinished=${point.unfinished}</title></circle>${index % Math.max(1, Math.ceil(points.length / 8)) === 0 || index === points.length - 1 ? `<text x="${x(point.weight)}" y="190" text-anchor="middle">${point.weight}</text>` : ""}`).join("")}
    <text x="210" y="210" text-anchor="middle">${name} weight</text><text x="50" y="13">Mean Score</text></svg>`;
}

export function cohortLabel(cohort: WeightCohort): string {
  const c = cohort.conditions;
  return `seed ${c.scenario_seed ?? "unknown"} · sim ${c.simulation_version}/schema ${c.schema_version} · ${c.code_revision || "revision unknown"} · max turns ${c.max_turns ?? "unknown"} · ${JSON.stringify(c.other_policy)} · ${c.scenario_id}`;
}

export function analysisMarkup(cohort: WeightCohort): string {
  const points = cohort.strategies.flatMap(strategy => axes.flatMap(([key]) => strategy.axes[key].values));
  const min = Math.min(0, ...points.map(point => point.mean_score));
  const max = Math.max(1, ...points.map(point => point.mean_score));
  const unknownLimit = cohort.conditions.max_turns === null ? '<p class="weight-warning">Max turns were not recorded for these Runs. They may include different Turn limits; compare with care. New API Runs record this setting.</p>' : "";
  return unknownLimit + cohort.strategies.map(strategy => `<article class="weight-strategy"><h3>${escape(strategy.strategy_id.replace(/_v1$/, ""))}</h3><p class="panel-note">${strategy.n} Runs · ${strategy.unfinished} unfinished included · last saved Score per Run</p><div class="weight-axes">${axes.map(([key, name]) => {
    const axis = strategy.axes[key];
    return `<section class="weight-axis"><h4>${name}</h4><p class="weight-correlation">Pearson r <strong>${axis.pearson_r === null ? "—" : axis.pearson_r.toFixed(3)}</strong> <span>n=${axis.n}</span></p>${axis.undefined_reason ? `<p class="panel-note">${escape(reasonLabels[axis.undefined_reason] ?? axis.undefined_reason)}</p>` : ""}${chart(axis.values, name, min, max)}<details><summary>Values and counts</summary><div class="table-scroll"><table><thead><tr><th>Weight</th><th>Mean Score</th><th>n</th><th>Unfinished</th></tr></thead><tbody>${axis.values.map(point => `<tr><td>${point.weight}</td><td>${number(point.mean_score)}</td><td>${point.n}</td><td>${point.unfinished}</td></tr>`).join("")}</tbody></table></div></details></section>`;
  }).join("")}</div></article>`).join("");
}

export function updateWeightAnalysis(data: WeightAnalysis, root: HTMLElement): void {
  const select = root.querySelector<HTMLSelectElement>("#weight-cohort")!;
  const previous = select.value;
  const options = data.cohorts.map(cohort => `<option value="${cohort.id}">${escape(cohortLabel(cohort))}</option>`).join("");
  if (select.innerHTML !== options) select.innerHTML = options;
  if (data.cohorts.some(cohort => cohort.id === previous)) select.value = previous;
  const cohort = data.cohorts.find(candidate => candidate.id === select.value);
  const content = root.querySelector<HTMLElement>("#weight-analysis-content")!;
  const markup = cohort ? analysisMarkup(cohort) : '<p>No Runs with all three recorded weights match these filters. Run AutoRun or import compatible logs.</p>';
  if (content.innerHTML !== markup) content.innerHTML = markup;
  root.querySelector<HTMLElement>("#weight-analysis-status")!.textContent = `${data.cohorts.length} condition groups · ${data.excluded_runs} Runs excluded for missing/invalid weights or Score`;
  select.disabled = !cohort;
}
