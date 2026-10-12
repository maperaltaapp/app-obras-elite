-- Apply after tasks-schema.sql. Additive migration; run once in a transaction.
begin;
-- Keep a private snapshot of existing own tasks before extending the schema.
create table if not exists elite_private.native_migration_backup (
 name text primary key, captured_at timestamptz not null default now(), rows jsonb not null
);
alter table elite_private.native_migration_backup enable row level security;
revoke all on elite_private.native_migration_backup from public,anon,authenticated;
insert into elite_private.native_migration_backup(name,rows)
 select 'tasks-before-native-2026-10-12',coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.elite_tasks t
 on conflict(name) do nothing;
create table if not exists public.elite_works (
 id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references auth.users(id),
 name text not null check(length(trim(name)) between 1 and 160), description text not null default '',
 start_date date, end_date date, archived_at timestamptz, progress integer check(progress between 0 and 100),
 trello_id text, stages jsonb not null default '[]', chat_url text not null default '',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(user_id,trello_id), unique(id,user_id), check(end_date is null or start_date is null or end_date>=start_date),
 check(jsonb_typeof(stages)='array' and jsonb_array_length(stages)<=100)
);
alter table public.elite_works enable row level security;
create policy elite_works_owner on public.elite_works for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
revoke all on public.elite_works from anon,authenticated;
grant select,insert,update on public.elite_works to authenticated;
grant all on public.elite_works to service_role;
alter table public.elite_tasks
 add column if not exists work_id uuid,
 add column if not exists description text not null default '',
 add column if not exists start_at timestamptz,
 add column if not exists status text not null default 'pending' check(status in ('pending','doing','blocked','done')),
 add column if not exists priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
 add column if not exists labels jsonb not null default '[]',
 add column if not exists checklists jsonb not null default '[]',
 add column if not exists stage text not null default 'General',
 add column if not exists recurrence text not null default 'none' check(recurrence in ('none','daily','weekly','monthly')),
 add column if not exists recurrence_timezone text not null default 'Europe/Madrid',
 add column if not exists previous_task_id uuid unique references public.elite_tasks(id),
 add column if not exists trello_id text,
 add column if not exists source_url text not null default '',
 add column if not exists position numeric not null default 0;
-- Composite FK prevents linking a task to a different user's work.
alter table public.elite_tasks add constraint elite_task_work_owner foreign key(work_id,user_id) references public.elite_works(id,user_id);
alter table public.elite_tasks add constraint elite_task_dates check(start_at is null or due_at is null or start_at<=due_at);
alter table public.elite_tasks add constraint elite_task_lightweight check(length(description)<=50000 and jsonb_typeof(labels)='array' and jsonb_array_length(labels)<=50 and jsonb_typeof(checklists)='array' and octet_length(checklists::text)<=250000);
create unique index if not exists elite_task_trello_unique on public.elite_tasks(user_id,trello_id) where trello_id is not null;
update public.elite_tasks set status='done' where completed;
create table public.elite_history (
 id bigint generated always as identity primary key, user_id uuid not null, entity_id uuid not null,
 entity_type text not null, action text not null, title text not null, fields jsonb not null default '[]',
 created_at timestamptz not null default now()
);
alter table public.elite_history enable row level security;
create policy elite_history_owner on public.elite_history for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.elite_history from anon,authenticated;
grant select on public.elite_history to authenticated;
grant all on public.elite_history to service_role;
create index elite_history_entity on public.elite_history(user_id,entity_id,created_at desc);
create function elite_private.native_history() returns trigger language plpgsql security definer set search_path='' as $$
declare changed jsonb; heading text;
begin
 heading:=coalesce(to_jsonb(new)->>'title',to_jsonb(new)->>'name','');
 if tg_op='UPDATE' then
  select coalesce(jsonb_agg(key),'[]'::jsonb) into changed from jsonb_each(to_jsonb(new)) where value is distinct from to_jsonb(old)->key and key not in ('updated_at','revision');
  if changed='[]'::jsonb then return new; end if;
 end if;
 insert into public.elite_history(user_id,entity_id,entity_type,action,title,fields) values(new.user_id,new.id,tg_table_name,case when tg_op='INSERT' then 'Creación' else 'Actualización' end,heading,coalesce(changed,'[]'::jsonb));
 return new;
end $$;
create trigger elite_tasks_history after insert or update on public.elite_tasks for each row execute function elite_private.native_history();
create trigger elite_works_history after insert or update on public.elite_works for each row execute function elite_private.native_history();
create function elite_private.native_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' then new.user_id:=old.user_id; new.created_at:=old.created_at; end if;
 new.updated_at:=now();
 if tg_table_name='elite_tasks' then
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=new.recurrence_timezone) then raise exception 'Zona horaria no válida'; end if;
  if jsonb_typeof(new.checklists)<>'array' or jsonb_array_length(new.checklists)>100 then raise exception 'Checklists no válidos'; end if;
  if exists(select 1 from jsonb_array_elements(new.checklists) c where jsonb_typeof(c->'items') is distinct from 'array' or jsonb_typeof(c->'name') is distinct from 'string') then raise exception 'Estructura de checklist no válida'; end if;
  if exists(select 1 from jsonb_array_elements(new.checklists) c cross join lateral jsonb_array_elements(c->'items') i where jsonb_typeof(i->'text') is distinct from 'string' or jsonb_typeof(i->'done') is distinct from 'boolean') then raise exception 'Elemento de checklist no válido'; end if;
  if new.recurrence<>'none' and new.due_at is null then raise exception 'La repetición necesita vencimiento'; end if;
  if tg_op='UPDATE' and new.completed is distinct from old.completed then new.status:=case when new.completed then 'done' else 'pending' end;
  else new.completed:=(new.status='done'); end if;
 end if;
 return new;
end $$;
-- Alphabetical trigger ordering: normalize completion before existing revision trigger.
create trigger elite_tasks_native_guard before insert or update on public.elite_tasks for each row execute function elite_private.native_guard();
create trigger elite_works_guard before update on public.elite_works for each row execute function elite_private.native_guard();
create function public.elite_complete_task(task_id uuid, expected_updated_at timestamptz) returns uuid language plpgsql security invoker set search_path='' as $$
declare t public.elite_tasks; next_id uuid; next_due timestamptz; next_start timestamptz; step interval; reset_checks jsonb;
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
 select coalesce(jsonb_agg(c || jsonb_build_object('items',coalesce((select jsonb_agg(i || '{"done":false}'::jsonb) from jsonb_array_elements(c->'items') i),'[]'::jsonb))),'[]'::jsonb) into reset_checks from jsonb_array_elements(t.checklists) c;
 insert into public.elite_tasks(user_id,title,category,work_name,work_id,description,start_at,due_at,remind_minutes,status,priority,labels,checklists,stage,recurrence,recurrence_timezone,previous_task_id)
 values(t.user_id,t.title,t.category,t.work_name,t.work_id,t.description,next_start,next_due,t.remind_minutes,'pending',t.priority,t.labels,reset_checks,t.stage,t.recurrence,t.recurrence_timezone,t.id)
 on conflict(previous_task_id) do nothing returning id into next_id;
 return next_id;
end $$;
revoke all on function public.elite_complete_task(uuid,timestamptz) from public,anon;
grant execute on function public.elite_complete_task(uuid,timestamptz) to authenticated;
commit;
