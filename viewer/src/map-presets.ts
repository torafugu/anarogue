import { api } from "./catalog.ts";

export interface MapPreset {
  id: string; name: string; version: number;
  settings: { enemy_amount: number; treasure_amount: number; map_depth: number };
}
export const mapKey = (p: MapPreset): string => `${p.id}:${p.version}`;
export const mapSummary = (p: MapPreset): string => `${p.name} · v${p.version} · Enemy ${p.settings.enemy_amount}% / Treasure ${p.settings.treasure_amount}% / Depth ${p.settings.map_depth}`;

export function mountMapPresets(root: HTMLElement): void {
  root.innerHTML = `<summary>Map presets — Enemy, Treasure and Depth</summary>
    <p class="panel-note">Save reusable Map settings here, then select a Map preset in Run presets. Seed is set separately for each Run preset.</p>
    <div class="preset-actions"><label class="select-label">Saved Map preset<select id="map-select"></select></label>
      <button type="button" class="button button-ghost" id="map-reload">Reload list</button>
      <button type="button" class="button button-ghost" id="map-new">New</button>
      <button type="button" class="button button-ghost" id="map-duplicate">Duplicate</button></div>
    <form id="map-form"><div class="preset-fields">
      <label class="select-label">Name<input id="map-name" required maxlength="80" placeholder="e.g. Dense enemies / 10 floors" /></label>
      <label class="select-label">Enemy amount (%)<input id="map-enemy_amount" type="number" min="0" max="500" step="1" value="100" required /></label>
      <label class="select-label">Treasure amount (%)<input id="map-treasure_amount" type="number" min="0" max="500" step="1" value="100" required /></label>
      <label class="select-label">Map depth<input id="map-map_depth" type="number" min="1" max="100" step="1" value="5" required /></label>
    </div><p class="panel-note">100% = normal, 0% = none. Depth is the exit depth. Changes create a new Map version; existing Run presets keep their selected version until you select the updated Map and save them.</p>
    <div class="preset-actions"><button type="submit" class="button button-primary" id="map-save">Save Map preset</button>
      <button type="button" class="button button-danger" id="map-delete">Delete Map preset</button><span id="map-version" class="panel-note"></span></div></form>
    <p id="map-status" role="status" aria-live="polite"></p>`;
  const select = root.querySelector<HTMLSelectElement>("#map-select")!;
  const form = root.querySelector<HTMLFormElement>("form")!;
  const input = (key: string) => root.querySelector<HTMLInputElement>(`#map-${key}`)!;
  const message = (s: string) => { root.querySelector<HTMLElement>("#map-status")!.textContent = s; };
  let list: MapPreset[] = [], current: MapPreset | null = null, dirty = false, busy = false;
  const render = () => { select.replaceChildren(new Option("New Map preset", ""), ...list.map(p => new Option(`${p.name} · v${p.version}`, p.id))); select.value = current?.id ?? ""; };
  const fill = (p: MapPreset | null) => {
    current = p; form.reset(); input("name").value = p?.name ?? "";
    if (p) for (const [key, value] of Object.entries(p.settings)) input(key).value = String(value);
    dirty = false; render(); root.querySelector<HTMLButtonElement>("#map-delete")!.disabled = !p;
    root.querySelector<HTMLElement>("#map-version")!.textContent = p ? `Saved version ${p.version}` : "New Map preset";
  };
  const body = (value: unknown, method: string): RequestInit => ({method, headers:{"Content-Type":"application/json"}, body:JSON.stringify(value)});
  const reload = async () => { list = (await api<{presets: MapPreset[]}>("/api/map-presets")).presets; render(); };
  const operation = async (action: () => Promise<void>) => {
    if (busy) return; busy = true;
    root.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLButtonElement>("input,select,button").forEach(e => e.disabled = true);
    try { await action(); } catch (e) { message(e instanceof Error ? e.message : String(e)); }
    finally { busy = false; root.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLButtonElement>("input,select,button").forEach(e => e.disabled = false); root.querySelector<HTMLButtonElement>("#map-delete")!.disabled = !current; }
  };
  const discard = () => !dirty || window.confirm("Discard unsaved Map preset changes?");
  form.addEventListener("input", () => { dirty = true; message("Unsaved Map changes."); });
  select.addEventListener("change", () => { if (discard()) { fill(list.find(p => p.id === select.value) ?? null); message(""); } else select.value = current?.id ?? ""; });
  root.querySelector("#map-new")!.addEventListener("click", () => { if (discard()) { fill(null); message(""); } });
  root.querySelector("#map-duplicate")!.addEventListener("click", () => { current = null; input("name").value = `${input("name").value || "Map"} copy`.slice(0,80); dirty = true; render(); root.querySelector<HTMLButtonElement>("#map-delete")!.disabled = true; root.querySelector<HTMLElement>("#map-version")!.textContent = "New copy — not saved"; message("Choose a name and save the copy."); });
  root.querySelector("#map-reload")!.addEventListener("click", () => { if (discard()) void operation(async () => { const id = current?.id; await reload(); fill(list.find(p => p.id === id) ?? null); window.dispatchEvent(new Event("anarogue-maps-changed")); message("Map preset list reloaded."); }); });
  form.addEventListener("submit", event => {
    event.preventDefault(); void operation(async () => {
      const settings = {enemy_amount:Number(input("enemy_amount").value), treasure_amount:Number(input("treasure_amount").value), map_depth:Number(input("map_depth").value)};
      const saved = await api<MapPreset>(current ? `/api/map-presets/${current.id}` : "/api/map-presets", body({name:input("name").value, settings, ...(current ? {version:current.version} : {})}, current ? "PUT" : "POST"));
      await reload(); fill(saved); message(`Saved “${saved.name}” · version ${saved.version}. Select it in Run presets.`);
      window.dispatchEvent(new Event("anarogue-maps-changed"));
    });
  });
  root.querySelector("#map-delete")!.addEventListener("click", () => {
    if (current && window.confirm(`Delete Map preset “${current.name}”? Maps used by Run presets must be reassigned first.`)) void operation(async () => {
      await api(`/api/map-presets/${current!.id}`, body({version:current!.version}, "DELETE"));
      await reload(); fill(null); message("Map preset deleted. Stored Runs are unchanged."); window.dispatchEvent(new Event("anarogue-maps-changed"));
    });
  });
  window.addEventListener("beforeunload", event => { if (dirty) event.preventDefault(); });
  fill(null); void operation(async () => { await reload(); message("Select a Map preset to edit, or create a new one."); });
}
