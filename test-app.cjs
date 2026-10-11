const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('index.html','utf8'),script=html.match(/<script>([\s\S]*)<\/script>/)[1];
const map=new Map();
function el(id){if(!map.has(id))map.set(id,{id,innerHTML:'',textContent:'',value:'',className:'',disabled:false,classList:{add(){},remove(){},toggle(){}},focus(){},showModal(){},close(){},remove(){map.delete(this.id)},addEventListener(){}});return map.get(id)}
const localStorage={getItem(){return null},setItem(){},removeItem(){}};
const context=vm.createContext({console,Date,Map,URL,URLSearchParams,localStorage,document:{getElementById:el,querySelectorAll(){return []},createElement(){const e=el('taskDialog');return e},body:{appendChild(){}}},window:{isSecureContext:true},navigator:{},location:{search:'',pathname:'/'},history:{replaceState(){}},setTimeout,clearTimeout});
vm.runInContext(script,context);const run=s=>vm.runInContext(s,context);
run(`DATA=[{id:'b1',name:'Prensas Cimentación',lists:[{id:'l1',name:'Preparación'}],cards:[
{id:'t1',name:'01 · Revisar planos de cimentación',due:'2026-10-12T07:00:00Z',idList:'l1',url:'https://trello.com/c/test1'},
{id:'t2',name:'Confirmar pedido de hormigón',due:'2026-10-12T08:00:00Z',url:'https://trello.com/c/test2'},
{id:'t3',name:'Inspección de armaduras en obra',due:'2026-10-12T09:00:00Z',url:'https://trello.com/c/test3'},
{id:'t4',name:'4. Revisión sin fecha',idList:'l1',url:'https://trello.com/c/test4'},
{id:'t5',name:'Tarea completada con fecha',due:'2026-10-12T05:00:00Z',dueComplete:true,url:'https://trello.com/c/test5'}]},
{id:'b2',name:'Cubiertas bajas',cards:[{id:'t6',name:'Hols',due:'2026-10-11T08:00:00Z',url:'https://trello.com/c/test6'}]}];
OWN_TASKS=[{id:'11111111-1111-4111-8111-111111111111',title:'Comprar material para casa',category:'personal',work_name:'Casa',due_at:'2026-10-12T12:00:00Z',completed:false,remind_minutes:15},{id:'22222222-2222-4222-8222-222222222222',title:'Llamar a proveedor mañana',category:'work',work_name:'Cubierta',due_at:'2026-10-12T14:00:00Z',completed:false,remind_minutes:5}];render();`);
assert.equal(run('mode'),'tasks');assert.equal(run('taskFilter'),'dated');
let result=el('taskResults').innerHTML;assert(result.indexOf('Hols')<result.indexOf('Revisar planos'));assert(!result.includes('Tarea completada'));assert(!result.includes('Revisión sin fecha'));
run("tasks('undated')");assert(el('taskResults').innerHTML.includes('Revisión sin fecha'));assert(el('taskResults').innerHTML.includes('<details class="task-group">'));
run("tasks('dated');taskSource='personal';renderTaskResults()");assert(el('taskResults').innerHTML.includes('Comprar material para'));assert(!el('taskResults').innerHTML.includes('Hols'));
run("taskSource='all';taskQuery='hormigón';renderTaskResults()");assert(el('taskResults').innerHTML.includes('Confirmar pedido de'));assert(!el('taskResults').innerHTML.includes('Hols'));
assert.equal(run("shortTaskName('01 · Revisar planos de cimentación')"),'Revisar planos de');
assert.equal(run("shortTaskName('Uno dos tres cuatro')"),'Uno dos tres');
assert.equal(run("trelloHref({url:'javascript:alert(1)'})"),'#');
run("taskQuery='';calCursor=new Date(2026,9,12);mode='calendar';render()");
result=el('content').innerHTML;assert(result.includes('+3 <span>tareas</span>'));assert.equal((result.match(/class="event /g)||[]).length,3);assert(result.includes('href="https://trello.com/c/test1"'));assert(result.includes("openTaskForm('11111111-1111-4111-8111-111111111111')"));assert(result.includes('aria-label="01 · Revisar planos de cimentación'));
assert(!result.includes('Tarea completada'));assert(result.includes('Fiesta Nacional de España'));
run("calMode='week';calendar()");assert(el('content').innerHTML.includes('+1 <span>tareas</span>'));
run("openTaskForm('11111111-1111-4111-8111-111111111111')");assert(el('taskDialog').innerHTML.includes('Comprar material para casa'));assert(el('taskDialog').innerHTML.includes('15 minutos antes'));
// Keep synthetic fixture screenshots independent of the live user's data/authentication.
run("taskSource='all';taskQuery='';mode='tasks';render()");
const css=html.match(/<style>([\s\S]*)<\/style>/)[1];
const shell=content=>`<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${css}</style><header><h1>App Obras Elite</h1></header><div class="wrap"><div class="nav"><button class="on">Tareas</button><button>Calendario</button><button>Obras</button></div><div class="panel top"><b>Tareas con fecha</b><div class="task-actions"><button class="dark">+ Tarea</button><button class="light">Avisos</button><button class="light">↻</button></div></div>${content}<p class="small">Vista de prueba · datos ficticios</p></div></html>`;
const tasks=el('content').innerHTML.replace('<div id="taskResults"></div>',`<div id="taskResults">${el('taskResults').innerHTML}</div>`);
fs.writeFileSync('preview-tasks.html',shell(tasks));
run("calMode='month';mode='calendar';render()");fs.writeFileSync('preview-calendar.html',shell(el('content').innerHTML));
console.log('OK: default agenda, global date order, own/Trello filters, full-name search, three-word titles, safe links, calendar limits/counts, own task dialogs, holidays.');
// Exercise persistence with a mocked API; no live user data is created.
(async()=>{
const requests=[];context.fetch=async(url,options={})=>{requests.push({url,options});return {ok:true,status:200,text:async()=>options.method==='POST'?'':JSON.stringify([])}};
run("session={access_token:'test'};editingTask=null;");el('ownTitle').value='Nueva tarea personal';el('ownCategory').value='personal';el('ownWork').value='Casa';el('ownDue').value='2026-10-13T09:00';el('ownReminder').value='15';
await run('saveOwnTask({preventDefault(){}})');const req=requests.find(r=>r.options.method==='POST');assert(req);const body=JSON.parse(req.options.body);assert.equal(body.category,'personal');assert.equal(body.remind_minutes,15);assert.equal(new Date(body.due_at).getHours(),9);assert(!('user_id'in body));
assert.equal(run('taskFilter'),'dated');assert.equal(run('taskQuery'),'');console.log('OK: personal task payload, timezone conversion, reminder selection, server-owned user identity.');
})().catch(e=>{console.error(e);process.exitCode=1});
