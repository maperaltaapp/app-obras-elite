const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const html=fs.readFileSync(__dirname+'/index.html','utf8'),script=html.match(/<script>([\s\S]*)<\/script>/)[1];
const map=new Map();function el(id){if(!map.has(id))map.set(id,{id,innerHTML:'',textContent:'',value:'',disabled:false,classList:{add(){},remove(){},toggle(){}},showModal(){},close(){},remove(){map.delete(this.id)},focus(){},addEventListener(){}});return map.get(id)}
const ctx=vm.createContext({console,Date,Map,URL,URLSearchParams,crypto,localStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{getElementById:el,querySelectorAll(){return []},querySelector(selector){return selector==='#content .task-toolbar'?{insertAdjacentHTML(_,text){el('content').innerHTML+=text}}:null},createElement(){return el('taskDialog')},body:{appendChild(){}}},navigator:{},location:{search:'',pathname:'/'},history:{replaceState(){}},setTimeout,clearTimeout});ctx.window=ctx;vm.runInContext(script,ctx);const run=s=>vm.runInContext(s,ctx);


run("calCursor=new Date(2026,9,22);NATIVE_WORKS=[]");
ctx.cards=Array.from({length:6},(_,i)=>({id:'w'+i,name:'Revisar material '+i,own:true,priority:i===0?'urgent':'normal',due:'2026-10-22T'+String(9+i).padStart(2,'0')+':00:00',board:{id:'b1',name:'Obra'}}));
ctx.cards.push({id:'outside',name:'Fuera de semana',own:true,due:'2026-10-26T09:00:00',board:{name:'Obra'}});
let weekly=run('weekView(cards)');
assert.equal((weekly.match(/class="week-calendar-day /g)||[]).length,7);
for(const day of ['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])assert(weekly.includes(day));
assert.equal((weekly.match(/class="week-calendar-event"/g)||[]).length,6);
assert(!weekly.includes('Fuera de semana'));assert(!weekly.includes('compact-task'));assert(weekly.includes('task-priority-urgent'));assert(weekly.includes('⚠'));assert(weekly.includes('14:00'));assert(weekly.includes('toggleTaskComplete'));
assert(!run('monthView(cards)').includes('toggleTaskComplete'));
run("calCursor=new Date(2026,10,1)");weekly=run('weekView(cards)');assert(weekly.includes('26'));assert(weekly.includes('Fuera de semana'));
console.log('PASS: Monday–Sunday grid, all events visible without task-list rows, date boundary filtering across months, urgent icon, event times, weekly completion retained and monthly remains unchanged.');
