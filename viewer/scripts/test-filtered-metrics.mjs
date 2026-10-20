import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import ts from 'typescript';

const source=readFileSync(new URL('../src/filtered-metrics.ts',import.meta.url),'utf8');
const js=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {meanMetricFields,meanMetricsDelimited}=await import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
const means=Object.fromEntries(meanMetricFields.map(([,key],index)=>[key,index===0?1/3:index]));
const data={runs:105,unfinished:5,means};
const filters=new URLSearchParams({strategy_id:'aggressive_v1',status:'cleared',scenario_seed:'42',enemy_weight:'0',item_weight:'4',stairs_weight:'2',temperature:'8'});
const conditions=['aggressive_v1','cleared','42','0','4','2','8'];
for(const format of ['csv','tsv']){
 const delimiter=format==='csv'?',':'\t';
 const rows=meanMetricsDelimited(data,filters,format).trimEnd().split('\r\n').map(row=>row.split(delimiter));
 assert.equal(rows.length,2);
 const noHeader=meanMetricsDelimited(data,filters,format,false);
 assert.equal(noHeader,meanMetricsDelimited(data,filters,format).split('\r\n').slice(1).join('\r\n'));
 assert.equal(noHeader.split('\r\n').length,2,'one data row and trailing newline');
 assert.equal(meanMetricsDelimited(data,filters,format,true),meanMetricsDelimited(data,filters,format));
 assert.deepEqual(rows[0],['Strategy','Result','Seed','Enemy','Treasure','Stairs','Temperature','Runs','Finished','Unfinished',...meanMetricFields.map(([label])=>label)]);
 assert.deepEqual(rows[1],[...conditions,'105','100','5',...Object.values(means).map(String)]);
 assert(rows[1].includes('0.3333333333333333'),'avoid rounding exported means to display precision');
}
const empty=meanMetricsDelimited({runs:0,unfinished:0,means:{}},new URLSearchParams(),'csv').split('\r\n')[1].split(',');
assert.deepEqual(empty.slice(0,7),Array(7).fill('All'));
assert.equal(empty.length,21,'7 filters + 3 counts + 11 means');
assert.deepEqual(empty.slice(7),['0','0','0',...Array(11).fill('')]);
for(const [format,special] of [['csv','a,"b"\nc'],['tsv','a\t"b"\nc']]){
 const text=meanMetricsDelimited(data,new URLSearchParams({strategy_id:special}),format);
 assert(text.split('\r\n')[1].startsWith(`"${special.replaceAll('"','""')}"${format==='csv'?',':'\t'}All`),'quote each filter cell and escape embedded quotes');
}
console.log('Filtered metrics export passed: header + one row, all filters including zero, 11 ordered means, counts, full precision, empty values and CSV/TSV quoting.');
