import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import ts from "typescript";
const source=readFileSync(new URL('../src/rank-comparison.ts',import.meta.url),'utf8');
// The helper's default transport is replaced by a deterministic paged fixture.
const js=ts.transpileModule(source.replace(/import .* from "\.\/catalog.ts";/,'const api = () => { throw new Error("Use test transport"); };'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {policyGroupKey,comparisonConditions,loadRankRuns}=await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
const run={id:'a',run_id:'a',strategy_id:'aggressive_v1',simulation_version:8,schema_version:8,code_revision:'x',goal_policy:{enemy_weight:1,item_weight:2,stairs_weight:3},scenario_seed:42,scenario_id:'scenario-42',execution_settings:{max_turns:100},score:10};
assert.equal(policyGroupKey(run),policyGroupKey({...run,goal_policy:{stairs_weight:3,item_weight:2,enemy_weight:1}}));
assert.notEqual(policyGroupKey(run),policyGroupKey({...run,strategy_id:'cautious_v1'}));
const groups=comparisonConditions([run,{...run,id:'b',scenario_seed:43},{...run,id:'c',code_revision:'y'},{...run,id:'d',execution_settings:undefined},{...run,id:'e',scenario_seed:null}]);
assert.equal(groups.length,4);
const rows=Array.from({length:620},(_,index)=>({...run,id:String(index),strategy_id:index===619?'aggressive_v1':'cautious_v1'}));
const offsets=[];
const result=await loadRankRuns(new URLSearchParams({enemy_weight:'1'}),new Set([policyGroupKey(run)]),async params=>{
 assert.equal(params.get('enemy_weight'),'1'); assert.equal(params.get('limit'),'500');
 const offset=Number(params.get('offset'));offsets.push(offset);return {runs:rows.slice(offset,offset+500),total:rows.length};
});
assert.deepEqual(offsets,[0,500]);assert.equal(result.length,1);assert.equal(result[0].id,'619');
assert.deepEqual(await loadRankRuns(new URLSearchParams(),new Set(),async()=>({runs:[],total:0})),[]);
console.log('Rank comparison passed: stable policy identities, compatible conditions and selected Runs beyond 500-row pagination.');
