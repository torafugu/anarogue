import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {chromium} from 'playwright';

const reference=readFileSync(new URL('../../examples/reference-v8/aggressive-seed-424242.jsonl',import.meta.url),'utf8').trim().split('\n').map(JSON.parse);
const eventsFor=(name,index)=>reference.map(event=>{
 const value=structuredClone(event);value.run_id=name;
 if(index){value.turn+=5;if(value.player_state){value.player_state.hp=9;value.player_state.gold=30;value.player_state.level=5;value.player_state.pos={x:6,y:8};value.player_state.score=90;}}
 if(value.event==='run_start')value.details.goal_policy={enemy_weight:4,item_weight:index?4:1,stairs_weight:1,temperature:8};
 return value;
});
const events={a:eventsFor('inspection-a',0),b:eventsFor('inspection-b',1)};
const runs=['a','b'].map((id,index)=>({id,run_id:`inspection-${id}`,strategy_id:'aggressive_v1',scenario_seed:424242,scenario_id:'scenario-424242',simulation_version:8,schema_version:8,code_revision:'inspection-test',goal_policy:events[id][0].details.goal_policy,status:'cleared',score:index?90:20,level:index?5:2,turns:index?113:108,max_depth:5,started_at:'test',execution_settings:{max_turns:5000}}));
let failKey=null,slowKey=null,failMeans=false;
const meanQueries=[];
const api=createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost');
 let result;
 if(url.pathname==='/api/runs')result={runs,total:runs.length};
 else if(url.pathname==='/api/stats')result={groups:runs.map(run=>({...run,runs:1,finished:1,cleared:1,clear_rate:1,mean_score:run.score,mean_depth:5,mean_turns:run.turns}))};
 else if(url.pathname==='/api/mean-metrics'){
  meanQueries.push(url.searchParams);
  if(failMeans){res.writeHead(500,{'Content-Type':'application/json'});res.end('{"error":"fixture averages failure"}');return;}
  const selected=runs.filter(run=>!url.searchParams.has('item_weight')||run.goal_policy.item_weight===Number(url.searchParams.get('item_weight')));
  const mean=key=>selected.length?selected.reduce((sum,run)=>sum+run[key],0)/selected.length:null;
  result={runs:selected.length,unfinished:0,means:Object.fromEntries(['score','level','turns','max_depth','kills','damage_taken','gold','decisions','potions_picked_up','potions_used','hp_healed'].map(key=>[key,mean(key)]))};
 }
 else if(url.pathname==='/api/weight-analysis')result={cohorts:[],excluded_runs:0};
 else {
  const match=url.pathname.match(/^\/api\/runs\/(a|b)\/events$/);if(!match){res.writeHead(404);res.end('{}');return;}
  if(match[1]===slowKey)await new Promise(resolve=>setTimeout(resolve,400));
  if(match[1]===failKey){res.writeHead(500,{'Content-Type':'application/json'});res.end('{"error":"fixture fetch failure"}');return;}
  result={events:events[match[1]]};
 }
 res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(result));
});
api.listen(0,'127.0.0.1');await once(api,'listening');
const apiPort=api.address().port;
// Let the OS choose Vite's port too, avoiding collisions with local dev servers.
const vite=createServer();vite.listen(0,'127.0.0.1');await once(vite,'listening');const port=vite.address().port;await new Promise(resolve=>vite.close(resolve));
const child=spawn(process.execPath,['node_modules/vite/bin/vite.js','--host','127.0.0.1','--port',String(port),'--strictPort'],{cwd:new URL('..',import.meta.url),env:{...process.env,ANAROGUE_RUN_API_URL:`http://127.0.0.1:${apiPort}`},stdio:'ignore'});
let browser;
try{
 for(let attempt=0;attempt<100;attempt++){try{const r=await fetch(`http://127.0.0.1:${port}`);if(r.ok)break;}catch{}await new Promise(resolve=>setTimeout(resolve,50));}
 browser=await chromium.launch({headless:true,...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE?{executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE}:{})});
 const page=await browser.newPage({permissions:['clipboard-read','clipboard-write']});page.setDefaultTimeout(10000);const errors=[];page.on('pageerror',error=>errors.push(error.message));
 await page.goto(`http://127.0.0.1:${port}`);await page.waitForSelector('.rank-checkbox');
 await page.waitForFunction(()=>document.querySelector('#mean-metrics-status').textContent.includes('2 matching Runs'));
 assert.equal(await page.locator('#mean-metrics .metric-card').count(),11);
 assert.equal(await page.locator('#mean-metrics strong').first().textContent(),'55.00');
 await page.click('#copy-means-csv');await page.waitForFunction(()=>document.querySelector('#mean-copy-status').textContent.includes('CSV copied'));
 const csv=await page.evaluate(()=>navigator.clipboard.readText());
 assert(csv.startsWith('Filters,Runs,Finished,Unfinished,Score,Level,Turns,Depth,Kills,Damage,Gold,Decisions,Potions found,Potions used,Healing\r\n'));
 assert(csv.includes('Strategy=All; Result=All; Seed=All; Enemy=All; Treasure=All; Stairs=All; Temperature=All,2,2,0,55,3.5,110.5,'));
 await page.evaluate(()=>Object.defineProperty(navigator.clipboard,'writeText',{configurable:true,value:()=>Promise.reject(new Error('clipboard denied'))}));
 await page.click('#copy-means-tsv');await page.waitForFunction(()=>document.querySelector('#mean-copy-status').textContent.includes('Copy failed: clipboard denied'));
 await page.evaluate(()=>delete navigator.clipboard.writeText);

 assert(await page.evaluate(()=>{const metrics=document.querySelector('#mean-metrics');return !!(document.querySelector('#weight-analysis').compareDocumentPosition(metrics)&Node.DOCUMENT_POSITION_FOLLOWING)&&!!(metrics.compareDocumentPosition(document.querySelector('#catalog-ranking'))&Node.DOCUMENT_POSITION_FOLLOWING);}));
 const filter=async value=>{await page.fill('#catalog-item',value);await page.locator('#catalog-item').press('Tab');};
 await filter('4');await page.waitForFunction(()=>document.querySelector('#mean-metrics-status').textContent.includes('1 matching Runs'));
 assert.equal(await page.locator('#mean-metrics strong').first().textContent(),'90.00');assert.equal(meanQueries.at(-1).get('item_weight'),'4');
 await page.click('#copy-means-tsv');await page.waitForFunction(()=>document.querySelector('#mean-copy-status').textContent.includes('TSV copied'));
 const tsv=await page.evaluate(()=>navigator.clipboard.readText());
 assert(tsv.startsWith('Filters\tRuns\tFinished\tUnfinished\tScore\t'));
 assert(tsv.includes('Treasure=4; Stairs=All; Temperature=All\t1\t1\t0\t90\t5\t113\t'));

 await filter('3');await page.waitForFunction(()=>document.querySelector('#mean-metrics-status').textContent.includes('0 matching Runs'));
 assert.equal(await page.locator('#mean-metrics strong').first().textContent(),'—');
 await page.click('#copy-means-tsv');await page.waitForFunction(()=>document.querySelector('#mean-copy-status').textContent.includes('TSV copied'));
 const emptyCopy=await page.evaluate(()=>navigator.clipboard.readText());assert(emptyCopy.split('\r\n')[1].endsWith('\t0\t0\t0'+'\t'.repeat(11)));

 failMeans=true;await filter('1');await page.waitForFunction(()=>document.querySelector('#mean-metrics-status').textContent.includes('Averages unavailable'));
 assert.equal(await page.locator('#mean-metrics').textContent(),'');
 assert(await page.locator('#copy-means-csv').isDisabled());assert(await page.locator('#copy-means-tsv').isDisabled());

 failMeans=false;await filter('');await page.waitForFunction(()=>document.querySelector('#mean-metrics-status').textContent.includes('2 matching Runs'));
 await page.setViewportSize({width:390,height:844});
 assert(await page.locator('#mean-metrics').evaluate(node=>node.getBoundingClientRect().right<=window.innerWidth));
 await page.setViewportSize({width:1280,height:800});
 for(const checkbox of await page.locator('.rank-checkbox').all())await checkbox.check();
 await page.click('#compare-selected');await page.waitForSelector('[data-stored-run="a"]');
 const inspect=async id=>{await page.locator(`[data-stored-run="${id}"]`).click();await page.waitForFunction(id=>document.querySelector('#viewer').dataset.runKey===id&&!document.querySelector('#viewer').hidden,id);};
 const snapshot=async()=>page.evaluate(()=>Object.fromEntries(['metrics','hp-chart','route-map','timeline','detail-panel'].map(id=>[id,document.getElementById(id).innerHTML])));
 await inspect('a');const first=await snapshot();
 await page.locator('[data-filter="combat"]').click();await page.fill('#event-search','no-such-event');
 await inspect('b');const second=await snapshot();
 for(const field of Object.keys(first))assert.notEqual(second[field],first[field],`${field} must change with the selected Run`);
 assert.equal(await page.locator('#event-search').inputValue(),'');assert(await page.locator('[data-filter="all"]').evaluate(node=>node.classList.contains('active')));
 assert((await page.locator('#inspection-policy').textContent()).includes('"item_weight":4'));
 slowKey='a';await page.locator('[data-stored-run="a"]').click();await page.locator('[data-stored-run="b"]').click();
 await page.waitForFunction(()=>document.querySelector('#viewer').dataset.runKey==='b'&&!document.querySelector('#viewer').hidden);
 await page.waitForTimeout(500);assert.equal(await page.locator('#run-title').textContent(),'inspection-b');slowKey=null;
 failKey='a';await page.locator('[data-stored-run="a"]').click();await page.waitForFunction(()=>!document.querySelector('#inspection-retry').hidden);
 assert(await page.locator('#viewer').isHidden());assert.equal(await page.locator('#metrics').textContent(),'');assert.equal(await page.locator('#run-title').textContent(),'');
 failKey=null;await page.click('#inspection-retry');await page.waitForFunction(()=>document.querySelector('#viewer').dataset.runKey==='a'&&!document.querySelector('#viewer').hidden);
 const restored=await snapshot();for(const field of Object.keys(first))assert.equal(restored[field],first[field],`${field} returns to Run A`);
 assert.deepEqual(errors,[]);
 console.log('Clipboard export passed: native CSV/TSV clipboard, filter snapshot, counts, empty export, denied access and failed API state. Inspection regression passed: all metrics/HP/route/events/details change A→B→A; filters reset, latest click wins and failed loads clear stale content and retry.');
}finally{if(browser)await browser.close();child.kill('SIGTERM');api.closeAllConnections();await new Promise(resolve=>api.close(resolve));}
