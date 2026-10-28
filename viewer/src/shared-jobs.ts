import { api } from "./catalog.ts";

export interface SharedJob {
  id: string; kind: "run" | "batch"; status: string; created_at: string;
  total?: number; completed?: number; failed?: number; run_id: string | null;
  cancel_requested?: boolean; interrupted?: boolean; error?: string;
  preset?: {name: string; version: number};
  current_settings?: {strategy: string; enemy_weight: number; item_weight: number; stairs_weight: number};
}

export function mountSharedJobs(root: HTMLElement, inspect: (id: string) => Promise<void>, replay: (id: string) => Promise<void>): void {
  root.innerHTML = `<div class="panel-heading"><div><p class="eyebrow">SHARED EXECUTION</p><h2>Jobs</h2></div><button class="button button-ghost" id="jobs-refresh">Refresh</button></div><p class="panel-note">All devices share this queue. Runs continue on the server when you close a client. Interrupted jobs are kept after API restarts; saved results remain available.</p><p id="jobs-status" role="status"></p><div id="jobs-list"></div><div class="preset-actions"><button class="button button-ghost" id="jobs-previous">Previous</button><span id="jobs-page"></span><button class="button button-ghost" id="jobs-next">Next</button></div>`;
  const status = root.querySelector<HTMLElement>("#jobs-status")!;
  const list = root.querySelector<HTMLElement>("#jobs-list")!;
  let loading = false, offset = 0, total = 0;
  const refresh = async () => {
    if (loading) return;
    loading = true;
    try {
      const page = await api<{jobs: SharedJob[]; total: number}>(`/api/jobs?limit=20&offset=${offset}`);
      total = page.total; list.replaceChildren();
      for (const job of page.jobs) {
        const card = document.createElement("article"); card.className = "job-card"; card.dataset.jobId = job.id;
        const title = document.createElement("h3"); title.textContent = job.preset ? `${job.preset.name} · v${job.preset.version}` : `${job.kind === "batch" ? "AutoRun" : "Run"} · ${job.id.slice(0, 8)}`;
        const progress = document.createElement("p"); progress.className = "job-progress";
        progress.textContent = `${job.interrupted ? "interrupted" : job.status} · ${job.created_at}${job.kind === "batch" ? ` · ${job.completed ?? 0}/${job.total} saved · ${job.failed ?? 0} failed` : ""}${job.cancel_requested ? " · stopping after current Run" : ""}`;
        card.append(title, progress);
        if (job.kind === "batch") { const bar = document.createElement("progress"); bar.max = job.total ?? 1; bar.value = (job.completed ?? 0) + (job.failed ?? 0); card.append(bar); }
        if (job.current_settings) { const current = document.createElement("p"); const s = job.current_settings; current.textContent = `${s.strategy} · Enemy ${s.enemy_weight} / Treasure ${s.item_weight} / Stairs ${s.stairs_weight}`; card.append(current); }
        if (job.error) { const error = document.createElement("p"); error.textContent = job.error; card.append(error); }
        const actions = document.createElement("div"); actions.className = "preset-actions";
        const button = (text: string, action: () => Promise<void>) => { const b = document.createElement("button"); b.className = "button button-ghost"; b.textContent = text; b.onclick = async () => { b.disabled = true; try { await action(); } catch (e) { status.textContent = String(e); } finally { b.disabled = false; } }; actions.append(b); return b; };
        if (job.kind === "batch" && ["queued", "running"].includes(job.status)) {
          const stop = button("Stop after current Run", async () => { await api(`/api/jobs/${job.id}/cancel`, {method:"POST", headers:{"Content-Type":"application/json"}, body:"{}"}); await refresh(); });
          stop.disabled = !!job.cancel_requested;
        }
        if (job.run_id) { button("Inspect latest Run", () => inspect(job.run_id!)); button("Replay latest Run", () => replay(job.run_id!)); }
        card.append(actions); list.append(card);
      }
      status.textContent = total ? `${total} shared jobs · updated automatically` : "No jobs yet. Select a saved Run preset and start it above.";
      root.querySelector("#jobs-page")!.textContent = total ? `${offset + 1}–${Math.min(offset + 20, total)} / ${total}` : "0 jobs";
      root.querySelector<HTMLButtonElement>("#jobs-previous")!.disabled = offset === 0;
      root.querySelector<HTMLButtonElement>("#jobs-next")!.disabled = offset + 20 >= total;
    } catch (error) { status.textContent = `Jobs unavailable: ${String(error)}`; }
    finally { loading = false; }
  };
  root.querySelector("#jobs-refresh")!.addEventListener("click", () => void refresh());
  root.querySelector("#jobs-previous")!.addEventListener("click", () => { if (!loading) { offset = Math.max(0, offset - 20); void refresh(); } });
  root.querySelector("#jobs-next")!.addEventListener("click", () => { if (!loading && offset + 20 < total) { offset += 20; void refresh(); } });
  window.addEventListener("anarogue-job-started", () => { offset = 0; void refresh(); });
  window.setInterval(() => { if (!document.hidden) void refresh(); }, 2000);
  void refresh();
}
