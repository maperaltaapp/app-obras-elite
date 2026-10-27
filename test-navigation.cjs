const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const html=fs.readFileSync(__dirname+'/index.html','utf8'),script=html.match(/<script>([\s\S]*)<\/script>/)[1],map=new Map();
function el(id){if(!map.has(id))map.set(id,{id,innerHTML:'',textContent:'',value:'',disabled:false,classList:{add(){},remove(){},toggle(){}},showModal(){},close(){},remove(){map.delete(id)},focus(){},addEventListener(){}});return map.get(id)}
const ctx=vm.createContext({console,Date,Map,URL,URLSearchParams,crypto,localStorage:{getItem(){return null}},document:{getElementById:el,querySelectorAll(){return []},querySelector(){return null},createElement(){return el('taskDialog')},body:{appendChild(){}}},navigator:{},location:{search:'',pathname:'/'},history:{replaceState(){}},setTimeout,clearTimeout});ctx.window=ctx;vm.runInContext(script,ctx);const run=s=>vm.runInContext(s,ctx);

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
