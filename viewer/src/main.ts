import "./style.css";
import { api, type StoredRun, type RunGroup } from "./catalog.ts";
import sampleLog from "../../examples/sample-run-v1.jsonl?raw";
import {
  decisionDetails,
  describeEvent,
  eventCategory,
  parseJsonLines,
  summarizeRun,
  type EnemySnapshot,
  type ParsedLog,
  type RunEvent,
  type Vector2i,
} from "./log.ts";

const stairsIcon = `<rect x=".1" y=".1" width=".8" height=".8" rx=".08" /><path d="M .225 .3 H .4 V .475 H .575 V .65 H .75 M .225 .775 H .75" />`;

type FilterName = "all" | "decision" | "combat" | "action" | "floor";

interface ViewerState {
  parsed: ParsedLog | null;
  runId: string;
  selectedSequence: number | null;
  selectedDepth: number;
  filter: FilterName;
  query: string;
  sourceName: string;
  error: string;
}

const state: ViewerState = {
  parsed: null,
  runId: "",
  selectedSequence: null,
  selectedDepth: 1,
  filter: "all",
  query: "",
  sourceName: "",
  error: "",
};

const app = document.querySelector<HTMLDivElement>("#app");
if (!app) throw new Error("App root was not found.");

app.innerHTML = `
  <header class="topbar">
    <div class="brand">
      <span class="brand-mark" aria-hidden="true">A</span>
      <div>
        <p class="eyebrow">AFTER-ACTION ANALYSIS</p>
        <h1>AnaRogue <span>Run Viewer</span></h1>
      </div>
    </div>
    <div class="file-actions">
      <button class="button button-ghost" id="sample-button" type="button">Import sample</button>
      <label class="button button-primary" for="file-input">Import JSONL</label>
      <input id="file-input" type="file" accept=".jsonl,.json,text/plain,application/json" />
    </div>
  </header>
  <main>
    <section class="panel catalogue" aria-label="Stored Runs">
      <div class="panel-heading">
        <div><p class="eyebrow">RUN DATABASE</p><h2>Stored Runs</h2></div>
        <span id="catalog-status" role="status">Connecting…</span>
      </div>
      <div class="catalog-controls">
        <label class="select-label">Strategy<select id="catalog-strategy"><option value="">All strategies</option><option value="aggressive_v1">Aggressive</option><option value="cautious_v1">Cautious</option></select></label>
        <label class="select-label">Result<select id="catalog-result"><option value="">All results</option><option value="cleared">Cleared</option><option value="defeated">Defeated</option><option value="unfinished">Unfinished</option><option value="restarted">Restarted</option></select></label>
        <label class="select-label">Seed<input id="catalog-seed" type="number" min="0" placeholder="All seeds" /></label>
        <label class="select-label catalog-run-label">Run<select id="catalog-run"><option value="">No Runs yet</option></select></label>
      </div>
      <div class="catalog-pagination"><button id="catalog-previous" class="button button-ghost" type="button">Previous page</button><span id="catalog-page"></span><button id="catalog-next" class="button button-ghost" type="button">Next page</button></div>
      <div id="catalog-stats" class="catalog-stats"></div>
    </section>
    <section class="drop-zone" id="drop-zone" aria-label="JSONL file drop zone">
      <div class="drop-icon" aria-hidden="true">↧</div>
      <p class="eyebrow">RUN CATALOGUE</p>
      <h2>Select a stored Run to inspect its decisions.</h2>
      <p>Runs accumulate in SQLite. Import existing JSONL or watch your simulation logs.</p>
      <div class="drop-actions">
        <label class="button button-primary" for="file-input">Import a file</label>
        <button class="button button-ghost" id="empty-sample-button" type="button">Import sample data</button>
      </div>
      <p class="privacy-note">Imported logs are saved by your local Run API. The list updates automatically.</p>
    </section>
    <section class="viewer" id="viewer" hidden>
      <div class="run-bar">
        <div>
          <p class="eyebrow">ACTIVE RUN</p>
          <div class="run-title-row">
            <h2 id="run-title"></h2>
            <span class="status-pill" id="run-status"></span>
          </div>
          <p class="source-label" id="source-label"></p>
        </div>
        <label class="select-label" id="run-select-label">
          Run
          <select id="run-select"></select>
        </label>
      </div>
      <div class="warning" id="warning" hidden></div>
      <section class="comparison-panel" id="comparison-panel" hidden></section>
      <section class="metrics" id="metrics" aria-label="Run summary"></section>
      <div class="analysis-grid">
        <section class="panel hp-panel">
          <div class="panel-heading">
            <div>
              <p class="eyebrow">SURVIVABILITY</p>
              <h3>HP over time</h3>
            </div>
            <p class="panel-note">damage and recovery by event</p>
          </div>
          <div id="hp-chart"></div>
        </section>
        <section class="panel map-panel">
          <div class="panel-heading">
            <div>
              <p class="eyebrow">MOVEMENT TRACE</p>
              <h3>Route by depth</h3>
            </div>
            <label class="select-label compact">
              Depth
              <select id="depth-select"></select>
            </label>
          </div>
          <div id="route-map"></div>
          <div class="map-legend">
            <span><i class="legend-player"></i>Player</span>
            <span><i class="legend-enemy"></i>Melee</span>
            <span><i class="legend-archer"></i>Archer</span>
            <span><i class="legend-brute"></i>Brute / marked strike</span>
            <span style="color:#de8fe8">● Health potion</span>
            <span><svg class="map-stairs legend-stairs" viewBox="0 0 1 1" aria-hidden="true">${stairsIcon}</svg>Stairs</span>
          </div>
        </section>
      </div>
      <section class="event-workbench">
        <div class="timeline-column">
          <div class="timeline-tools">
            <div>
              <p class="eyebrow">EVENT STREAM</p>
              <h3>What happened, and why</h3>
            </div>
            <input id="event-search" type="search" placeholder="Search rule, reason, result…" />
          </div>
          <div class="filters" id="filters" aria-label="Event filters">
            <button class="filter active" data-filter="all">All</button>
            <button class="filter" data-filter="decision">Decisions</button>
            <button class="filter" data-filter="combat">Combat</button>
            <button class="filter" data-filter="action">Actions</button>
            <button class="filter" data-filter="floor">Run</button>
          </div>
          <div class="timeline" id="timeline"></div>
        </div>
        <aside class="detail-panel" id="detail-panel"></aside>
      </section>
    </section>
    <div class="toast" id="toast" role="alert" hidden></div>
  </main>
`;

const getElement = <T extends HTMLElement>(selector: string): T => {
  const element = document.querySelector<T>(selector);
  if (!element) throw new Error(`Missing element: ${selector}`);
  return element;
};

const escapeHtml = (value: unknown): string =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

const eventsForRun = (): RunEvent[] =>
  state.parsed?.runs.get(state.runId) ?? [];

const runStart = (events: RunEvent[]): RunEvent | undefined =>
  events.find((event) => event.event === "run_start");

const strategyForRun = (events: RunEvent[]): string =>
  events.find((event) => event.strategy_id)?.strategy_id ??
  String(runStart(events)?.details.strategy_id ?? "unknown strategy");

const scenarioForRun = (events: RunEvent[]): string =>
  events.find((event) => event.scenario_id)?.scenario_id ??
  String(runStart(events)?.details.scenario_id ?? "");

const simulationForRun = (events: RunEvent[]): number =>
  Number(runStart(events)?.details.simulation_version ?? events[0]?.schema_version ?? 1);

const strategyLabel = (strategy: string): string => {
  if (strategy.startsWith("aggressive")) return "Aggressive";
  if (strategy.startsWith("cautious")) return "Cautious";
  return strategy;
};

function loadSource(source: string, sourceName: string): void {
  activeStoredRun = null;
  try {
    const parsed = parseJsonLines(source);
    const runIds = [...parsed.runs.keys()];
    state.parsed = parsed;
    state.runId = runIds.at(-1) ?? "";
    state.sourceName = sourceName;
    state.error = "";
    state.filter = "all";
    state.query = "";
    selectInitialEvent();
    render();
  } catch (error) {
    state.error = error instanceof Error ? error.message : "Could not read this log.";
    showToast(state.error);
  }
}

function selectInitialEvent(): void {
  const events = eventsForRun();
  const firstDecision = events.find((event) => event.event === "decision");
  state.selectedSequence = firstDecision?.sequence ?? events.at(-1)?.sequence ?? null;
  state.selectedDepth = firstDecision?.depth ?? events.at(-1)?.depth ?? 1;
}

function showToast(message: string): void {
  const toast = getElement<HTMLDivElement>("#toast");
  toast.textContent = message;
  toast.hidden = false;
  window.setTimeout(() => {
    toast.hidden = true;
  }, 5000);
}

function render(): void {
  const viewer = getElement<HTMLElement>("#viewer");
  const dropZone = getElement<HTMLElement>("#drop-zone");
  const hasRun = Boolean(state.parsed && state.runId);
  viewer.hidden = !hasRun;
  dropZone.hidden = hasRun;
  if (!hasRun) return;

  const events = eventsForRun();
  const summary = summarizeRun(events);
  const selected = events.find((event) => event.sequence === state.selectedSequence);
  const strategy = strategyForRun(events);
  const scenario = scenarioForRun(events);

  getElement("#run-title").textContent = state.runId;
  getElement("#source-label").textContent =
    `${state.sourceName} · ${events.length} events · ${strategyLabel(strategy)}${scenario ? ` · ${scenario}` : ""}`;
  const status = getElement("#run-status");
  status.textContent = summary.result;
  status.className = `status-pill status-${summary.result}`;

  renderRunSelect();
  renderWarnings();
  if (activeStoredRun) renderStoredComparison();
  else renderComparison(events);
  renderMetrics(events);
  renderHpChart(events);
  renderDepthSelect(events);
  renderRouteMap(events, selected);
  renderTimeline(events);
  renderDetail(selected);
}

function renderRunSelect(): void {
  const select = getElement<HTMLSelectElement>("#run-select");
  const label = getElement<HTMLElement>("#run-select-label");
  const runIds = [...(state.parsed?.runs.keys() ?? [])];
  label.hidden = Boolean(activeStoredRun) || runIds.length < 2;
  select.innerHTML = runIds
    .map(
      (id) => {
        const events = state.parsed?.runs.get(id) ?? [];
        const label = `${strategyLabel(strategyForRun(events))} · ${id}`;
        return `<option value="${escapeHtml(id)}" ${id === state.runId ? "selected" : ""}>${escapeHtml(label)}</option>`;
      },
    )
    .join("");
}

function renderWarnings(): void {
  const warning = getElement<HTMLDivElement>("#warning");
  const warnings = state.parsed?.warnings ?? [];
  warning.hidden = warnings.length === 0;
  warning.textContent = warnings.join(" ");
}

function renderComparison(events: RunEvent[]): void {
  const panel = getElement<HTMLElement>("#comparison-panel");
  const scenario = scenarioForRun(events);
  const peers = [...(state.parsed?.runs.entries() ?? [])].filter(
    ([, candidate]) => scenario && scenarioForRun(candidate) === scenario
      && simulationForRun(candidate) === simulationForRun(events),
  );
  const strategies = new Set(peers.map(([, candidate]) => strategyForRun(candidate)));
  if (!scenario || peers.length < 2 || strategies.size < 2) {
    panel.hidden = true;
    panel.innerHTML = "";
    return;
  }

  panel.hidden = false;
  panel.innerHTML = `
    <div class="comparison-heading">
      <div>
        <p class="eyebrow">SAME-SEED COMPARISON</p>
        <h3>Aggressive vs. Cautious</h3>
      </div>
      <code>${escapeHtml(scenario)}</code>
    </div>
    <div class="comparison-cards">
      ${peers
        .map(([runId, candidate]) => {
          const summary = summarizeRun(candidate);
          const strategy = strategyForRun(candidate);
          return `
            <button class="comparison-card ${runId === state.runId ? "active" : ""}" data-compare-run="${escapeHtml(runId)}" type="button">
              <span class="comparison-name">${escapeHtml(strategyLabel(strategy))}</span>
              <span class="comparison-strategy">${escapeHtml(strategy)}</span>
              <span class="comparison-stat"><b>Lv ${summary.level}</b> · XP ${summary.xp}/${summary.level * 8}</span>
              <span class="comparison-stat"><b>${summary.score}</b> score</span>
              <span class="comparison-stat"><b>${summary.maxDepth}</b> depth</span>
              <span class="comparison-stat"><b>${summary.damageTaken}</b> damage</span>
              <span class="comparison-stat"><b>${summary.kills}</b> kills</span>
              <span class="comparison-stat"><b>${summary.gold}</b> gold</span>
              <span class="comparison-stat"><b>${summary.turns}</b> turns</span>
            </button>`;
        })
        .join("")}
    </div>`;

  panel.querySelectorAll<HTMLButtonElement>("[data-compare-run]").forEach((button) => {
    button.addEventListener("click", () => {
      state.runId = button.dataset.compareRun ?? state.runId;
      selectInitialEvent();
      render();
    });
  });
}

function renderMetrics(events: RunEvent[]): void {
  const summary = summarizeRun(events);
  const metrics = [
    ["Score", summary.score, "latest total"],
    ["Level", summary.level, `XP ${summary.xp}/${summary.level * 8}`],
    ["Turns", summary.turns, "elapsed actions"],
    ["Depth", summary.maxDepth, "deepest floor"],
    ["Kills", summary.kills, "enemies removed"],
    ["Damage", summary.damageTaken, "HP lost"],
    ["Gold", summary.gold, "final total"],
    ["Decisions", summary.decisions, "rules evaluated"],
    ["Potions found", summary.potionsPickedUp, "picked up"],
    ["Potions used", summary.potionsUsed, "consumed"],
    ["Healing", summary.hpHealed, "HP from potions"],
  ];
  getElement("#metrics").innerHTML = metrics
    .map(
      ([label, value, note]) => `
        <article class="metric-card">
          <p>${escapeHtml(label)}</p>
          <strong>${escapeHtml(value)}</strong>
          <span>${escapeHtml(note)}</span>
        </article>`,
    )
    .join("");
}

function renderHpChart(events: RunEvent[]): void {
  const values = events
    .filter((event) => event.player_state)
    .map((event) => ({
      sequence: event.sequence,
      turn: event.turn,
      hp: event.player_state?.hp ?? event.hp,
      maxHp: event.player_state?.max_hp ?? event.hp,
      event: event.event,
    }));
  const container = getElement("#hp-chart");
  if (values.length === 0) {
    container.innerHTML = `<p class="empty-note">No player-state snapshots available.</p>`;
    return;
  }

  const width = 720;
  const height = 230;
  const pad = { left: 42, right: 18, top: 18, bottom: 32 };
  const plotWidth = width - pad.left - pad.right;
  const plotHeight = height - pad.top - pad.bottom;
  const minSequence = values[0].sequence;
  const maxSequence = values.at(-1)?.sequence ?? minSequence + 1;
  const span = Math.max(maxSequence - minSequence, 1);
  const maxHp = Math.max(...values.map((value) => value.maxHp), 1);
  const point = (sequence: number, hp: number): [number, number] => [
    pad.left + ((sequence - minSequence) / span) * plotWidth,
    pad.top + (1 - hp / maxHp) * plotHeight,
  ];
  const points = values.map((value) => point(value.sequence, value.hp));
  const line = points.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const area = [
    `${points[0][0]},${pad.top + plotHeight}`,
    ...points.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`),
    `${points.at(-1)?.[0] ?? pad.left},${pad.top + plotHeight}`,
  ].join(" ");
  const damagePoints = values
    .map((value, index) => ({ value, index }))
    .filter(({ value, index }) => index > 0 && value.hp < values[index - 1].hp)
    .map(({ value }) => {
      const [x, y] = point(value.sequence, value.hp);
      return `<circle class="damage-point" cx="${x}" cy="${y}" r="4"><title>Turn ${value.turn}: HP ${value.hp}</title></circle>`;
    })
    .join("");

  container.innerHTML = `
    <svg class="chart" viewBox="0 0 ${width} ${height}" role="img" aria-label="HP over event sequence">
      <defs>
        <linearGradient id="hp-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#d6e86a" stop-opacity=".32" />
          <stop offset="100%" stop-color="#d6e86a" stop-opacity="0" />
        </linearGradient>
      </defs>
      <line class="grid-line" x1="${pad.left}" y1="${pad.top}" x2="${pad.left + plotWidth}" y2="${pad.top}" />
      <line class="grid-line" x1="${pad.left}" y1="${pad.top + plotHeight / 2}" x2="${pad.left + plotWidth}" y2="${pad.top + plotHeight / 2}" />
      <line class="axis-line" x1="${pad.left}" y1="${pad.top + plotHeight}" x2="${pad.left + plotWidth}" y2="${pad.top + plotHeight}" />
      <text class="axis-text" x="8" y="${pad.top + 5}">${maxHp}</text>
      <text class="axis-text" x="18" y="${pad.top + plotHeight + 5}">0</text>
      <text class="axis-text" x="${pad.left}" y="${height - 7}">event ${minSequence}</text>
      <text class="axis-text axis-end" x="${pad.left + plotWidth}" y="${height - 7}">event ${maxSequence}</text>
      <polygon points="${area}" fill="url(#hp-fill)" />
      <polyline class="hp-line" points="${line}" />
      ${damagePoints}
    </svg>`;
}

function renderDepthSelect(events: RunEvent[]): void {
  const select = getElement<HTMLSelectElement>("#depth-select");
  const depths = [...new Set(events.map((event) => event.depth))].sort((a, b) => a - b);
  if (!depths.includes(state.selectedDepth)) state.selectedDepth = depths[0] ?? 1;
  select.innerHTML = depths
    .map(
      (depth) =>
        `<option value="${depth}" ${depth === state.selectedDepth ? "selected" : ""}>${depth}</option>`,
    )
    .join("");
}

function asVector(value: unknown): Vector2i | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<Vector2i>;
  return typeof candidate.x === "number" && typeof candidate.y === "number"
    ? { x: candidate.x, y: candidate.y }
    : null;
}

function renderRouteMap(events: RunEvent[], selected?: RunEvent): void {
	const depthEvents = events.filter((event) => event.depth === state.selectedDepth);
	const floorStart = depthEvents.find((event) => event.event === "floor_start");
	const floorEvents = floorStart
		? depthEvents.filter((event) => event.sequence >= floorStart.sequence)
		: depthEvents;
  const mapSize = (floorStart?.details.map_size ?? {}) as Record<string, unknown>;
  const width = Math.max(Number(mapSize.width) || 24, 1);
  const height = Math.max(Number(mapSize.height) || 18, 1);
  const positions = floorEvents
    .map((event) => event.player_state?.pos)
    .filter((pos): pos is Vector2i => Boolean(pos));
  const stairs = asVector(floorStart?.details.stairs_pos);
  let enemies = Array.isArray(floorStart?.details.enemies)
    ? (floorStart.details.enemies as EnemySnapshot[])
    : [];
  const selectedPos =
    selected?.depth === state.selectedDepth ? selected.player_state?.pos : undefined;
  const cutoff = selected?.depth === state.selectedDepth ? selected.sequence : Infinity;
  let items = (floorStart?.details.items ?? []) as { id: string; type: string; weapon_kind?: string | null; pos: Vector2i }[];
  for (const event of floorEvents) {
    if (event.sequence > cutoff) break;
    const observation = decisionDetails(event)?.observation;
    if (observation?.items) items = observation.items;
    if (observation?.enemies) enemies = observation.enemies;
    if (event.event === "battle_result") {
      const d = event.details;
      if (d.result === "enemy_defeated") enemies = enemies.filter(enemy => enemy.id !== d.enemy_id);
      else enemies = enemies.map(enemy => enemy.id !== d.enemy_id ? enemy : {
        ...enemy,
        pos: (d.enemy_pos as Vector2i | undefined) ?? enemy.pos,
        hp: (d.enemy_hp_after as number | undefined) ?? enemy.hp,
        windup_target: "windup_target" in d ? d.windup_target as Vector2i | null : enemy.windup_target,
      });
    }
    if (event.event === "item_result" && event.details.result === "item_equipped") {
      items = event.details.items as typeof items;
    }
    if (event.event === "item_result" && event.details.result === "item_picked_up") {
      const item = event.details.item as { id: string };
      items = items.filter((candidate) => candidate.id !== item.id);
    }
  }
  const itemMarks = items.map((item) => `<g fill="#de8fe8"><circle cx="${item.pos.x + .5}" cy="${item.pos.y + .5}" r=".28"/><text x="${item.pos.x + .5}" y="${item.pos.y + .68}" text-anchor="middle" font-size=".45" fill="#17212b">${item.type === "weapon" ? item.weapon_kind === "bow" ? "B" : "W" : item.type === "armor" ? "D" : "+"}</text><title>${escapeHtml(item.id)} · ${escapeHtml(item.type)}</title></g>`).join("");
  const route = positions.map((pos) => `${pos.x + 0.5},${pos.y + 0.5}`).join(" ");
  const enemyMarks = enemies
    .map(
      (enemy) => `
        <g class="map-enemy ${enemy.type === "archer" ? "archer" : enemy.type === "brute" ? "brute" : ""}">
          <circle cx="${enemy.pos.x + 0.5}" cy="${enemy.pos.y + 0.5}" r=".38" />
          <title>${escapeHtml(enemy.id)} · ${escapeHtml(enemy.type)}</title>
          ${enemy.windup_target ? `<rect class="windup-mark" x="${enemy.windup_target.x}" y="${enemy.windup_target.y}" width="1" height="1"><title>Brute strike next enemy phase</title></rect>` : ""}
        </g>`,
    )
    .join("");

  getElement("#route-map").innerHTML = `
    <svg class="route-map" viewBox="0 0 ${width} ${height}" role="img" aria-label="Player movement on depth ${state.selectedDepth}">
      <defs>
        <pattern id="map-grid" width="1" height="1" patternUnits="userSpaceOnUse">
          <path d="M 1 0 L 0 0 0 1" fill="none" stroke="#32372f" stroke-width=".035" />
        </pattern>
      </defs>
      <rect width="${width}" height="${height}" fill="#171b17" />
      <rect width="${width}" height="${height}" fill="url(#map-grid)" />
      ${route ? `<polyline class="route-line" points="${route}" />` : ""}
      ${stairs ? `<g class="map-stairs" transform="translate(${stairs.x} ${stairs.y})">${stairsIcon}<title>Stairs · descend to next floor</title></g>` : ""}
      ${itemMarks}
      ${enemyMarks}
      ${positions[0] ? `<circle class="route-start" cx="${positions[0].x + 0.5}" cy="${positions[0].y + 0.5}" r=".25"><title>Start</title></circle>` : ""}
      ${selectedPos ? `<circle class="route-selected" cx="${selectedPos.x + 0.5}" cy="${selectedPos.y + 0.5}" r=".44"><title>Selected event</title></circle>` : ""}
    </svg>`;
}

function filteredEvents(events: RunEvent[]): RunEvent[] {
  const query = state.query.trim().toLowerCase();
  return events.filter((event) => {
    if (state.filter !== "all" && eventCategory(event) !== state.filter) return false;
    if (!query) return true;
    return JSON.stringify(event).toLowerCase().includes(query);
  });
}

function renderTimeline(events: RunEvent[]): void {
	document.querySelectorAll<HTMLButtonElement>(".filter").forEach((button) => {
		button.classList.toggle("active", button.dataset.filter === state.filter);
	});
	getElement<HTMLInputElement>("#event-search").value = state.query;
	const visibleEvents = filteredEvents(events);
  const timeline = getElement("#timeline");
  if (visibleEvents.length === 0) {
    timeline.innerHTML = `<p class="empty-note timeline-empty">No events match this filter.</p>`;
    return;
  }
  timeline.innerHTML = visibleEvents
    .map((event) => {
      const description = describeEvent(event);
      const selected = event.sequence === state.selectedSequence;
      return `
        <button class="event-row ${selected ? "selected" : ""}" data-sequence="${event.sequence}" type="button">
          <span class="event-index">${String(event.sequence).padStart(3, "0")}</span>
          <span class="event-marker category-${eventCategory(event)}"></span>
          <span class="event-content">
            <span class="event-meta">TURN ${event.turn} · DEPTH ${event.depth} · ${escapeHtml(event.event)}</span>
            <strong>${escapeHtml(description.title)}</strong>
            <span>${escapeHtml(description.body)}</span>
          </span>
          <span class="event-hp">${event.player_state?.hp ?? event.hp} HP</span>
        </button>`;
    })
    .join("");

  timeline.querySelectorAll<HTMLButtonElement>("[data-sequence]").forEach((button) => {
    button.addEventListener("click", () => {
      state.selectedSequence = Number(button.dataset.sequence);
      const selected = events.find((event) => event.sequence === state.selectedSequence);
      if (selected) state.selectedDepth = selected.depth;
      render();
      document
        .querySelector(".detail-panel")
        ?.scrollIntoView({ behavior: "smooth", block: "nearest" });
    });
  });
}

function renderDetail(event?: RunEvent): void {
  const detail = getElement("#detail-panel");
  if (!event) {
    detail.innerHTML = `<div class="detail-empty"><span>◎</span><p>Select an event to inspect it.</p></div>`;
    return;
  }
  const description = describeEvent(event);
  const decision = decisionDetails(event);
  const comparison = decision?.observation.progression;
  const rejectionLabels = { hp_reserve: "HP reserve too low", mobile_target: "Retreating Archer", no_level_up: "No level-up", out_of_reach: "Beyond route limit / blocked", "": "Eligible" };
  const growthMarkup = comparison ? `
    <div class="growth-comparison">
      <h4>Growth vs. descent · ${comparison.selected === "combat" ? "Combat selected" : "Stairs selected"}${comparison.target_retained ? " · Current target retained" : ""}</h4>
      <p>Stairs: score <b>${comparison.stairs_score}</b> · ${comparison.stairs_steps} shortest-route steps · up to ${comparison.stairs_healing} HP recovered</p>
      <div class="growth-table-scroll"><table>
        <thead><tr><th>Enemy</th><th>Approach</th><th>Attacks</th><th>XP</th><th>Levels</th><th>Est. damage</th><th>Revisit penalty</th><th>Score</th><th>Assessment</th></tr></thead>
        <tbody>${comparison.candidates.map((candidate) => `<tr>
          <td>${escapeHtml(candidate.enemy_id)}</td><td>${candidate.steps ?? "—"}</td><td>${candidate.attack_turns ?? "—"}</td>
          <td>${candidate.xp_gain ?? "—"}</td><td>${candidate.levels_gained ?? "—"}</td><td>${candidate.estimated_damage ?? "—"}</td>
          <td>${candidate.revisit_penalty ?? "—"}</td><td>${candidate.score ?? "—"}</td><td>${candidate.enemy_id === comparison.selected_enemy_id ? "Selected" : !candidate.rejection && (candidate.score ?? 0) <= comparison.stairs_score ? "Stairs favored" : escapeHtml(rejectionLabels[candidate.rejection] ?? candidate.rejection)}</td>
        </tr>`).join("") || '<tr><td colspan="9">No enemies remain.</td></tr>'}</tbody>
      </table></div>
      <p class="detail-description">Damage uses current enemy positions and equipment. Enemy movement is not predicted; the scores are policy estimates.</p>
    </div>` : "";
  const goal = decision?.observation.goal_selection;
  const goalMarkup = goal ? `<div class="growth-comparison">
    <h4>Goal: ${escapeHtml(goal.selected_kind)} · ${escapeHtml(goal.selected_id)}${goal.target_retained ? " · Retained" : " · Drawn"}</h4>
    <p>${goal.target_retained ? "Target retained; no new draw. Redraw weights shown below." : `Draw ${goal.draw} · policy RNG ${goal.rng_before} → ${goal.rng_after}`}</p>
    <div class="growth-table-scroll"><table><thead><tr><th>Category</th><th>Target</th><th>Benefit</th><th>Est. damage</th><th>Risk</th><th>Time</th><th>Revisits</th><th>Utility</th><th>Draw chance</th></tr></thead>
    <tbody>${goal.candidates.map(c => {
      const entry = goal.distribution.find(d => d.kind === c.kind && d.id === c.id);
      return `<tr><td>${escapeHtml(c.kind)}</td><td>${escapeHtml(c.id)}</td><td>${c.benefit}</td><td>${c.estimated_damage}</td><td>${c.risk}</td><td>${c.turns}</td><td>${c.revisit_penalty}</td><td>${c.utility}</td><td>${entry ? `${(100 * entry.mass / entry.total_mass).toFixed(1)}%` : c.eligible ? "Other target" : escapeHtml(c.rejection)}</td></tr>`;
    }).join("")}</tbody></table></div>
    <p>Damage is an estimate using current positions. It does not predict all enemy movement.</p></div>` : "";
  const decisionMarkup = decision
    ? `
      <div class="decision-rule">
        <p class="eyebrow">MATCHED RULE</p>
        <code>${escapeHtml(decision.rule_id)}</code>
      </div>
      <blockquote>${escapeHtml(decision.reason)}</blockquote>
      <dl class="observation-grid">
        <div><dt>Strategy</dt><dd>${escapeHtml(decision.strategy_id)}</dd></div>
        <div><dt>Action</dt><dd>${escapeHtml(decision.action.type)}</dd></div>
        <div><dt>HP</dt><dd>${decision.observation.hp}/${decision.observation.max_hp}</dd></div>
        <div><dt>Potions</dt><dd>${decision.observation.inventory?.health_potion ?? 0}/3</dd></div>
        <div><dt>Enemies</dt><dd>${decision.observation.enemy_count}</dd></div>
        <div><dt>Danger here</dt><dd>${decision.observation.current_danger ?? "—"}</dd></div>
        <div><dt>Next danger</dt><dd>${decision.observation.selected_step_danger ?? "—"}</dd></div>
        <div><dt>Tile visits</dt><dd>${decision.observation.current_tile_visits ?? "—"}</dd></div>
        <div><dt>Revisit cost</dt><dd>${decision.observation.selected_step_revisit_cost ?? 0}</dd></div>
      </dl>
      <div class="action-vector">
        direction <code>(${decision.action.direction.x}, ${decision.action.direction.y})</code>
        <span>→</span> action turn <code>${decision.action_turn}</code>
      </div>`
    : `<p class="detail-description">${escapeHtml(description.body)}</p>`;

  detail.innerHTML = `
    <div class="detail-header">
      <div>
        <p class="eyebrow">EVENT ${event.sequence}</p>
        <h3>${escapeHtml(description.title)}</h3>
      </div>
      <span class="event-chip category-${eventCategory(event)}">${escapeHtml(event.event)}</span>
    </div>
    ${decisionMarkup}
    ${growthMarkup}
    ${goalMarkup}
    <div class="state-strip">
      <span>Turn <b>${event.turn}</b></span>
      <span>Depth <b>${event.depth}</b></span>
      <span>Lv <b>${event.player_state?.level ?? 1}</b></span>
      <span>XP <b>${event.player_state?.xp ?? 0}/${(event.player_state?.level ?? 1) * 8}</b></span>
      <span>HP <b>${event.player_state?.hp ?? event.hp}</b></span>
      <span>ATK <b>${event.player_state?.attack ?? 0}</b> (${event.player_state?.base_attack ?? event.player_state?.attack ?? 0} + ${event.player_state?.attack_bonus ?? 0})${event.player_state?.weapon_kind === "bow" ? " / 2, rounded down" : ""}</span>
      <span>Weapon type <b>${event.player_state?.weapon_kind ?? "melee"}</b> · range <b>${event.player_state?.attack_range ?? 1}</b></span>
      <span>DEF <b>${event.player_state?.defense ?? 0}</b> (${event.player_state?.base_defense ?? 0} + ${event.player_state?.defense_bonus ?? 0})</span>
      <span>Weapon <b>${escapeHtml(event.player_state?.equipment?.weapon?.id ?? "None")}</b></span>
      <span>Armor <b>${escapeHtml(event.player_state?.equipment?.armor?.id ?? "None")}</b></span>
      <span>Potions <b>${event.player_state?.inventory?.health_potion ?? 0}/3</b></span>
      <span>Gold <b>${event.player_state?.gold ?? event.gold}</b></span>
      <span>Score <b>${event.player_state?.score ?? 0}</b></span>
    </div>
    <details class="raw-event">
      <summary>Raw event</summary>
      <pre>${escapeHtml(JSON.stringify(event, null, 2))}</pre>
    </details>`;
}

async function loadFile(file: File): Promise<void> {
  if (file.size > 25 * 1024 * 1024) {
    showToast("This MVP accepts log files up to 25 MB.");
    return;
  }
  await importSource(await file.text(), file.name);
}

getElement<HTMLInputElement>("#file-input").addEventListener("change", (event) => {
  const file = (event.currentTarget as HTMLInputElement).files?.[0];
  if (file) void loadFile(file);
});

for (const selector of ["#sample-button", "#empty-sample-button"]) {
  getElement<HTMLButtonElement>(selector).addEventListener("click", () => {
    void importSource(sampleLog, "bundled sample");
  });
}

getElement<HTMLSelectElement>("#run-select").addEventListener("change", (event) => {
  state.runId = (event.currentTarget as HTMLSelectElement).value;
  selectInitialEvent();
  render();
});

getElement<HTMLSelectElement>("#depth-select").addEventListener("change", (event) => {
  state.selectedDepth = Number((event.currentTarget as HTMLSelectElement).value);
  renderRouteMap(eventsForRun(), eventsForRun().find((item) => item.sequence === state.selectedSequence));
});

getElement<HTMLInputElement>("#event-search").addEventListener("input", (event) => {
  state.query = (event.currentTarget as HTMLInputElement).value;
  renderTimeline(eventsForRun());
});

getElement("#filters").addEventListener("click", (event) => {
  const target = (event.target as HTMLElement).closest<HTMLButtonElement>("[data-filter]");
  if (!target) return;
  state.filter = target.dataset.filter as FilterName;
  document.querySelectorAll(".filter").forEach((element) => {
    element.classList.toggle("active", element === target);
  });
  renderTimeline(eventsForRun());
});

const dropZone = getElement("#drop-zone");
for (const eventName of ["dragenter", "dragover"]) {
  document.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.add("dragging");
  });
}
for (const eventName of ["dragleave", "drop"]) {
  document.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.classList.remove("dragging");
  });
}
document.addEventListener("drop", (event) => {
  const file = event.dataTransfer?.files[0];
  if (file) void loadFile(file);
});


let catalogue: StoredRun[] = [];
let activeStoredRun: StoredRun | null = null;
let catalogueOffset = 0;
let catalogueTotal = 0;
let catalogueGeneration = 0;
let detailGeneration = 0;
let catalogueBusy = false;
let databaseOnline = false;

function catalogueQuery(): URLSearchParams {
  const query = new URLSearchParams();
  for (const [selector, key] of [["#catalog-strategy", "strategy_id"], ["#catalog-result", "status"], ["#catalog-seed", "scenario_seed"]]) {
    const value = getElement<HTMLInputElement | HTMLSelectElement>(selector).value;
    if (value) query.set(key, value);
  }
  return query;
}

async function refreshCatalogue(): Promise<void> {
  if (catalogueBusy) return;
  catalogueBusy = true;
  const generation = catalogueGeneration;
  const query = catalogueQuery();
  const statsQuery = new URLSearchParams(query);
  query.set("limit", "100");
  query.set("offset", String(catalogueOffset));
  try {
    const [data, stats] = await Promise.all([
      api<{runs: StoredRun[]; total: number}>(`/api/runs?${query}`),
      api<{groups: RunGroup[]}>(`/api/stats?${statsQuery}`),
    ]);
    if (generation !== catalogueGeneration) return;
    databaseOnline = true;
    catalogue = data.runs;
    catalogueTotal = data.total;
    getElement("#catalog-status").textContent = `${data.total} Runs · auto-updated`;
    renderCatalogueSelect();
    getElement("#catalog-page").textContent = `${data.total ? catalogueOffset + 1 : 0}–${Math.min(catalogueOffset + 100, data.total)} / ${data.total}`;
    getElement<HTMLButtonElement>("#catalog-previous").disabled = catalogueOffset === 0;
    getElement<HTMLButtonElement>("#catalog-next").disabled = catalogueOffset + 100 >= data.total;
    renderStoredStats(stats.groups);
    if (!state.parsed && catalogue[0]) await selectStoredRun(catalogue[0]);
  } catch {
    databaseOnline = false;
    getElement("#catalog-status").textContent = "Run API offline — start tools/run_store.py serve";
  } finally {
    catalogueBusy = false;
    if (generation !== catalogueGeneration) void refreshCatalogue();
  }
}

function renderCatalogueSelect(): void {
  const select = getElement<HTMLSelectElement>("#catalog-run");
  const selected = activeStoredRun?.id ?? select.value;
  const options = [...catalogue];
  if (activeStoredRun && !options.some(run => run.id === activeStoredRun?.id)) options.unshift(activeStoredRun);
  const markup = options.map(run => `<option value="${escapeHtml(run.id)}">${escapeHtml(`${strategyLabel(run.strategy_id)} · seed ${run.scenario_seed ?? "?"} · D${run.max_depth} · ${run.status} · ${run.started_at} · ${run.id.slice(0, 8)}`)}</option>`).join("") || '<option value="">No Runs yet</option>';
  if (select.innerHTML !== markup) select.innerHTML = markup;
  if (options.some(run => run.id === selected)) select.value = selected;
}

async function selectStoredRun(run: StoredRun): Promise<void> {
  const generation = ++detailGeneration;
  try {
    const data = await api<{events: RunEvent[]}>(`/api/runs/${encodeURIComponent(run.id)}/events`);
    if (generation !== detailGeneration) return;
    const parsed = parseJsonLines(data.events.map(event => JSON.stringify(event)).join("\n"));
    state.parsed = parsed;
    state.runId = run.run_id;
    activeStoredRun = run;
    state.sourceName = "Run database";
    state.error = "";
    selectInitialEvent();
    render();
    renderCatalogueSelect();
  } catch (error) {
    if (generation === detailGeneration) showToast(error instanceof Error ? error.message : "Could not load Run.");
  }
}

async function importSource(source: string, sourceName: string): Promise<void> {
  if (!databaseOnline) {
    detailGeneration++;
    loadSource(source, `${sourceName} · offline, not saved`);
    showToast("Run API offline. Reading locally; this log has not been saved to the database.");
    return;
  }
  try {
    const result = await api<{run_ids: string[]}>("/api/import", {method: "POST", headers: {"Content-Type": "application/x-ndjson"}, body: source});
    catalogueOffset = 0;
    catalogueGeneration++;
    await refreshCatalogue();
    const key = result.run_ids.at(-1);
    if (key) await selectStoredRun(await api<StoredRun>(`/api/runs/${encodeURIComponent(key)}`));
    void refreshCatalogue();
    showToast(`Saved ${result.run_ids.length} Run(s) to the database.`);
  } catch (error) {
    showToast(error instanceof Error ? error.message : "Import failed.");
  }
}

function renderStoredStats(groups: RunGroup[]): void {
  const display = (value: number | null) => value === null ? "—" : value.toFixed(1);
  getElement("#catalog-stats").innerHTML = `<p class="panel-note">Completed Runs only for averages and clear rate. Groups keep simulation/schema versions, code revision and policy weights separate.</p><div class="table-scroll"><table><thead><tr><th>Strategy / policy</th><th>Version / revision</th><th>Runs / finished</th><th>Clear rate</th><th>Mean depth</th><th>Mean score</th><th>Mean turns</th></tr></thead><tbody>${groups.map(group => `<tr><td>${escapeHtml(strategyLabel(group.strategy_id))}<br><small>${escapeHtml(JSON.stringify(group.goal_policy))}</small></td><td>sim ${group.simulation_version} / schema ${group.schema_version}<br>${escapeHtml(group.code_revision || "revision unknown")}</td><td>${group.runs} / ${group.finished}</td><td>${group.clear_rate === null ? "—" : `${(group.clear_rate * 100).toFixed(1)}%`}</td><td>${display(group.mean_depth)}</td><td>${display(group.mean_score)}</td><td>${display(group.mean_turns)}</td></tr>`).join("")}</tbody></table></div>`;
}

function renderStoredComparison(): void {
  const panel = getElement<HTMLElement>("#comparison-panel");
  const run = activeStoredRun;
  panel.hidden = !run || run.scenario_seed === null;
  if (!run || run.scenario_seed === null) return;
  const generation = detailGeneration;
  panel.innerHTML = '<p class="panel-note">Loading same-seed Runs…</p>';
  const query = new URLSearchParams({scenario_seed: String(run.scenario_seed), simulation_version: String(run.simulation_version), schema_version: String(run.schema_version), code_revision: run.code_revision, limit: "100"});
  void api<{runs: StoredRun[]; total: number}>(`/api/runs?${query}`).then(data => {
    if (generation !== detailGeneration || activeStoredRun?.id !== run.id) return;
    const peers = data.runs.filter(peer => peer.code_revision === run.code_revision);
    panel.hidden = peers.length < 2;
    panel.innerHTML = `<div class="comparison-heading"><h3>Same-seed comparison</h3><span>seed ${run.scenario_seed} · sim ${run.simulation_version}${data.total > 100 ? " · latest 100 Runs" : ""}</span></div><div class="comparison-cards">${peers.map(peer => `<button class="comparison-card ${peer.id === run.id ? "active" : ""}" data-stored-run="${escapeHtml(peer.id)}"><span class="comparison-name">${escapeHtml(strategyLabel(peer.strategy_id))}</span><span>${escapeHtml(JSON.stringify(peer.goal_policy))}</span><span>Score ${peer.score} · D${peer.max_depth} · Lv ${peer.level}</span><span>${peer.turns} turns · ${escapeHtml(peer.status)}</span></button>`).join("")}</div>`;
    panel.querySelectorAll<HTMLButtonElement>("[data-stored-run]").forEach(button => button.addEventListener("click", () => {
      const peer = peers.find(candidate => candidate.id === button.dataset.storedRun);
      if (peer) void selectStoredRun(peer);
    }));
  }).catch(() => {
    if (generation === detailGeneration) panel.innerHTML = '<p class="panel-note">Comparison unavailable while API is offline.</p>';
  });
}

for (const selector of ["#catalog-strategy", "#catalog-result", "#catalog-seed"]) {
  getElement(selector).addEventListener("change", () => {
    catalogueOffset = 0;
    catalogueGeneration++;
    void refreshCatalogue();
  });
}
getElement<HTMLSelectElement>("#catalog-run").addEventListener("change", event => {
  const id = (event.currentTarget as HTMLSelectElement).value;
  const run = catalogue.find(candidate => candidate.id === id);
  if (run) void selectStoredRun(run);
});
for (const [selector, step] of [["#catalog-previous", -100], ["#catalog-next", 100]] as const) {
  getElement(selector).addEventListener("click", () => {
    catalogueOffset = Math.max(0, Math.min(catalogueTotal - 1, catalogueOffset + step));
    catalogueGeneration++;
    void refreshCatalogue();
  });
}
void refreshCatalogue();
window.setInterval(() => { if (!document.hidden) void refreshCatalogue(); }, 3000);
