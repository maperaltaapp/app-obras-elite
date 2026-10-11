self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('push',event=>{
 let data={};try{data=event.data?.json()||{}}catch{}
 event.waitUntil(self.registration.showNotification(data.title||'Obras Elite',{body:data.body||'Tienes una tarea pendiente.',tag:data.tag||'elite-reminder',icon:'./icon-192.png',data:{url:data.url||self.registration.scope}}));
});
self.addEventListener('notificationclick',event=>{
 event.notification.close();let url=new URL(event.notification.data?.url||self.registration.scope,self.registration.scope);
 if(url.origin!==self.location.origin||!url.pathname.startsWith(new URL(self.registration.scope).pathname))url=new URL(self.registration.scope);
 event.waitUntil(self.clients.matchAll({type:'window',includeUncontrolled:true}).then(async clients=>{for(const client of clients){if(client.url.startsWith(self.registration.scope)&&'focus' in client){await client.navigate(url.href);return client.focus()}}return self.clients.openWindow(url.href)}));
});
