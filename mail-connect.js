'use strict';
const BASE='https://vyswxgbbqyffnduhhrvz.supabase.co';
const KEY='sb_publishable_nzhp4ZiQ5NltXfmuoBc-hg_v_OVHRYb';
const $=id=>document.getElementById(id);let token=null;
function status(text){$('status').textContent=text;}
function view(id){for(const name of ['login','connect','connected'])$(name).classList.toggle('hidden',name!==id);}
async function request(path,data={}){
 const response=await fetch(BASE+'/functions/v1/elite-mail/'+path,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify(data),signal:AbortSignal.timeout(35000)});
 const result=await response.json();if(!response.ok)throw Error(result.error||result.message||'No se pudo completar la solicitud.');return result;
}
async function busy(button,fn){button.disabled=true;try{await fn();}catch(e){status(e.message||'No se pudo conectar.');}finally{button.disabled=false;}}
$('login').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{
 status('Comprobando tu cuenta de Elite…');let password=$('elite-password').value;$('elite-password').value='';
 const response=await fetch(BASE+'/auth/v1/token?grant_type=password',{method:'POST',headers:{'Content-Type':'application/json',apikey:KEY},body:JSON.stringify({email:$('email').value.trim(),password}),signal:AbortSignal.timeout(15000)});password='';
 const result=await response.json();if(!response.ok)throw Error('No se pudo iniciar sesión en Elite. Comprueba el correo y la contraseña.');token=result.access_token;
 const state=await request('status');view(state.state==='connected'?'connected':'connect');status('');
 });};
$('connect').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{status('Comprobando el acceso cifrado al correo…');let password=$('mail-password').value;$('mail-password').value='';try{await request('connect',{password});view('connected');status('Correo conectado en modo de solo lectura.');}finally{password='';}});};
$('test').onclick=e=>busy(e.target,async()=>{status('Comprobando lectura…');const result=await request('api',{action:'list',limit:1});status('Lectura correcta. '+result.total+' mensajes en la bandeja de entrada. No se ha modificado ningún correo.');});
$('disconnect').onclick=e=>busy(e.target,async()=>{await request('disconnect');view('connect');status('Correo desconectado. Se ha eliminado la credencial guardada.');});
