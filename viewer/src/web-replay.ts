export function createWebReplay(): (runId: string, turn?: number) => Promise<void> {
  const dialog = document.createElement("dialog");
  dialog.id = "web-replay-dialog";
  dialog.innerHTML = `<div class="web-replay-bar"><h2>Replay</h2><button class="button button-ghost" type="button">Close</button></div><p class="panel-note" role="status"></p><div class="web-replay-frame"></div>`;
  document.body.append(dialog);
  const container = dialog.querySelector<HTMLDivElement>(".web-replay-frame")!;
  const status = dialog.querySelector<HTMLParagraphElement>("[role=status]")!;
  let generation = 0, iframe: HTMLIFrameElement | null = null;
  const unload = () => { generation++; iframe?.remove(); iframe = null; container.replaceChildren(); };
  dialog.querySelector("button")!.addEventListener("click", () => dialog.close());
  dialog.addEventListener("close", unload);
  window.addEventListener("message", event => {
    if (event.origin !== location.origin || event.source !== iframe?.contentWindow) return;
    if (event.data?.type === "anarogue-replay-ready") status.textContent = "Use Previous / Play / Next, or arrow keys, to replay Turns.";
    if (event.data?.type === "anarogue-replay-error") status.textContent = String(event.data.message);
  });
  return async (runId, turn = 0) => {
    if (!/^[0-9a-f]{64}$/.test(runId)) throw new Error("Select a stored Run to replay.");
    unload(); const token = generation;
    if (!dialog.open) dialog.showModal();
    status.textContent = "Loading Replay…";
    try {
      const response = await fetch("/replay/index.html", {signal: AbortSignal.timeout(15000)});
      if (!response.ok || !(await response.text()).includes("new Engine(")) throw new Error("Web Replay is unavailable. Ask the server operator to install the Replay build.");
      if (token !== generation || !dialog.open) return;
      iframe = document.createElement("iframe");
      iframe.title = "Godot Run Replay";
      iframe.allow = "fullscreen";
      iframe.src = `/replay/index.html?run=${encodeURIComponent(runId)}&turn=${Math.max(0, Math.floor(turn))}`;
      container.append(iframe);
    } catch (error) {
      if (token === generation) status.textContent = error instanceof Error ? error.message : String(error);
    }
  };
}
