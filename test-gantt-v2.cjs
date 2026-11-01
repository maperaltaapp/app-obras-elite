const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const html=fs.readFileSync(__dirname+'/index.html','utf8'),script=html.match(/<script>([\s\S]*)<\/script>/)[1],map=new Map();
function el(id){if(!map.has(id))map.set(id,{id,innerHTML:'',textContent:'',value:'',disabled:false,classList:{add(){},remove(){},toggle(){}},showModal(){},close(){},remove(){map.delete(id)},focus(){},addEventListener(){}});return map.get(id)}
const ctx=vm.createContext({console,structuredClone,Date,Map,URL,URLSearchParams,crypto,localStorage:{getItem(){return null}},document:{getElementById:el,querySelectorAll(){return []},querySelector(){return null},createElement(){return el('taskDialog')},body:{appendChild(){}}},navigator:{},location:{search:'',pathname:'/'},history:{replaceState(){}},setTimeout,clearTimeout});ctx.window=ctx;vm.runInContext(script,ctx);const run=s=>vm.runInContext(s,ctx);

run("NATIVE_WORKS=[{id:'w1',name:'Prueba',stages:[]}];OWN_TASKS=[];CONTRACTORS=[{id:'p1',name:'Proveedor',trade:'Electricidad',kind:'subcontractor'}];WORK_CONTRACTORS=[];openPlanningWorks()");
assert.equal(run('selectedSection'),'gantts');assert(!el('content').innerHTML.includes('+ Tarea'));
run("tasks()");assert.equal((el('content').innerHTML.match(/>\+ Tarea<\/button>/g)||[]).length,1);
run("openTaskForDay('2026-11-10')");assert.equal(el('ownDue').value,'2026-11-10T09:00');assert(el('taskDialog').innerHTML.includes('Nueva tarea'));
const month=run('monthView([])'),week=run('weekView([])');assert(month.includes('calendarDayTap(event'));assert(month.includes('aria-label="Crear tarea el '));assert(week.includes('week-create'));
run("openContractors('w1');editWorkContractor()");const form=el('taskDialog').innerHTML;assert(form.includes('id="controlProvider"'));assert(!form.includes('id="controlName"'));assert(!form.includes('id="controlScope"'));
ctx.payload=null;ctx.capture=o=>{ctx.payload=JSON.parse(o.body);return [{...ctx.payload}]};run("eliteRequest=async(u,o)=>capture(o);refreshControls=async()=>{}");el('controlProvider').value='p1';el('controlRowWork').value='w1';el('controlEntry').value='';el('controlNotes').value='';
(async()=>{await el('controlRowForm').onsubmit({preventDefault(){}});await new Promise(r=>setTimeout(r,0));assert.equal(ctx.payload.contractor_id,'p1');assert.equal(ctx.payload.scope,'Electricidad');
assert.equal(run("followCost([{pricing:'units',unit:'day',quantity:3,rate:180}]).valued"),540);assert.equal(run("followCost([{unit:'hour',quantity:3,duration:8,rate:25}]).valued"),600);assert.equal(run("followCost([laborUnits({unit:'hour',quantity:3,duration:8,rate:25})]).valued"),600);
console.log('PASS: global selection; task-only create button; calendar day prefill; registry-only control selection; direct units pricing; legacy cost preservation.');})().catch(e=>{console.error(e);process.exitCode=1});
run(`NATIVE_WORKS=[{id:'w1',name:'Prensas',stages:[]},{id:'w2',name:'Archivada',archived_at:'2026-01-01',stages:[]}];OWN_TASKS=[
{id:'a',title:'Urgente hoy',work_id:'w1',category:'work',due_at:'2026-10-31T10:00:00Z',priority:'urgent'},
{id:'b',title:'Normal hoy',work_id:'w1',category:'work',due_at:'2026-10-31T11:00:00Z'},
{id:'c',title:'Atrasada',work_id:'w2',category:'work',due_at:'2026-10-30T11:00:00Z'},
{id:'d',title:'Futura',category:'personal',due_at:'2026-11-01T11:00:00Z'},
{id:'e',title:'Sin fecha',work_id:'w1',category:'work'},
{id:'f',title:'Completa',work_id:'w1',category:'work',completed:true},
{id:'g',title:'Archivada',work_id:'w2',category:'work',deleted_at:'2026-01-01'},
{id:'h',title:'Control sin fecha',work_id:'w1',category:'work',control_id:'control'}];madridDay=(value=new Date())=>value===undefined?'2026-10-31':new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Madrid'}).format(new Date(value));tasks('all')`);
assert.equal(run('homeCards().length'),8);
assert.equal(run("homeGroup(homeCards()[0],'2026-10-31')"),'urgent');
assert.equal(run("homeGroup(homeCards()[1],'2026-10-31')"),'today');
assert.equal(run("homeGroup(homeCards()[2],'2026-10-31')"),'overdue');
assert.equal(run("homeGroup(homeCards()[3],'2026-10-31')"),'future');
assert.equal(run("homeGroup(homeCards()[4],'2026-10-31')"),'undated');
assert.equal((el('taskResults').innerHTML.match(/class="home-row"/g)||[]).length,6);
assert(!el('taskResults').innerHTML.includes('<details'));
assert.equal(el('home-done-count').textContent,1);assert.equal(el('home-archived-count').textContent,1);
run("taskQuery='prensas';renderTaskResults()");assert.equal((el('taskResults').innerHTML.match(/class="home-row"/g)||[]).length,4);
run("taskQuery='';tasks('archived')");assert(el('taskResults').innerHTML.includes("openTaskForm('g')"));
run("tasks('done')");assert(el('taskResults').innerHTML.includes("openTaskForm('f')"));
assert.equal(run("homeGroup({due:'2026-10-30T23:30:00Z',priority:'urgent'},'2026-10-31')"),'urgent');
console.log('PASS: all records conserved; five date categories; Madrid midnight; search; completed/archive access; no collapsed tasks.');
run(`var fixture=[{id:'a',name:'A',start:'2026-10-01',end:'2026-10-03',weight:40,depends_on:[],budget:300,observations:[{date:'2026-10-02',percent:20}]},{id:'b',name:'B',start:'2026-10-04',end:'2026-10-06',weight:30,depends_on:['a'],lag_days:0,budget:600},{id:'c',name:'C',start:'2026-10-07',end:'2026-10-08',weight:30,depends_on:['a','b'],lag_days:0,budget:100,economic_observations:[{date:'2026-10-07',amount:80}]}]`);
assert.equal(run("scheduleLinked(fixture)[2].start"),'2026-10-07');
run("var changed=structuredClone(fixture);changed[0].start='2026-09-29';changed[0].end='2026-10-01'");
assert.equal(run('scheduleLinked(changed)[2].start'),'2026-10-05');
assert.equal(run('scheduleLinked(changed)[0].observations[0].date'),'2026-10-02');
run("changed[0].depends_on=['c']");assert.throws(()=>run('scheduleLinked(changed)'),/ciclo/);
assert.equal(run("economicValue(fixture,'2026-10-08')"),1000);assert.equal(run("economicValue(fixture,'2026-10-06',true)"),null);assert.equal(run("economicValue(fixture,'2026-10-07',true)"),80);
run('var missing=structuredClone(fixture);missing[0].budget=null');assert.equal(run("economicValue(missing,'2026-10-08')"),null);
assert(run('renderGantt({phases:fixture,baseline:fixture})').includes('marker-end'));assert(run('renderEconomicCurve({phases:fixture})').includes('Avance económico'));
console.log('PASS: multiple predecessors, earlier rescheduling, cycles, measurement preservation, monetary curves, missing budgets.');
run(`var branch=[{id:'a',name:'A',start:'2026-10-01',end:'2026-10-03',weight:25,depends_on:[]},{id:'b',name:'B',start:'2026-10-01',end:'2026-10-05',weight:25,depends_on:[]},{id:'c',name:'C',start:'2026-10-06',end:'2026-10-07',weight:50,depends_on:['a','b'],lag_days:0}];`);
assert.equal(run("gCritical(branch).get('a')"),2);assert.equal(run("gCritical(branch).get('b')"),0);assert.equal(run("gCritical(branch).get('c')"),0);
run("var marker={id:'m',name:'Entrega',start:'2026-10-08',end:'2026-10-08',weight:0,milestone:true,depends_on:['c']};branch.push(marker)");assert.equal(run('ElitePlanning.validate(branch).length'),4);
console.log('PASS: critical path with parallel branches, float and zero-weight milestone.');
