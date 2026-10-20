import assert from 'node:assert/strict';
import {mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {chromium} from 'playwright';

const directory=mkdtempSync(join(tmpdir(),'anarogue-clear-'));
const python=spawn(process.env.PYTHON || 'python3',['-u','-c',`
import sys
sys.path.insert(0, 'tools')
from run_store import RunStore, make_server
from pathlib import Path
store=RunStore(sys.argv[1])
source=Path('examples/reference-v8/aggressive-seed-424242.jsonl').read_text()
store.import_text(source)
import json
events=[json.loads(line) for line in source.splitlines()]
for event in events:
    event['run_id']='second-clear-test-run'
    event['scenario_seed']=99
store.import_text('\\n'.join(json.dumps(event) for event in events))
server=make_server(store, port=0)
print(server.server_port, flush=True)
server.serve_forever()
`,join(directory,'runs.sqlite3')],{cwd:new URL('../..',import.meta.url),stdio:['ignore','pipe','inherit']});
let vite,browser;
try {
 const [output]=await once(python.stdout,'data');const apiPort=Number(output.toString().trim());assert(apiPort>0);
 const reserve=createServer();reserve.listen(0,'127.0.0.1');await once(reserve,'listening');const port=reserve.address().port;await new Promise(resolve=>reserve.close(resolve));
 vite=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port',String(port),'--strictPort'],{cwd:new URL('..',import.meta.url),env:{...process.env,ANAROGUE_RUN_API_URL:`http://127.0.0.1:${apiPort}`},stdio:'ignore'});
 const base=`http://127.0.0.1:${port}`;
 for(let i=0;i<100;i++){try{if((await fetch(base)).ok)break;}catch{}await new Promise(resolve=>setTimeout(resolve,50));}
 browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE?{executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE}:{})});
 const page=await browser.newPage();page.setDefaultTimeout(10000);const errors=[];page.on('pageerror',error=>errors.push(error.message));
 await page.goto(base);await page.waitForFunction(()=>document.querySelector('#catalog-status').textContent.startsWith('2 Runs'));
 await page.check('.rank-checkbox');
 await page.fill('#catalog-seed','424242');await page.locator('#catalog-seed').dispatchEvent('change');
 await page.waitForFunction(()=>document.querySelector('#catalog-status').textContent.startsWith('1 Runs'));
 await page.click('#delete-all-runs');await page.waitForFunction(()=>document.querySelector('#delete-counts').textContent.startsWith('2 Runs'));
 assert(await page.locator('#delete-confirm').isDisabled());
 await page.fill('#delete-confirmation','delete');assert(await page.locator('#delete-confirm').isDisabled());
 await page.click('#delete-cancel');assert.equal((await (await fetch(`${base}/api/database`)).json()).runs,2);
 await page.click('#delete-all-runs');await page.waitForFunction(()=>document.querySelector('#delete-counts').textContent.startsWith('2 Runs'));
 await page.fill('#delete-confirmation','DELETE');
 await page.route('**/api/database/clear',route=>route.fulfill({status:409,contentType:'application/json',body:JSON.stringify({error:'A Run is active'})}));
 await page.click('#delete-confirm');await page.waitForFunction(()=>document.querySelector('#delete-error').textContent.includes('A Run is active'));
 assert(await page.locator('#delete-dialog').isVisible());assert(await page.locator('#delete-confirm').isDisabled());
 assert.equal((await (await fetch(`${base}/api/database`)).json()).runs,2);
 await page.click('#delete-cancel');await page.unroute('**/api/database/clear');
 await page.click('#delete-all-runs');await page.waitForFunction(()=>document.querySelector('#delete-counts').textContent.startsWith('2 Runs'));
 await page.fill('#delete-confirmation','DELETE');await page.click('#delete-confirm');
 await page.waitForFunction(()=>!document.querySelector('#delete-dialog').open&&document.querySelector('#delete-status').textContent.startsWith('Deleted 2 Runs')).catch(async error=>{console.error(await page.locator('#delete-error').textContent(),errors);throw error;});
 await page.waitForFunction(()=>document.querySelector('#catalog-status').textContent.startsWith('0 Runs'));
 assert.deepEqual(await (await fetch(`${base}/api/database`)).json(),{runs:0,events:0,watch_enabled:false});
 assert.equal(await page.locator('.rank-checkbox').count(),0);
 assert.equal(await page.locator('#rank-selection-count').textContent(),'0 selected');
 assert(await page.locator('#viewer').isHidden());assert.equal(await page.locator('#metrics').textContent(),'');
 assert.equal(await page.locator('#catalog-run').textContent(),'No Runs yet');
 await page.setViewportSize({width:390,height:844});await page.click('#delete-all-runs');
 await page.waitForFunction(()=>document.querySelector('#delete-counts').textContent.startsWith('0 Runs'));
 assert(await page.locator('#delete-dialog').evaluate(el=>el.getBoundingClientRect().width<=window.innerWidth));
 await page.keyboard.press('Escape');assert(await page.locator('#delete-dialog').isHidden());
 assert.deepEqual(errors,[]);
 console.log('Clear Runs passed: real API/SQLite, unfiltered totals, cancel, typed confirmation, conflict/retry, empty catalogue/selection/inspection and mobile dialog.');
} finally {if(browser)await browser.close();vite?.kill('SIGTERM');python.kill('SIGTERM');await once(python,'exit');rmSync(directory,{recursive:true,force:true});}
