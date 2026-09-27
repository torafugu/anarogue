import "./style.css";
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
      <button class="button button-ghost" id="sample-button" type="button">Load sample</button>
      <label class="button button-primary" for="file-input">Open JSONL</label>
      <input id="file-input" type="file" accept=".jsonl,.json,text/plain,application/json" />
    </div>
  </header>
  <main>
    <section class="drop-zone" id="drop-zone" aria-label="JSONL file drop zone">
      <div class="drop-icon" aria-hidden="true">↧</div>
      <p class="eyebrow">DROP RUN LOG</p>
      <h2>Turn raw events into a readable story.</h2>
      <p>Open <code>simple_rogue_battle_log.jsonl</code> or try the bundled sample.</p>
      <div class="drop-actions">
        <label class="button button-primary" for="file-input">Choose a file</label>
        <button class="button button-ghost" id="empty-sample-button" type="button">Use sample data</button>
      </div>
      <p class="privacy-note">Analysis stays in this browser. No log is uploaded.</p>
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
            <span><i class="legend-stairs"></i>Stairs</span>
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

function loadSource(source: string, sourceName: string): void {
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
  const strategy = events.find((event) => event.event === "run_start")?.details
    .strategy_id;

  getElement("#run-title").textContent = state.runId;
  getElement("#source-label").textContent =
    `${state.sourceName} · ${events.length} events · ${String(strategy ?? "unknown strategy")}`;
  const status = getElement("#run-status");
  status.textContent = summary.result;
  status.className = `status-pill status-${summary.result}`;

  renderRunSelect();
  renderWarnings();
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
  label.hidden = runIds.length < 2;
  select.innerHTML = runIds
    .map(
      (id) =>
        `<option value="${escapeHtml(id)}" ${id === state.runId ? "selected" : ""}>${escapeHtml(id)}</option>`,
    )
    .join("");
}

function renderWarnings(): void {
  const warning = getElement<HTMLDivElement>("#warning");
  const warnings = state.parsed?.warnings ?? [];
  warning.hidden = warnings.length === 0;
  warning.textContent = warnings.join(" ");
}

function renderMetrics(events: RunEvent[]): void {
  const summary = summarizeRun(events);
  const metrics = [
    ["Turns", summary.turns, "elapsed actions"],
    ["Depth", summary.maxDepth, "deepest floor"],
    ["Kills", summary.kills, "enemies removed"],
    ["Damage", summary.damageTaken, "HP lost"],
    ["Gold", summary.gold, "final total"],
    ["Decisions", summary.decisions, "rules evaluated"],
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
  const enemies = Array.isArray(floorStart?.details.enemies)
    ? (floorStart.details.enemies as EnemySnapshot[])
    : [];
  const selectedPos =
    selected?.depth === state.selectedDepth ? selected.player_state?.pos : undefined;
  const route = positions.map((pos) => `${pos.x + 0.5},${pos.y + 0.5}`).join(" ");
  const enemyMarks = enemies
    .map(
      (enemy) => `
        <g class="map-enemy ${enemy.type === "archer" ? "archer" : ""}">
          <circle cx="${enemy.pos.x + 0.5}" cy="${enemy.pos.y + 0.5}" r=".38" />
          <title>${escapeHtml(enemy.id)} · ${escapeHtml(enemy.type)}</title>
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
      ${stairs ? `<g class="map-stairs"><rect x="${stairs.x + 0.16}" y="${stairs.y + 0.16}" width=".68" height=".68" rx=".1" /><title>Stairs</title></g>` : ""}
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
        <div><dt>Enemies</dt><dd>${decision.observation.enemy_count}</dd></div>
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
    <div class="state-strip">
      <span>Turn <b>${event.turn}</b></span>
      <span>Depth <b>${event.depth}</b></span>
      <span>HP <b>${event.player_state?.hp ?? event.hp}</b></span>
      <span>Gold <b>${event.player_state?.gold ?? event.gold}</b></span>
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
  loadSource(await file.text(), file.name);
}

getElement<HTMLInputElement>("#file-input").addEventListener("change", (event) => {
  const file = (event.currentTarget as HTMLInputElement).files?.[0];
  if (file) void loadFile(file);
});

for (const selector of ["#sample-button", "#empty-sample-button"]) {
  getElement<HTMLButtonElement>(selector).addEventListener("click", () => {
    loadSource(sampleLog, "bundled sample");
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
