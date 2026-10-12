create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
select cron.schedule('elite-task-reminders','* * * * *',$job$
 select net.http_post(
  url:='https://vyswxgbbqyffnduhhrvz.supabase.co/functions/v1/elite-notifications',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select gateway_jwt from elite_private.push_config where id=true),'x-elite-cron',(select cron_secret from elite_private.push_config where id=true)),
  body:='{}'::jsonb,timeout_milliseconds:=60000
 ) where exists (
  select 1 from public.elite_tasks t join public.elite_push_subscriptions s on s.user_id=t.user_id left join public.elite_works w on w.id=t.work_id
  where (t.work_id is null or w.archived_at is null) and not t.completed and t.deleted_at is null and t.remind_minutes is not null
  and t.due_at-make_interval(mins=>t.remind_minutes)<=now() and t.due_at>=now()-interval '24 hours'
  and not exists(select 1 from public.elite_push_deliveries d where d.task_id=t.id and d.revision=t.revision and d.subscription_id=s.id and d.status in ('sent','failed','cancelled'))
 );
$job$);
