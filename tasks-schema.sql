begin;
create schema if not exists elite_private;
revoke all on schema elite_private from public, anon, authenticated;
create table public.elite_tasks (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 title text not null check(length(trim(title)) between 1 and 240), category text not null check(category in ('personal','work')),
 work_name text not null default '' check(length(work_name)<=160), due_at timestamptz,
 remind_minutes integer check(remind_minutes in (0,5,15,30,60,1440)), completed boolean not null default false,
 deleted_at timestamptz, revision integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(remind_minutes is null or due_at is not null)
);
alter table public.elite_tasks enable row level security;
create policy elite_tasks_owner on public.elite_tasks for all to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
revoke all on public.elite_tasks from anon, authenticated;
grant select,insert,update on public.elite_tasks to authenticated;
grant all on public.elite_tasks to service_role;
create index elite_tasks_owner_due on public.elite_tasks(user_id,due_at);
create function elite_private.task_revision() returns trigger language plpgsql set search_path='' as $$ begin
 new.user_id:=old.user_id; new.created_at:=old.created_at; new.updated_at:=now();
 if (new.due_at,new.remind_minutes,new.completed,new.deleted_at) is distinct from (old.due_at,old.remind_minutes,old.completed,old.deleted_at) then new.revision:=old.revision+1; else new.revision:=old.revision; end if;
 return new; end $$;
create trigger elite_tasks_revision before update on public.elite_tasks for each row execute function elite_private.task_revision();
create table public.elite_push_subscriptions (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text unique not null check(length(endpoint)<4096),p256dh text not null,auth text not null,created_at timestamptz not null default now()
);
alter table public.elite_push_subscriptions enable row level security;
create policy elite_subscriptions_owner on public.elite_push_subscriptions for select to authenticated using ((select auth.uid())=user_id);
create policy elite_subscriptions_delete on public.elite_push_subscriptions for delete to authenticated using ((select auth.uid())=user_id);
revoke all on public.elite_push_subscriptions from anon,authenticated;
grant select,delete on public.elite_push_subscriptions to authenticated;
grant all on public.elite_push_subscriptions to service_role;
create index elite_subscriptions_user on public.elite_push_subscriptions(user_id);
create table elite_private.push_config(id boolean primary key default true check(id), cron_secret text not null default gen_random_uuid()::text, public_key text,private_key text);
alter table elite_private.push_config enable row level security;
insert into elite_private.push_config(id) values(true);
create function public.elite_push_config() returns jsonb language sql security definer set search_path='' as $$ select to_jsonb(c) from elite_private.push_config c where id=true $$;
revoke all on function public.elite_push_config() from public,anon,authenticated;
grant execute on function public.elite_push_config() to service_role;
create function public.elite_init_vapid(pub text, priv text) returns jsonb language plpgsql security definer set search_path='' as $$ begin
 update elite_private.push_config set public_key=pub,private_key=priv where id=true and public_key is null;
 return public.elite_push_config(); end $$;
revoke all on function public.elite_init_vapid(text,text) from public,anon,authenticated;
grant execute on function public.elite_init_vapid(text,text) to service_role;
create table public.elite_push_deliveries (
 id uuid primary key default gen_random_uuid(),task_id uuid not null references public.elite_tasks(id) on delete cascade,
 revision integer not null,subscription_id uuid not null references public.elite_push_subscriptions(id) on delete cascade,
 status text not null default 'pending' check(status in ('pending','sending','sent','cancelled','failed')),
 attempts integer not null default 0,lease_until timestamptz, sent_at timestamptz,last_error text,unique(task_id,revision,subscription_id)
);
alter table public.elite_push_deliveries enable row level security;
revoke all on public.elite_push_deliveries from anon,authenticated;
grant all on public.elite_push_deliveries to service_role;
create function public.elite_claim_reminders() returns jsonb language plpgsql security definer set search_path='' as $$ declare output jsonb; begin
 insert into public.elite_push_deliveries(task_id,revision,subscription_id)
 select t.id,t.revision,s.id from public.elite_tasks t join public.elite_push_subscriptions s on s.user_id=t.user_id
 where not t.completed and t.deleted_at is null and t.remind_minutes is not null and t.due_at-make_interval(mins=>t.remind_minutes)<=now() and t.due_at>=now()-interval '24 hours'
 on conflict do nothing;
 with candidates as (
 select d.id from public.elite_push_deliveries d join public.elite_tasks t on t.id=d.task_id
 where (d.status='pending' or (d.status='sending' and d.lease_until<now())) and d.attempts<4 and (d.lease_until is null or d.lease_until<now())
 and d.revision=t.revision and not t.completed and t.deleted_at is null and t.due_at>=now()-interval '24 hours'
 order by t.due_at limit 30 for update of d skip locked
 ), claimed as (
 update public.elite_push_deliveries d set status='sending',attempts=attempts+1,lease_until=now()+interval '5 minutes' from candidates c where d.id=c.id returning d.*
 ) select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'revision',d.revision,'attempts',d.attempts,'task_id',t.id,'title',t.title,'due_at',t.due_at,'subscription_id',s.id,'endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth)),'[]'::jsonb)
 into output from claimed d join public.elite_tasks t on t.id=d.task_id join public.elite_push_subscriptions s on s.id=d.subscription_id;
 return output; end $$;
revoke all on function public.elite_claim_reminders() from public,anon,authenticated;
grant execute on function public.elite_claim_reminders() to service_role;
commit;
