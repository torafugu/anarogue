import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import ts from "typescript";

const source = readFileSync(new URL("../src/weight-analysis.ts", import.meta.url), "utf8");
const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext } }).outputText;
const { analysisMarkup, cohortLabel, updateWeightAnalysis } = await import(`data:text/javascript;base64,${Buffer.from(js).toString("base64")}`);
const cohort = {
  id: "cohort-a", conditions: {scenario_seed:42, scenario_id:'<script>alert("x")</script>', simulation_version:8, schema_version:8, code_revision:"test", max_turns:null, other_policy:{temperature:8}},
  strategies: ["aggressive_v1", "cautious_v1"].map(strategy_id => ({strategy_id, n:3, unfinished:1, axes:Object.fromEntries(["enemy_weight","item_weight","stairs_weight"].map((name,index)=>[name,{n:3,pearson_r:index ? null : 1,undefined_reason:index ? "constant_weight" : null,values:[{weight:0,n:1,mean_score:0,unfinished:0},{weight:2,n:2,mean_score:10,unfinished:1}]}]))}))
};
const markup = analysisMarkup(cohort);
assert.equal((markup.match(/class="weight-chart"/g) ?? []).length, 6);
assert.equal((markup.match(/Pearson r/g) ?? []).length, 6);
assert(markup.includes("1.000") && markup.includes("Weight has no variation"));
assert(markup.includes("Max turns were not recorded") && markup.includes("Values and counts"));
assert(!markup.includes("NaN") && !markup.includes("Infinity"));
assert(cohortLabel(cohort).includes("seed 42"));
const select = {value:"cohort-a",innerHTML:"",disabled:false};
const content = {innerHTML:""}; const status = {textContent:""};
const root = {querySelector:selector=>({"#weight-cohort":select,"#weight-analysis-content":content,"#weight-analysis-status":status})[selector]};
updateWeightAnalysis({cohorts:[cohort],excluded_runs:2},root);
assert(!select.innerHTML.includes("<script>") && select.innerHTML.includes("&lt;script&gt;"));
assert.equal(select.value,"cohort-a");
assert(status.textContent.includes("2 Runs excluded"));
updateWeightAnalysis({cohorts:[],excluded_runs:0},root);
assert(content.innerHTML.includes("No Runs") && select.disabled);
console.log("Weight analysis rendering passed: six charts/correlations, undefined cases, exact tables, escaping, selection and empty state.");
