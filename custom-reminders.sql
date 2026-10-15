-- Add custom reminder dates without changing existing task data or push keys.
begin;
alter table public.elite_tasks add column if not exists remind_at timestamptz;
do $$ begin
 if not exists(select 1 from pg_catalog.pg_constraint where conrelid='public.elite_tasks'::regclass and conname='elite_reminder_one_mode') then
  alter table public.elite_tasks add constraint elite_reminder_one_mode check(remind_at is null or remind_minutes is null);
 end if;
end $$;
create or replace function elite_private.task_revision() returns trigger language plpgsql set search_path='' as $$ begin
 new.user_id:=old.user_id; new.created_at:=old.created_at; new.updated_at:=now();
 if (new.due_at,new.remind_minutes,new.remind_at,new.completed,new.deleted_at) is distinct from (old.due_at,old.remind_minutes,old.remind_at,old.completed,old.deleted_at) then new.revision:=old.revision+1; else new.revision:=old.revision; end if;
 return new; end $$;
create or replace function public.elite_claim_reminders() returns jsonb language plpgsql security definer set search_path='' as $$ declare output jsonb; begin
 insert into public.elite_push_deliveries(task_id,revision,subscription_id)
 select t.id,t.revision,s.id from public.elite_tasks t join public.elite_push_subscriptions s on s.user_id=t.user_id left join public.elite_works w on w.id=t.work_id
 where (t.work_id is null or w.archived_at is null) and not t.completed and t.deleted_at is null and (t.remind_at is not null and t.remind_at<=now() and t.remind_at>=now()-interval '24 hours' or t.remind_at is null and t.remind_minutes is not null and t.due_at-make_interval(mins=>t.remind_minutes)<=now() and t.due_at>=now()-interval '24 hours')
 on conflict do nothing;
 with candidates as (
 select d.id from public.elite_push_deliveries d join public.elite_tasks t on t.id=d.task_id left join public.elite_works w on w.id=t.work_id
 where (d.status='pending' or (d.status='sending' and d.lease_until<now())) and d.attempts<4 and (d.lease_until is null or d.lease_until<now())
 and (t.work_id is null or w.archived_at is null) and (t.remind_at is not null and t.remind_at<=now() and t.remind_at>=now()-interval '24 hours' or t.remind_at is null and t.remind_minutes is not null and t.due_at-make_interval(mins=>t.remind_minutes)<=now() and t.due_at>=now()-interval '24 hours') and d.revision=t.revision and not t.completed and t.deleted_at is null
 order by coalesce(t.remind_at,t.due_at-make_interval(mins=>t.remind_minutes)) limit 30 for update of d skip locked
 ), claimed as (
 update public.elite_push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '5 minutes' from candidates c where d.id=c.id returning d.*
 ) select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'revision',d.revision,'attempts',d.attempts,'task_id',t.id,'title',t.title,'due_at',t.due_at,'subscription_id',s.id,'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth)),'[]'::jsonb)
 into output from claimed d join public.elite_tasks t on t.id=d.task_id join public.elite_push_subscriptions s on s.id=d.subscription_id;
 return output; end $$;
revoke all on function public.elite_claim_reminders() from public,anon,authenticated;
grant execute on function public.elite_claim_reminders() to service_role;
create or replace function public.elite_complete_task(task_id uuid, expected_updated_at timestamptz) returns uuid language plpgsql security invoker set search_path='' as $$
declare t public.elite_tasks; next_id uuid; next_due timestamptz; next_start timestamptz; next_reminder timestamptz; step interval; reset_checks jsonb;
begin
 select * into t from public.elite_tasks where id=task_id and user_id=auth.uid() and deleted_at is null for update;
 if not found then raise exception 'Tarea no encontrada'; end if;
 if t.completed then return null; end if;
 if t.updated_at is distinct from expected_updated_at then raise exception 'La tarea ha cambiado. Actualiza antes de completar.'; end if;
 update public.elite_tasks set completed=true where id=t.id;
 if t.recurrence='none' then return null; end if;
 step:=case t.recurrence when 'daily' then interval '1 day' when 'weekly' then interval '7 days' else interval '1 month' end;
 next_due:=((t.due_at at time zone t.recurrence_timezone)+step) at time zone t.recurrence_timezone;
 next_start:=((t.start_at at time zone t.recurrence_timezone)+step) at time zone t.recurrence_timezone;
 next_reminder:=((t.remind_at at time zone t.recurrence_timezone)+step) at time zone t.recurrence_timezone;
 select coalesce(jsonb_agg(c || jsonb_build_object('items',coalesce((select jsonb_agg(i || '{"done":false}'::jsonb) from jsonb_array_elements(c->'items') i),'[]'::jsonb))),'[]'::jsonb) into reset_checks from jsonb_array_elements(t.checklists) c;
 insert into public.elite_tasks(user_id,title,category,work_name,work_id,description,start_at,due_at,remind_minutes,remind_at,status,priority,labels,checklists,stage,recurrence,recurrence_timezone,previous_task_id)
 values(t.user_id,t.title,t.category,t.work_name,t.work_id,t.description,next_start,next_due,t.remind_minutes,next_reminder,'pending',t.priority,t.labels,reset_checks,t.stage,t.recurrence,t.recurrence_timezone,t.id)
 on conflict(previous_task_id) do nothing returning id into next_id;
 return next_id;
end $$;
revoke all on function public.elite_complete_task(uuid,timestamptz) from public,anon;
grant execute on function public.elite_complete_task(uuid,timestamptz) to authenticated;
-- Reschedule the existing minute job; authentication and push keys are unchanged.
select cron.schedule('elite-task-reminders','* * * * *',$job$
 select net.http_post(
  url:='https://vyswxgbbqyffnduhhrvz.supabase.co/functions/v1/elite-notifications',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select gateway_jwt from elite_private.push_config where id=true),'x-elite-cron',(select cron_secret from elite_private.push_config where id=true)),
  body:='{}'::jsonb,timeout_milliseconds:=60000
 ) where exists (
  select 1 from public.elite_tasks t join public.elite_push_subscriptions s on s.user_id=t.user_id left join public.elite_works w on w.id=t.work_id
  where (t.work_id is null or w.archived_at is null) and not t.completed and t.deleted_at is null and (t.remind_at is not null and t.remind_at<=now() and t.remind_at>=now()-interval '24 hours' or t.remind_at is null and t.remind_minutes is not null and t.due_at-make_interval(mins=>t.remind_minutes)<=now() and t.due_at>=now()-interval '24 hours')
  and not exists(select 1 from public.elite_push_deliveries d where d.task_id=t.id and d.revision=t.revision and d.subscription_id=s.id and d.status in ('sent','failed','cancelled'))
 );
$job$);

notify pgrst, 'reload schema';
commit;
