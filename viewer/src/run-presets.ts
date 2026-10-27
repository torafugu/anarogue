import { api } from "./catalog.ts";

type Settings = Record<string, number | string | number[] | string[]>;
interface Preset { id: string; name: string; kind: "run" | "batch"; version: number; settings: Settings }

export function mountRunPresets(root: HTMLElement): void {
  const fields = ["seed", "max_turns", "enemy_amount", "treasure_amount", "map_depth", "enemy_weight", "item_weight", "stairs_weight"];
  const numberFields = (entries: (string | number)[][]) => entries.map(([key, label, min, max, value]) => `<label class="select-label">${label}<input id="preset-${key}" type="number" required min="${min}" max="${max}" step="1" value="${value}" /></label>`).join("");
  root.innerHTML = `
    <summary>Run presets — create settings for the Godot launcher</summary>
    <p class="panel-note">Save a named Strategy, weights and DSL with Seed and Map settings. In Godot, select the preset and Run. Saving validates the configuration without starting a Run.</p>
    <div class="preset-actions">
      <label class="select-label">Saved preset<select id="preset-select"><option value="">New preset</option></select></label>
      <button type="button" class="button button-ghost" id="preset-reload">Reload list</button>
      <button type="button" class="button button-ghost" id="preset-new">New</button>
      <button type="button" class="button button-ghost" id="preset-duplicate">Duplicate</button>
    </div>
    <form id="preset-form">
      <div class="preset-fields">
        <label class="select-label">Name<input id="preset-name" required maxlength="80" placeholder="e.g. Archer counter / cautious" /></label>
        <label class="select-label">Mode<select id="preset-kind"><option value="run">Single Run</option><option value="batch">AutoRun</option></select></label>
        <label class="select-label">Strategy<select id="preset-strategy"><option value="aggressive">Aggressive</option><option value="cautious">Cautious</option></select></label>
        <label class="select-label" id="preset-batch-strategies-label" hidden>Strategies<select id="preset-batch-strategies"><option value="both">Both strategies</option><option value="aggressive">Aggressive</option><option value="cautious">Cautious</option></select></label>
        ${numberFields([["seed", "Seed", 0, 4294967295, 424242], ["max_turns", "Max turns", 1, 100000, 5000], ["enemy_amount", "Enemy amount (%)", 0, 500, 100], ["treasure_amount", "Treasure amount (%)", 0, 500, 100], ["map_depth", "Map depth", 1, 100, 5]])}
      </div>
      <div class="preset-fields" id="preset-single-weights">${numberFields([["enemy_weight", "Enemy weight", 0, 1000, 4], ["item_weight", "Treasure weight", 0, 1000, 2], ["stairs_weight", "Stairs weight", 0, 1000, 1]])}</div>
      <div id="preset-batch-weights" hidden>
        <div class="preset-fields">${[["enemy_weights", "Enemy"], ["item_weights", "Treasure"], ["stairs_weights", "Stairs"]].map(([key, label]) => `<label class="select-label">${label} values<input id="preset-${key}" value="0,1,2,3,4" /></label>`).join("")}</div>
        <p class="panel-note" id="preset-batch-count"></p>
        <p class="panel-note">Comma-separated integers (0–1000). All-zero combinations are excluded; at most 2,000 Runs. DSL overrides apply to every combination.</p>
      </div>
      <p class="panel-note">Map amounts: 100% = normal, 0% = none. Depth is the exit depth. Blank DSL uses the Strategy unchanged; declared weights override the form.</p>
      <label class="select-label">Player DSL<textarea id="preset-dsl" rows="12" spellcheck="false" placeholder='rule "Counter Archer" {\n  target nearest enemy where type == archer and shootable\n  do shoot target\n}'></textarea></label>
      <p class="panel-note">Rules run top to bottom before automatic healing and Brute avoidance. Actions: shoot target, attack target, move_toward target, keep_distance target min = 3 max = 5, use_potion, wait. Use floor.enemy_count == 0 to collect or descend after clearing. <a href="https://github.com/torafugu/anarogue/blob/main/docs/player-dsl.md" target="_blank" rel="noopener">DSL reference</a> · <a href="https://github.com/torafugu/anarogue/blob/main/examples/player-dsl/bow-sweep.dsl" target="_blank" rel="noopener">Bow sweep example</a></p>
      <div class="preset-actions">
        <button type="button" class="button button-ghost" id="preset-validate">Validate settings / DSL</button>
        <button type="submit" class="button button-primary" id="preset-save">Save preset</button>
        <button type="button" class="button button-danger" id="preset-delete">Delete preset</button>
        <span id="preset-version" class="panel-note"></span>
      </div>
    </form>
    <p id="preset-status" role="status" aria-live="polite"></p>`;
  const input = (id: string) => root.querySelector<HTMLInputElement>(`#preset-${id}`)!;
  const select = (id: string) => root.querySelector<HTMLSelectElement>(`#preset-${id}`)!;
  const form = root.querySelector<HTMLFormElement>("form")!;
  const status = root.querySelector<HTMLElement>("#preset-status")!;
  const dsl = root.querySelector<HTMLTextAreaElement>("textarea")!;
  let presets: Preset[] = [], current: Preset | null = null, dirty = false, busy = false;
  const message = (value: string) => { status.textContent = value; };
  const body = (value: unknown, method = "POST"): RequestInit => ({ method, headers: { "Content-Type": "application/json" }, body: JSON.stringify(value) });
  const settings = (): Settings => {
    const result: Settings = {};
    for (const key of fields.slice(0, 5)) result[key] = Number(input(key).value);
    result.dsl = dsl.value;
    if (select("kind").value === "batch") {
      const strategies = select("batch-strategies").value;
      result.strategies = strategies === "both" ? ["aggressive", "cautious"] : [strategies];
      for (const key of ["enemy_weights", "item_weights", "stairs_weights"]) {
        const values = input(key).value.split(",").map(v => v.trim());
        if (values.some(v => !/^\d+$/.test(v))) throw new Error("AutoRun values must be comma-separated integers.");
        result[key] = [...new Set(values.map(Number))];
      }
    } else {
      result.strategy = select("strategy").value;
      for (const key of fields.slice(5)) result[key] = Number(input(key).value);
    }
    return result;
  };
  const mode = () => {
    const batch = select("kind").value === "batch";
    select("strategy").parentElement!.hidden = batch;
    root.querySelector<HTMLElement>("#preset-batch-strategies-label")!.hidden = !batch;
    root.querySelector<HTMLElement>("#preset-batch-weights")!.hidden = !batch;
    root.querySelector<HTMLElement>("#preset-single-weights")!.hidden = batch;
    for (const key of fields.slice(5)) input(key).disabled = batch || busy;
    try {
      const s = settings(), lists = [s.enemy_weights, s.item_weights, s.stairs_weights] as number[][];
      const total = batch ? (s.strategies as string[]).length * (lists.reduce((n, list) => n * list.length, 1) - Number(lists.every(list => list.includes(0)))) : 1;
      root.querySelector<HTMLElement>("#preset-batch-count")!.textContent = `${total} Runs`;
    } catch { root.querySelector<HTMLElement>("#preset-batch-count")!.textContent = "Enter valid weight lists."; }
  };
  const renderList = () => {
    select("select").replaceChildren(new Option("New preset", ""), ...presets.map(p => new Option(`${p.name} · ${p.kind === "batch" ? "AutoRun" : "Run"}`, p.id)));
    select("select").value = current?.id ?? "";
  };
  const fill = (preset: Preset | null) => {
    current = preset; form.reset(); input("name").value = preset?.name ?? "";
    select("kind").value = preset?.kind ?? "run";
    if (preset) {
      for (const key of fields) if (preset.settings[key] !== undefined) input(key).value = String(preset.settings[key]);
      select("strategy").value = String(preset.settings.strategy ?? "aggressive");
      for (const key of ["enemy_weights", "item_weights", "stairs_weights"]) if (Array.isArray(preset.settings[key])) input(key).value = preset.settings[key].join(",");
      const strategies = preset.settings.strategies as string[] | undefined;
      select("batch-strategies").value = strategies?.length === 1 ? strategies[0] : "both";
    }
    dsl.value = String(preset?.settings.dsl ?? "");
    root.querySelector<HTMLElement>("#preset-version")!.textContent = preset ? `Saved version ${preset.version}` : "New preset";
    root.querySelector<HTMLButtonElement>("#preset-delete")!.disabled = !current;
    dirty = false; renderList(); mode();
  };
  const operation = async (action: () => Promise<void>) => {
    if (busy) return;
    busy = true;
    root.querySelectorAll<HTMLButtonElement | HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>("button,input,select,textarea").forEach(e => e.disabled = true);
    try { await action(); } catch (error) { message(error instanceof Error ? error.message : String(error)); }
    finally {
      busy = false;
      root.querySelectorAll<HTMLButtonElement | HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>("button,input,select,textarea").forEach(e => e.disabled = false);
      root.querySelector<HTMLButtonElement>("#preset-delete")!.disabled = !current; mode();
    }
  };
  const reload = async () => { presets = (await api<{presets: Preset[]}>("/api/presets")).presets; renderList(); };
  const discard = () => !dirty || window.confirm("Discard unsaved preset changes?");
  form.addEventListener("input", () => { dirty = true; message("Unsaved changes. Save to make these settings available in Godot."); mode(); });
  select("kind").addEventListener("change", mode);
  select("strategy").addEventListener("change", () => {
    const cautious = select("strategy").value === "cautious";
    input("enemy_weight").value = cautious ? "1" : "4"; input("item_weight").value = "2"; input("stairs_weight").value = cautious ? "4" : "1";
  });
  select("select").addEventListener("change", () => {
    if (!discard()) { select("select").value = current?.id ?? ""; return; }
    fill(presets.find(p => p.id === select("select").value) ?? null); message("");
  });
  root.querySelector("#preset-new")!.addEventListener("click", () => { if (discard()) { fill(null); message(""); } });
  root.querySelector("#preset-duplicate")!.addEventListener("click", () => {
    current = null; input("name").value = `${input("name").value || "Preset"} copy`.slice(0, 80); dirty = true;
    renderList(); root.querySelector<HTMLElement>("#preset-version")!.textContent = "New copy — not saved";
    root.querySelector<HTMLButtonElement>("#preset-delete")!.disabled = true; message("Choose a name and save the copy.");
  });
  root.querySelector("#preset-reload")!.addEventListener("click", () => {
    if (discard()) void operation(async () => { const id = current?.id; await reload(); fill(presets.find(p => p.id === id) ?? null); message("Preset list reloaded."); });
  });
  root.querySelector("#preset-validate")!.addEventListener("click", () => {
    if (form.reportValidity()) void operation(async () => {
      const report = await api<{total: number}>("/api/presets/validate", body({ kind: select("kind").value, settings: settings() }));
      message(`Valid settings / DSL · ${report.total} Runs. No Run started. Changes are not saved yet.`);
    });
  });
  form.addEventListener("submit", event => {
    event.preventDefault(); void operation(async () => {
      const saved = await api<Preset>(current ? `/api/presets/${current.id}` : "/api/presets", body({ name: input("name").value, kind: select("kind").value, settings: settings(), ...(current ? {version: current.version} : {}) }, current ? "PUT" : "POST"));
      current = saved; await reload(); fill(saved); message(`Saved “${saved.name}” · version ${saved.version}. Select it in Godot; use Reload presets if needed.`);
    });
  });
  root.querySelector("#preset-delete")!.addEventListener("click", () => {
    if (current && window.confirm(`Delete preset “${current.name}”? Stored Runs will remain.`)) void operation(async () => {
      await api(`/api/presets/${current!.id}`, body({version: current!.version}, "DELETE"));
      current = null; await reload(); fill(null); message("Preset deleted. Stored Runs are unchanged.");
    });
  });
  window.addEventListener("beforeunload", event => { if (dirty) event.preventDefault(); });
  fill(null); void operation(async () => { await reload(); message(presets.length ? "Select a preset to edit, or create a new one." : "No presets yet. Name and save your first configuration."); });
}
