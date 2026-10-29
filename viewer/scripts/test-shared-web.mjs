import assert from 'node:assert/strict';
import {mkdtempSync, rmSync, existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {chromium} from 'playwright';

assert(existsSync(new URL('../public/replay/index.wasm', import.meta.url)), 'Export the Godot Web Replay before this test');
const directory = mkdtempSync(join(tmpdir(), 'anarogue-shared-web-'));
const python = spawn(process.env.PYTHON || 'python3', ['-u', '-c', `
import os, sys, time
sys.path.insert(0, 'tools')
from run_jobs import RunJobs
from run_store import RunStore, make_server
from run_presets import RunPresets
store = RunStore(sys.argv[1])
jobs = RunJobs(store, os.environ['ANAROGUE_RUST_BINARY'])
simulate = jobs.simulate
def slow(settings):
    time.sleep(.15)
    return simulate(settings)
jobs.simulate = slow
RunPresets(store).save({'name':'Shared sweep', 'kind':'batch', 'settings':{'max_turns':4, 'enemy_weights':[0,1,2], 'item_weights':[0,1,2], 'stairs_weights':[0,1,2]}}, jobs)
server = make_server(store, port=0, jobs=jobs)
print(server.server_port, flush=True)
server.serve_forever()
`, join(directory, 'runs.sqlite3')], {cwd:new URL('../..', import.meta.url), stdio:['ignore','pipe','inherit']});
let vite, browser;
try {
  const [output] = await once(python.stdout, 'data'); const apiPort = Number(output.toString().trim()); assert(apiPort > 0);
  const reserve = createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening'); const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
  vite = spawn(process.execPath, ['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port',String(port),'--strictPort'], {cwd:new URL('..', import.meta.url),env:{...process.env,ANAROGUE_RUN_API_URL:`http://127.0.0.1:${apiPort}`},stdio:'ignore'});
  const base = `http://127.0.0.1:${port}`;
  for (let i=0;i<100;i++) {try {if ((await fetch(base)).ok) break;} catch {} await new Promise(resolve=>setTimeout(resolve,50));}
  browser = await chromium.launch({headless:true,args:['--use-angle=swiftshader','--enable-unsafe-swiftshader'],...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE?{executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE}:{})});
  const desktop = await browser.newPage({viewport:{width:1400,height:1000}});
  const phone = await browser.newPage({viewport:{width:390,height:844}});
  const errors=[]; for (const page of [desktop,phone]) {page.setDefaultTimeout(30000);page.on('pageerror',error=>errors.push(error.message));page.on('console',message=>{if(message.type()==='error') console.error(message.text());});}
  await Promise.all([desktop.goto(base),phone.goto(base)]);
  await desktop.click('#run-presets summary');
  await desktop.waitForFunction(()=>!document.querySelector('#preset-select').disabled);
  const preset = (await (await fetch(`${base}/api/presets`)).json()).presets[0];
  await desktop.selectOption('#preset-select',preset.id);
  assert(await desktop.locator('#preset-run').isEnabled());
  await desktop.fill('#preset-name','Unsaved change'); assert(await desktop.locator('#preset-run').isDisabled());
  desktop.once('dialog', dialog=>dialog.accept());await desktop.click('#preset-reload');
  await desktop.waitForFunction(()=>!document.querySelector('#preset-run').disabled);
  await desktop.click('#preset-run');
  await desktop.waitForFunction(()=>document.querySelector('#preset-status').textContent.startsWith('Started'));
  await phone.waitForFunction(()=>document.querySelector('.job-card')?.textContent.includes('saved'));
  const jobId = await phone.locator('.job-card').getAttribute('data-job-id');
  await phone.waitForFunction(()=>document.querySelector('.job-card .job-progress')?.textContent.match(/[1-9]\d*\/52 saved/));
  await phone.getByRole('button',{name:'Stop after current Run',exact:true}).click();
  await phone.waitForFunction(()=>document.querySelector('.job-progress')?.textContent.startsWith('cancelled'));
  const job = await (await fetch(`${base}/api/jobs/${jobId}`)).json();
  assert(job.completed>0 && job.completed<52); assert.equal(job.status,'cancelled');
  await desktop.waitForFunction(()=>document.querySelector('.job-progress')?.textContent.startsWith('cancelled'));
  const results = await (await fetch(`${base}/api/runs?job_id=${jobId}`)).json();assert.equal(results.total,job.completed);
  await desktop.getByRole('button',{name:'Replay latest Run',exact:true}).click();
  await desktop.waitForSelector('#web-replay-dialog iframe');
  const frame = desktop.frame({url:/\/replay\/index.html/}); assert(frame);
  await frame.waitForFunction(id=>window.anaReplayState?.run_id===id,job.run_id,{timeout:60000});
  assert.equal((await frame.evaluate(()=>window.anaReplayState)).turn,0);
  await frame.locator('#canvas').click();
  await frame.locator('#canvas').press('ArrowRight');
  await frame.waitForFunction(()=>window.anaReplayState.turn>=1);
  await desktop.locator('.web-replay-frame').screenshot({path:'/tmp/anarogue-web-replay.png'});
  await frame.goto(`${base}/replay/index.html?run=${job.run_id}&turn=2`);
  await frame.waitForFunction(()=>window.anaReplayState?.turn===2,{},{timeout:60000});
  await desktop.locator('.web-replay-bar button').click();assert.equal(await desktop.locator('#web-replay-dialog iframe').count(),0);
  await desktop.getByRole('button',{name:'Inspect latest Run',exact:true}).click();
  await desktop.waitForFunction(id=>document.querySelector('#viewer').dataset.runKey===id,job.run_id);
  await desktop.locator('#run-inspection').evaluate(el=>el.open=true);
  const events = (await (await fetch(`${base}/api/runs/${job.run_id}/events`)).json()).events;
  const selectedEvent = events.find(event=>event.turn===2);
  await desktop.click(`[data-sequence="${selectedEvent.sequence}"]`);
  await desktop.click('#open-web-replay');
  await desktop.waitForSelector('#web-replay-dialog iframe');
  const selectedFrame = desktop.frame({url:/\/replay\/index.html/});
  await selectedFrame.waitForFunction(()=>window.anaReplayState?.turn===2,{},{timeout:60000});
  await desktop.locator('.web-replay-bar button').click();
  await desktop.route('**/replay/index.html',route=>route.fulfill({status:404,body:'Unavailable'}));
  await desktop.click('#open-web-replay');
  await desktop.waitForFunction(()=>document.querySelector('#web-replay-dialog [role=status]').textContent.includes('unavailable'));
  assert.equal(await desktop.locator('#web-replay-dialog iframe').count(),0);
  await desktop.locator('.web-replay-bar button').click();
  await desktop.unroute('**/replay/index.html');
  await phone.reload(); await phone.waitForFunction(()=>document.querySelector('.job-progress')?.textContent.startsWith('cancelled'));
  assert.equal(await phone.locator('.job-card').getAttribute('data-job-id'),jobId);
  assert(await phone.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  assert.deepEqual(errors,[]);
  console.log('Shared Web passed: Viewer launch, independent mobile progress/cancel, durable history, job results, actual Godot WASM loading/stepping/seek, lazy unload and responsive UI.');
} finally {
  if (browser) await browser.close(); vite?.kill('SIGTERM'); python.kill('SIGTERM');await once(python,'exit');rmSync(directory,{recursive:true,force:true});
}
