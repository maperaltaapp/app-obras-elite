import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
const APP='https://maperaltaapp.github.io/app-obras-elite/';
const headers={'Access-Control-Allow-Origin':new URL(APP).origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-elite-cron','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
function safeEndpoint(value:string){try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&['fcm.googleapis.com','updates.push.services.mozilla.com','push.services.mozilla.com','web.push.apple.com','notify.windows.com'].some(h=>u.hostname===h||u.hostname.endsWith('.'+h))}catch{return false}}
async function configuration(){let {data,error}=await db.rpc('elite_push_config');if(error)throw error;if(!data.public_key){const k=webpush.generateVAPIDKeys();const result=await db.rpc('elite_init_vapid',{pub:k.publicKey,priv:k.privateKey});if(result.error)throw result.error;data=result.data}if(!data.gateway_jwt){const token=Deno.env.get('SUPABASE_ANON_KEY')||'';if(!token.startsWith('eyJ'))throw new Error('Legacy gateway token unavailable');const result=await db.rpc('elite_set_gateway_jwt',{token});if(result.error)throw result.error;data=result.data}return data}
function pushOptions(config:any){return {TTL:3600,timeout:10000,vapidDetails:{subject:APP,publicKey:config.public_key,privateKey:config.private_key}}}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 try{
  if(req.method==='GET'){const c=await configuration();return reply({publicKey:c.public_key,ready:true})}
  if(req.method!=='POST')return reply({error:'Método no permitido'},405);
  const cron=req.headers.get('x-elite-cron');
  if(cron){const config=await configuration();if(cron!==config.cron_secret)return reply({error:'No autorizado'},401);
   const {data:jobs,error}=await db.rpc('elite_claim_reminders');if(error)throw error;let sent=0,failed=0;
   for(const j of jobs){try{
    if(!safeEndpoint(j.endpoint))throw new Error('Destino push no válido');
    const {data:task,error:readError}=await db.from('elite_tasks').select('revision,completed,deleted_at,work_id').eq('id',j.task_id).single();if(readError)throw readError;
    let archivedWork=false;if(task.work_id){const {data:work,error:workError}=await db.from('elite_works').select('archived_at').eq('id',task.work_id).single();if(workError)throw workError;archivedWork=!!work.archived_at}if(task.revision!==j.revision||task.completed||task.deleted_at||archivedWork){await db.from('elite_push_deliveries').update({status:'cancelled'}).eq('id',j.id);continue}
    await webpush.sendNotification({endpoint:j.endpoint,keys:{p256dh:j.p256dh,auth:j.auth}},JSON.stringify({title:'Recordatorio · Obras Elite',body:j.title,url:APP+'?task='+j.task_id,tag:'elite-'+j.id}),pushOptions(config));
    const {error:saveError}=await db.from('elite_push_deliveries').update({status:'sent',sent_at:new Date().toISOString(),last_error:null}).eq('id',j.id);if(saveError)throw saveError;sent++;
   }catch(e){failed++;const status=Number(e.statusCode||0);if(status===404||status===410){await db.from('elite_push_subscriptions').delete().eq('id',j.subscription_id)}else{await db.from('elite_push_deliveries').update({status:j.attempts>=4?'failed':'pending',last_error:status?'Push HTTP '+status:'Fallo de envío',lease_until:new Date(Date.now()+300000).toISOString()}).eq('id',j.id)}}
   }return reply({processed:jobs.length,sent,failed});
  }
  const token=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');if(!token)return reply({error:'Inicia sesión'},401);
  const {data:{user},error:authError}=await db.auth.getUser(token);if(authError||!user)return reply({error:'Sesión caducada'},401);
  if(Number(req.headers.get('content-length')||0)>10000)return reply({error:'Solicitud demasiado grande'},413);
  const body=await req.json();const config=await configuration();
  if(body.action==='subscribe'){
   const s=body.subscription;if(!s||!safeEndpoint(s.endpoint)||typeof s.keys?.p256dh!=='string'||typeof s.keys?.auth!=='string'||s.keys.p256dh.length>200||s.keys.auth.length>100)return reply({error:'Suscripción no válida'},400);
   const {data:existing}=await db.from('elite_push_subscriptions').select('id,user_id').eq('endpoint',s.endpoint).maybeSingle();
   if(existing&&existing.user_id!==user.id)return reply({error:'Desactiva los avisos de la cuenta anterior en este navegador'},409);
   const {count}=await db.from('elite_push_subscriptions').select('id',{count:'exact',head:true}).eq('user_id',user.id);if(!existing&&(count||0)>=5)return reply({error:'Máximo de cinco dispositivos. Desactiva uno primero.'},400);
   const {error}=await db.from('elite_push_subscriptions').upsert({user_id:user.id,endpoint:s.endpoint,p256dh:s.keys.p256dh,auth:s.keys.auth},{onConflict:'endpoint'});if(error)throw error;
   return reply({ok:true});
  }
  if(body.action==='test'){
   const {data:s,error}=await db.from('elite_push_subscriptions').select('*').eq('user_id',user.id).eq('endpoint',body.endpoint).single();if(error||!s)return reply({error:'Activa los avisos primero'},400);
   if(!safeEndpoint(s.endpoint))return reply({error:'Destino no válido'},400);
   await webpush.sendNotification({endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth}},JSON.stringify({title:'Obras Elite',body:'Los avisos están activados en este dispositivo.',url:APP,tag:'elite-test'}),pushOptions(config));return reply({ok:true});
  }
  return reply({error:'Acción no válida'},400);
 }catch(e){console.error('elite-notifications',e?.statusCode||e?.code||'internal');return reply({error:'No se pudo completar la operación. Inténtalo de nuevo.'},500)}
});
