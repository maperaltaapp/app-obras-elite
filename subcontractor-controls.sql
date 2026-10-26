create table public.elite_work_contractors (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id),
 work_id uuid not null,
 name text not null check(length(btrim(name)) between 1 and 160),
 scope text not null default '' check(length(scope)<=2000),
 kind text not null default 'subcontractor' check(kind in ('subcontractor','supplier')),
 entry_date date,
 notes text not null default '' check(length(notes)<=5000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(id,work_id,user_id),
 foreign key(work_id,user_id) references public.elite_works(id,user_id) on delete cascade
);
create index elite_work_contractors_owner_work on public.elite_work_contractors(user_id,work_id);
alter table public.elite_work_contractors enable row level security;
revoke all on public.elite_work_contractors from anon;
grant select,insert,update,delete on public.elite_work_contractors to authenticated;
create policy elite_work_contractors_owner on public.elite_work_contractors for all to authenticated
 using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create trigger elite_work_contractors_guard before insert or update on public.elite_work_contractors
 for each row execute function elite_private.native_guard();
create trigger elite_work_contractors_history after insert or update on public.elite_work_contractors
 for each row execute function elite_private.native_history();

alter table public.elite_tasks add column control_id uuid,
 add column control_step text,
 add column control_na boolean not null default false,
 add constraint elite_tasks_control_owner foreign key(control_id,work_id,user_id)
 references public.elite_work_contractors(id,work_id,user_id) on delete cascade,
 add constraint elite_tasks_control_pair check (
 (control_id is null and control_step is null and not control_na) or
 (control_id is not null and work_id is not null and control_step is not null and
 control_step in ('mail','plans','documents','vehicles','contract','training','magda') and recurrence='none')),
 add constraint elite_tasks_control_unique unique(control_id,control_step);
create function public.elite_control_task_guard() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.control_id,new.control_step) is distinct from (old.control_id,old.control_step) then
  raise exception 'No se puede cambiar la vinculación de una etapa';
 end if;
 if not new.completed then new.control_na:=false; end if;
 return new;
end $$;
revoke all on function public.elite_control_task_guard() from public,anon;
create trigger zz_elite_control_task_guard before insert or update on public.elite_tasks
 for each row execute function public.elite_control_task_guard();

create function public.elite_control_rename() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.name is distinct from old.name then
  update public.elite_tasks set title=left(case control_step
   when 'mail' then 'Mail' when 'plans' then 'Planos' when 'documents' then 'Documentación'
   when 'vehicles' then 'Vehículos' when 'contract' then 'Contrato'
   when 'training' then 'Acción formativa' when 'magda' then 'Aviso a Magda' end || ' · ' || new.name,240)
  where control_id=new.id and user_id=new.user_id;
 end if;
 return new;
end $$;
revoke all on function public.elite_control_rename() from public,anon;
create trigger elite_control_rename after update on public.elite_work_contractors
 for each row execute function public.elite_control_rename();
