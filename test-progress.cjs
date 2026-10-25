const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const html=fs.readFileSync(__dirname+'/index.html','utf8'),script=html.match(/<script>([\s\S]*)<\/script>/)[1];
const map=new Map();function el(id){if(!map.has(id))map.set(id,{id,innerHTML:'',textContent:'',value:'',disabled:false,classList:{add(){},remove(){},toggle(){}},showModal(){},close(){},remove(){map.delete(this.id)},focus(){},addEventListener(){}});return map.get(id)}
const ctx=vm.createContext({console,Date,Map,URL,URLSearchParams,crypto,localStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{getElementById:el,querySelectorAll(){return []},querySelector(selector){return selector==='#content .task-toolbar'?{insertAdjacentHTML(_,text){el('content').innerHTML+=text}}:null},createElement(){return el('taskDialog')},body:{appendChild(){}}},navigator:{},location:{search:'',pathname:'/'},history:{replaceState(){}},setTimeout,clearTimeout});ctx.window=ctx;vm.runInContext(script,ctx);const run=s=>vm.runInContext(s,ctx);

ctx.w={id:'w1',name:'Prueba',cards:[{id:'t1',complete:true},{id:'t2',complete:true}],progress:85};
run("NATIVE_WORKS=[w];WORK_PLANS=[]");
assert.equal(run('measuredWorkProgress(w)'),null);
assert(run('renderWorkCard(w)').includes('Sin mediciones'));
assert(!run('renderWorkCard(w)').includes('85%'));
ctx.phases=[{id:'p1',name:'A',start:'2020-01-01',end:'2099-12-31',weight:40,observations:[]},{id:'p2',name:'B',start:'2020-01-01',end:'2099-12-31',weight:60,observations:[]}];
run("WORK_PLANS=[{work_id:'w1',phases}]");
assert.equal(run('measuredWorkProgress(w)'),null);
assert(run('renderWorkCard(w)').includes('Sin mediciones'));
run("phases[0].observations=[{date:'2020-01-01',percent:0}]");
assert.equal(run('measuredWorkProgress(w)'),0);
assert(run('renderWorkCard(w)').includes('0% avance físico'));
run("phases[0].observations[0].percent=50;phases[1].observations=[{date:'2020-01-01',percent:25}]");
assert.equal(run('measuredWorkProgress(w)'),35);
assert(run('renderWorkCard(w)').includes('35% avance físico'));
run("phases[0].observations=[{date:'2099-01-01',percent:100}];phases[1].observations=[]");
assert.equal(run('measuredWorkProgress(w)'),null);
run("OWN_TASKS=[];detail('w1')");
assert(!el('content').innerHTML.includes('Generar PDF'));
assert(!html.includes('generateWorkPdf'));
assert(!html.includes('buildWorkPdf'));
assert.equal(run('typeof generateWorkPdf'),'undefined');
assert(html.includes('application/pdf'));
console.log('PASS: completed tasks and old manual values do not create physical progress; no measurements differs from measured zero; weighted measurements retained; future observations excluded; PDF generator removed; attachments retained.');
