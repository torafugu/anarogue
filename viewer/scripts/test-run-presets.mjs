import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {chromium} from 'playwright';

const directory = mkdtempSync(join(tmpdir(), 'anarogue-presets-'));
const bowSweep = readFileSync(new URL('../../examples/player-dsl/bow-sweep.dsl', import.meta.url), 'utf8');
const python = spawn(process.env.PYTHON || 'python3', ['-u', '-c', `
import os, sys
sys.path.insert(0, 'tools')
from run_jobs import RunJobs
from run_store import RunStore, make_server
store = RunStore(sys.argv[1])
jobs = RunJobs(store, os.environ.get('ANAROGUE_RUST_BINARY', 'simulation-core/target/debug/anarogue-sim'))
server = make_server(store, port=0, jobs=jobs)
print(server.server_port, flush=True)
server.serve_forever()
`, join(directory, 'runs.sqlite3')], {cwd: new URL('../..', import.meta.url), stdio: ['ignore', 'pipe', 'inherit']});
let vite, browser;
try {
  const [output] = await once(python.stdout, 'data');
  const apiPort = Number(output.toString().trim()); assert(apiPort > 0);
  const reserve = createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening');
  const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
  vite = spawn(process.execPath, ['node_modules/vite/bin/vite.js', '--host', '127.0.0.1', '--port', String(port), '--strictPort'], {
    cwd: new URL('..', import.meta.url), env: {...process.env, ANAROGUE_RUN_API_URL: `http://127.0.0.1:${apiPort}`}, stdio: 'ignore'});
  const base = `http://127.0.0.1:${port}`;
  for (let i = 0; i < 100; i++) { try { if ((await fetch(base)).ok) break; } catch {} await new Promise(resolve => setTimeout(resolve, 50)); }
  browser = await chromium.launch({headless: true, ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? {executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE} : {})});
  const page = await browser.newPage(); page.setDefaultTimeout(10000);
  const errors = []; page.on('pageerror', error => errors.push(error.message));
  await page.goto(base); await page.click('#run-presets summary');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.includes('No presets yet'));
  await page.fill('#preset-name', '弓反撃 / Cautious');
  await page.selectOption('#preset-strategy', 'cautious');
  assert.equal(await page.inputValue('#preset-enemy_weight'), '1');
  assert.equal(await page.inputValue('#preset-stairs_weight'), '4');
  await page.fill('#preset-item_weight', '7'); await page.fill('#preset-max_turns', '2');
  await page.fill('#preset-enemy_amount', '200'); await page.fill('#preset-map_depth', '8');
  await page.fill('#preset-dsl', 'rule "Bad" { when self.hpp < 5 do wait }');
  await page.click('#preset-save');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.includes('DSL line'));
  assert.equal((await (await fetch(`${base}/api/presets`)).json()).presets.length, 0);
  await page.fill('#preset-dsl', bowSweep); await page.click('#preset-validate');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.startsWith('Valid settings'));
  assert.equal((await (await fetch(`${base}/api/database`)).json()).runs, 0);
  await page.click('#preset-save');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.startsWith('Saved'));
  let presets = (await (await fetch(`${base}/api/presets`)).json()).presets;
  assert.equal(presets.length, 1); const original = presets[0];
  assert.equal(original.settings.item_weight, 7); assert.equal(original.settings.dsl, bowSweep);
  await page.reload(); await page.click('#run-presets summary');
  await page.waitForFunction(() => !document.querySelector('#preset-select').disabled);
  await page.selectOption('#preset-select', original.id);
  assert.equal(await page.inputValue('#preset-item_weight'), '7');
  assert.equal(await page.inputValue('#preset-dsl'), bowSweep);
  await page.fill('#preset-name', 'Renamed'); await page.click('#preset-save');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.includes('version 2'));
  // A stale editor cannot overwrite a change from another browser.
  await fetch(`${base}/api/presets/${original.id}`, {method:'PUT', headers:{'Content-Type':'application/json'}, body:JSON.stringify({name:'External edit', kind:'run', settings:original.settings, version:2})});
  await page.fill('#preset-name', 'Stale overwrite'); await page.click('#preset-save');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.includes('HTTP 409'));
  assert.equal(await page.inputValue('#preset-name'), 'Stale overwrite', 'Conflict keeps the draft');
  page.once('dialog', dialog => dialog.accept()); await page.click('#preset-reload');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.includes('reloaded'));
  assert.equal(await page.inputValue('#preset-name'), 'External edit');
  await page.click('#preset-duplicate'); await page.fill('#preset-name', 'Sweep 14');
  await page.selectOption('#preset-kind', 'batch');
  for (const key of ['enemy_weights', 'item_weights', 'stairs_weights']) await page.fill(`#preset-${key}`, '0,1');
  assert.equal(await page.textContent('#preset-batch-count'), '14 Runs');
  await page.click('#preset-save'); await page.waitForFunction(() => document.querySelector('#preset-status').textContent.startsWith('Saved'));
  presets = (await (await fetch(`${base}/api/presets`)).json()).presets;
  assert.equal(presets.length, 2); assert.equal(presets.find(p => p.name === 'Sweep 14').kind, 'batch');
  const accepted = await (await fetch(`${base}/api/presets/${original.id}/run`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({version:3})})).json();
  let job;
  for (let i = 0; i < 200; i++) { job = await (await fetch(`${base}/api/jobs/${accepted.id}`)).json(); if (job.status === 'completed' || job.status === 'failed') break; await new Promise(resolve => setTimeout(resolve, 20)); }
  assert.equal(job.status, 'completed', JSON.stringify(job));
  const run = await (await fetch(`${base}/api/runs/${job.run_id}`)).json();
  assert.equal(run.preset.name, 'External edit'); assert.equal(run.preset.version, 3);
  await page.setViewportSize({width: 390, height: 844});
  assert(await page.locator('#preset-dsl').evaluate(el => el.getBoundingClientRect().right <= window.innerWidth));
  assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
  await page.screenshot({path: process.env.ANAROGUE_PRESET_SCREENSHOT || '/tmp/anarogue-presets-mobile.png', fullPage: true});
  page.once('dialog', dialog => dialog.accept()); await page.click('#preset-delete');
  await page.waitForFunction(() => document.querySelector('#preset-status').textContent.startsWith('Preset deleted'));
  assert.equal((await (await fetch(`${base}/api/database`)).json()).runs, 1);
  assert.deepEqual(errors, []);
  console.log('Viewer presets passed: real Rust/API/SQLite, preflight, save/reload, Unicode, update/conflict, duplicate, AutoRun, launch snapshot, deletion and mobile layout.');
} finally {
  if (browser) await browser.close(); vite?.kill('SIGTERM'); python.kill('SIGTERM');
  await once(python, 'exit'); rmSync(directory, {recursive:true, force:true});
}
