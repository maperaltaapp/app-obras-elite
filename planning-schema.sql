-- Additive, apply after native-schema.sql. Candidate: test before production.
begin;
create table public.elite_contractors (
 id uuid primary key default gen_random_uuid(),user_id uuid not null default auth.uid() references auth.users(id),
 name text not null check(length(trim(name)) between 1 and 160),kind text not null check(kind in('subcontractor','supplier')),
 trade text not null default '',email text not null default '',phone text not null default '',notes text not null default '',
 capacity integer not null check(capacity between 1 and 50),archived_at timestamptz,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(id,user_id)
);
alter table public.elite_contractors enable row level security;
create policy elite_contractors_owner on public.elite_contractors for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
revoke all on public.elite_contractors from public,anon,authenticated;
grant select,insert,update on public.elite_contractors to authenticated;
grant all on public.elite_contractors to service_role;
create trigger elite_contractors_guard before update on public.elite_contractors for each row execute function elite_private.native_guard();
create trigger elite_contractors_history after insert or update on public.elite_contractors for each row execute function elite_private.native_history();
create table public.elite_work_plans (
 work_id uuid primary key,user_id uuid not null default auth.uid(),phases jsonb not null default '[]',
 baseline jsonb not null default '[]',baseline_at timestamptz,confirmed_at timestamptz,
 revision integer not null default 1,updated_at timestamptz not null default now(),
 foreign key(work_id,user_id) references public.elite_works(id,user_id),
 check(jsonb_typeof(phases)='array' and jsonb_array_length(phases)<=100),
 check(jsonb_typeof(baseline)='array' and octet_length(phases::text)<=250000)
);
alter table public.elite_work_plans enable row level security;
create policy elite_work_plans_owner on public.elite_work_plans for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.elite_work_plans from public,anon,authenticated;
grant select on public.elite_work_plans to authenticated;
grant all on public.elite_work_plans to service_role;
create function elite_private.protect_plan_baseline() returns trigger language plpgsql set search_path='' as $$ begin
 if old.baseline_at is not null and (new.baseline,new.baseline_at) is distinct from (old.baseline,old.baseline_at) then raise exception 'La planificación original no se puede sobrescribir'; end if;
 new.user_id:=old.user_id;new.work_id:=old.work_id;return new;
end $$;
create trigger elite_plan_baseline before update on public.elite_work_plans for each row execute function elite_private.protect_plan_baseline();
create table public.elite_plan_exceptions(id uuid primary key default gen_random_uuid(),user_id uuid not null,work_id uuid not null,reason text not null,conflicts jsonb not null,created_at timestamptz not null default now(),foreign key(work_id,user_id) references public.elite_works(id,user_id));
alter table public.elite_plan_exceptions enable row level security;
create policy elite_exceptions_owner on public.elite_plan_exceptions for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.elite_plan_exceptions from public,anon,authenticated;
grant select on public.elite_plan_exceptions to authenticated;
grant all on public.elite_plan_exceptions to service_role;
create function public.elite_save_plan(target_work uuid,new_phases jsonb,expected_revision integer,freeze_baseline boolean default false,confirm_work boolean default false,exception_reason text default '') returns public.elite_work_plans language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid();old_plan public.elite_work_plans;result public.elite_work_plans;p jsonb;pre jsonb;normalized jsonb:='[]';conflicts jsonb;obs jsonb;weight numeric:=0;title text;cid uuid;
begin
 if owner_id is null then raise exception 'Inicia sesión'; end if;
 perform pg_advisory_xact_lock(hashtextextended(owner_id::text,0));
 select name into title from public.elite_works where id=target_work and user_id=owner_id and archived_at is null for update;
 if not found then raise exception 'Obra no encontrada'; end if;
 select * into old_plan from public.elite_work_plans where work_id=target_work for update;
 if coalesce(old_plan.revision,0)<>expected_revision then raise exception 'La planificación cambió. Actualiza antes de guardar.'; end if;
 if jsonb_typeof(new_phases) is distinct from 'array' or jsonb_array_length(new_phases)>100 or octet_length(new_phases::text)>250000 then raise exception 'Planificación no válida'; end if;
 if (select count(*) from jsonb_array_elements(new_phases))<>(select count(distinct value->>'id') from jsonb_array_elements(new_phases)) then raise exception 'Identificador de fase repetido'; end if;
 for p in select value from jsonb_array_elements(new_phases) loop
  if nullif(p->>'id','') is null or length(trim(coalesce(p->>'name','')))=0 or length(p->>'name')>160 or jsonb_typeof(p->'weight') is distinct from 'number' then raise exception 'Indica nombre y peso de cada fase'; end if;
  perform (p->>'id')::uuid;
  if (p->>'start') is null or (p->>'end') is null or (p->>'start') !~ '^\d{4}-\d{2}-\d{2}$' or (p->>'end') !~ '^\d{4}-\d{2}-\d{2}$' or (p->>'end')::date<(p->>'start')::date or (p->>'end')::date-(p->>'start')::date>3660 then raise exception 'Fechas de fase no válidas'; end if;
  if (p->>'weight')::numeric<=0 or (p->>'weight')::numeric>100 then raise exception 'Peso de fase no válido'; end if;weight:=weight+(p->>'weight')::numeric;
  if jsonb_typeof(coalesce(p->'depends_on','[]')) is distinct from 'array' then raise exception 'Dependencias no válidas'; end if;
  for pre in select value from jsonb_array_elements(coalesce(p->'depends_on','[]')) loop
   if not exists(select 1 from jsonb_array_elements(new_phases) f where f->>'id'=pre#>>'{}' and (f->>'end')::date<(p->>'start')::date) then raise exception 'Dependencia ausente, cíclica o con fechas incompatibles'; end if;
  end loop;
  cid:=nullif(p->>'contractor_id','')::uuid;
  if cid is not null and not exists(select 1 from public.elite_contractors where id=cid and user_id=owner_id and archived_at is null) then raise exception 'Subcontrata no encontrada'; end if;
  if jsonb_typeof(coalesce(p->'observations','[]')) is distinct from 'array' then raise exception 'Mediciones no válidas'; end if;
  if (select count(*) from jsonb_array_elements(coalesce(p->'observations','[]')))<>(select count(distinct value->>'date') from jsonb_array_elements(coalesce(p->'observations','[]'))) then raise exception 'Medición diaria repetida'; end if;
  for obs in select value from jsonb_array_elements(coalesce(p->'observations','[]')) loop
   if nullif(obs->>'date','') is null or (obs->>'date')::date>(now() at time zone 'Europe/Madrid')::date or jsonb_typeof(obs->'percent') is distinct from 'number' or (obs->>'percent')::numeric not between 0 and 100 then raise exception 'Medición física no válida o futura'; end if;
  end loop;
  if coalesce(p->>'request_status','pending') not in('pending','requested','confirmed') then raise exception 'Estado de subcontrata no válido'; end if;
  if p->>'request_status'='confirmed' and cid is null then raise exception 'Asigna una subcontrata antes de confirmarla'; end if;
  select value into pre from jsonb_array_elements(coalesce(old_plan.phases,'[]')) where value->>'id'=p->>'id';
  p:=p-'contractor_confirmed_at';
  if p->>'request_status'='confirmed' then p:=p||jsonb_build_object('contractor_confirmed_at',case when pre->>'request_status'='confirmed' and pre->>'contractor_id'=p->>'contractor_id' then coalesce(pre->>'contractor_confirmed_at',now()::text) else now()::text end); end if;
  normalized:=normalized||jsonb_build_array(p);
 end loop;
 if jsonb_array_length(new_phases)>0 and abs(weight-100)>0.001 then raise exception 'Los pesos deben sumar 100 %%'; end if;
 if freeze_baseline and jsonb_array_length(new_phases)=0 then raise exception 'Añade fases antes de guardar la planificación original'; end if;
 -- Capacity is checked at every interval start using current dates and distinct works.
 with plans as (
  select wp.work_id,wp.phases from public.elite_work_plans wp join public.elite_works w on w.id=wp.work_id where wp.user_id=owner_id and wp.work_id<>target_work and w.archived_at is null
  union all select target_work,normalized
 ), intervals as (
  select q.work_id,(f->>'contractor_id')::uuid contractor_id,(f->>'start')::date starts,(f->>'end')::date ends from plans q cross join lateral jsonb_array_elements(q.phases) f where nullif(f->>'contractor_id','') is not null
 ), checks as (
  select i.contractor_id,i.starts,array_agg(distinct a.work_id) works,c.capacity from intervals i join intervals a on a.contractor_id=i.contractor_id and a.starts<=i.starts and a.ends>=i.starts join public.elite_contractors c on c.id=i.contractor_id group by i.contractor_id,i.starts,c.capacity
 ) select coalesce(jsonb_agg(to_jsonb(c)),'[]') into conflicts from checks c where cardinality(c.works)>c.capacity and target_work=any(c.works);
 if conflicts<>'[]'::jsonb and length(trim(exception_reason))=0 then raise exception 'CAPACITY_CONFLICT' using detail=conflicts::text; end if;
 insert into public.elite_work_plans(work_id,user_id,phases,baseline,baseline_at,confirmed_at)
 values(target_work,owner_id,normalized,case when freeze_baseline then normalized else '[]'::jsonb end,case when freeze_baseline then now() else null end,case when confirm_work then now() else null end)
 on conflict(work_id) do update set phases=excluded.phases,
 baseline=case when elite_work_plans.baseline_at is null and freeze_baseline then normalized else elite_work_plans.baseline end,
 baseline_at=case when elite_work_plans.baseline_at is null and freeze_baseline then now() else elite_work_plans.baseline_at end,
 confirmed_at=case when confirm_work then coalesce(elite_work_plans.confirmed_at,now()) else null end,
 revision=elite_work_plans.revision+1,updated_at=now() returning * into result;
 if jsonb_array_length(normalized)>0 then update public.elite_works set start_date=(select min((value->>'start')::date) from jsonb_array_elements(normalized)),end_date=(select max((value->>'end')::date) from jsonb_array_elements(normalized)) where id=target_work; end if;
 if conflicts<>'[]'::jsonb then insert into public.elite_plan_exceptions(user_id,work_id,reason,conflicts) values(owner_id,target_work,left(trim(exception_reason),2000),conflicts); end if;
 insert into public.elite_history(user_id,entity_id,entity_type,action,title,fields) values(owner_id,target_work,'elite_work_plans',case when conflicts<>'[]'::jsonb then 'Excepción de capacidad: '||left(trim(exception_reason),500) else 'Planificación actualizada' end,title,jsonb_build_array('phases',case when freeze_baseline then 'baseline' else 'planning' end));
 return result;
end $$;
revoke all on function public.elite_save_plan(uuid,jsonb,integer,boolean,boolean,text) from public,anon;
grant execute on function public.elite_save_plan(uuid,jsonb,integer,boolean,boolean,text) to authenticated;
commit;
