begin;
alter table elite_private.push_config add column if not exists gateway_jwt text;
create or replace function public.elite_set_gateway_jwt(token text) returns jsonb language plpgsql security definer set search_path='' as $$ begin
 if token is null or token not like 'eyJ%.%.%' or length(token)>4096 then raise exception 'Token de programador no válido'; end if;
 update elite_private.push_config set gateway_jwt=token where id=true;
 return public.elite_push_config(); end $$;
revoke all on function public.elite_set_gateway_jwt(text) from public,anon,authenticated;
grant execute on function public.elite_set_gateway_jwt(text) to service_role;
create or replace function public.elite_claim_reminders() returns jsonb language plpgsql security definer set search_path='' as $$ declare output jsonb; begin
 insert into public.elite_push_deliveries(task_id,revision,subscription_id)
 select t.id,t.revision,s.id from public.elite_tasks t join public.elite_push_subscriptions s on s.user_id=t.user_id left join public.elite_works w on w.id=t.work_id
 where (t.work_id is null or w.archived_at is null) and not t.completed and t.deleted_at is null and t.remind_minutes is not null and t.due_at-make_interval(mins=>t.remind_minutes)<=now() and t.due_at>=now()-interval '24 hours'
 on conflict do nothing;
 with candidates as (
 select d.id from public.elite_push_deliveries d join public.elite_tasks t on t.id=d.task_id left join public.elite_works w on w.id=t.work_id
 where (d.status='pending' or (d.status='sending' and d.lease_until<now())) and d.attempts<4 and (d.lease_until is null or d.lease_until<now())
 and (t.work_id is null or w.archived_at is null) and t.remind_minutes is not null and t.due_at-make_interval(mins=>t.remind_minutes)<=now() and d.revision=t.revision and not t.completed and t.deleted_at is null and t.due_at>=now()-interval '24 hours'
 order by t.due_at limit 30 for update of d skip locked
 ), claimed as (
 update public.elite_push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '5 minutes' from candidates c where d.id=c.id returning d.*
 ) select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'revision',d.revision,'attempts',d.attempts,'task_id',t.id,'title',t.title,'due_at',t.due_at,'subscription_id',s.id,'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth)),'[]'::jsonb)
 into output from claimed d join public.elite_tasks t on t.id=d.task_id join public.elite_push_subscriptions s on s.id=d.subscription_id;
 return output; end $$;
revoke all on function public.elite_claim_reminders() from public,anon,authenticated;
grant execute on function public.elite_claim_reminders() to service_role;
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

commit;
