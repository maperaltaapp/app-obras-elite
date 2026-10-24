const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const html=fs.readFileSync(__dirname+'/index.html','utf8'),script=html.match(/<script>([\s\S]*)<\/script>/)[1];
const map=new Map();function el(id){if(!map.has(id))map.set(id,{id,innerHTML:'',textContent:'',value:'',disabled:false,classList:{add(){},remove(){},toggle(){}},showModal(){},close(){},remove(){map.delete(this.id)},focus(){},addEventListener(){}});return map.get(id)}
const ctx=vm.createContext({console,Date,Map,URL,URLSearchParams,crypto,localStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{getElementById:el,querySelectorAll(){return []},querySelector(selector){return selector==='#content .task-toolbar'?{insertAdjacentHTML(_,text){el('content').innerHTML+=text}}:null},createElement(){return el('taskDialog')},body:{appendChild(){}}},navigator:{},location:{search:'',pathname:'/'},history:{replaceState(){}},setTimeout,clearTimeout});ctx.window=ctx;vm.runInContext(script,ctx);const run=s=>vm.runInContext(s,ctx);

ctx.work={id:'w1',name:'Obra',stages:[]};ctx.fixture={id:'t1',title:'Comprar material urgente ahora',work_id:'w1',category:'work',priority:'urgent',status:'pending',description:'Notas existentes',labels:[],checklists:[],recurrence:'none',remind_at:null,remind_minutes:null,extra_remind_at:[]};
run("NATIVE_WORKS=[work];OWN_TASKS=[fixture];openTaskForm('t1')");
for(const id of ['ownReminderAt','ownReminderAt2','ownReminderAt3'])assert(el('taskDialog').innerHTML.includes('id="'+id+'"'));
el('ownReminder').value='custom';el('ownReminderAt').value='2099-10-20T10:00';el('ownReminderAt2').value='2099-10-20T11:00';el('ownReminderAt3').value='2099-10-21T12:00';
let reminders=run('collectTaskReminders()');assert.equal(reminders.extra_remind_at.length,2);assert.equal(new Set([reminders.remind_at,...reminders.extra_remind_at]).size,3);
el('ownReminderAt3').value='2099-10-20T10:00';assert.throws(()=>run('collectTaskReminders()'),/distintas/);
el('ownReminderAt3').value='2020-01-01T10:00';assert.throws(()=>run('collectTaskReminders()'),/futuras/);
el('ownReminderAt3').value='';el('ownReminder').value='';el('ownReminderAt').value='';reminders=run('collectTaskReminders()');assert.equal(reminders.remind_at,null);assert.equal(reminders.extra_remind_at.length,1);
el('ownReminderAt2').value='';assert.equal(run('collectTaskReminders().extra_remind_at.length'),0);
el('ownReminderAt2').value='2099-10-20T10:00';el('ownReminder').value='60';el('ownDue').value='2099-10-20T11:00';assert.throws(()=>run('collectTaskReminders()'),/distintas/);
run("fixture.extra_remind_at=['2020-01-01T10:00:00Z'];editingTask=fixture");el('ownReminder').value='';el('ownReminderAt2').value=run('localDateTime(fixture.extra_remind_at[0])');assert.equal(run('collectTaskReminders().extra_remind_at[0]'),'2020-01-01T10:00:00Z');
let markup=run("compactTask(nativeCard(fixture),{name:'Obra'})");assert(markup.includes('task-priority-urgent'));assert(markup.includes('aria-label="Urgente"'));assert(markup.includes('⚠'));
markup=run('calendarTask(nativeCard(fixture))');assert(markup.includes('task-priority-urgent'));assert(markup.includes('⚠'));assert(markup.includes('Comprar material urgente'));
run("fixture.priority='normal'");markup=run("compactTask(nativeCard(fixture),{name:'Obra'})");assert(!markup.includes('task-priority-urgent'));assert(!markup.includes('⚠'));
assert(html.includes('.event.task-priority-urgent{background:#ffe1de;color:#a51c17'));
assert(html.includes('.compact-task.task-priority-urgent{background:#fff1f0'));
console.log('PASS: three reminder inputs; independent dates; distinct dates and future validation; removing reminders; existing past dates preserved on unrelated edits; urgent red class and accessible warning in lists and calendar; normal priority remains unchanged.');

run('openTaskForm()');let form=el('taskDialog').innerHTML;
assert(form.includes('<details class="task-reminders" id="reminderSettings">'));
assert(!form.includes('id="reminderSettings" open'));
assert(form.includes('<option value="0" selected>Al vencimiento</option>'));
el('ownReminder').value='0';el('ownDue').value='2099-10-20T12:00';el('ownReminderAt2').value='';el('ownReminderAt3').value='';
assert.equal(run('collectTaskReminders().remind_minutes'),0);
el('ownDue').value='2099-10-21T14:00';assert.equal(run('collectTaskReminders().remind_minutes'),0);
el('ownDue').value='';assert.equal(run('collectTaskReminders().remind_minutes'),null);
run("fixture.remind_minutes=null;fixture.remind_at=null;fixture.extra_remind_at=[];openTaskForm('t1')");
assert(el('taskDialog').innerHTML.includes('<option value="" selected>Sin aviso</option>'));
el('ownReminder').value='custom';el('ownReminder').onchange();assert.equal(el('customReminderRow').hidden,false);
el('ownReminder').value='0';el('ownDue').value='2099-10-22T11:00';el('ownReminder').onchange();assert.equal(el('customReminderRow').hidden,true);assert(el('reminderSummary').textContent.includes('Al vencimiento'));
el('ownReminderAt2').value='2099-10-21T10:00';el('ownReminderAt2').oninput();assert(el('reminderSummary').textContent.includes('+1 aviso'));
console.log('PASS: new tasks default to due-time reminder; due-date changes keep linked offset; undated task allowed; existing disabled reminders preserved; collapsed compact panel and summary update.');
