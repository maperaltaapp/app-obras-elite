CREATE OR REPLACE FUNCTION elite_private.gantt_save_core(target_work uuid, new_phases jsonb, expected_revision integer, freeze_baseline boolean DEFAULT false, confirm_work boolean DEFAULT false, exception_reason text DEFAULT ''::text)
 RETURNS elite_work_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare owner_id uuid:=auth.uid();old_plan public.elite_work_plans;result public.elite_work_plans;p jsonb;pre jsonb;normalized jsonb:='[]';conflicts jsonb;obs jsonb;weight numeric:=0;title text;cid uuid;
begin
 if owner_id is null then raise exception 'Inicia sesión'; end if;
 perform pg_advisory_xact_lock(hashtextextended(owner_id::text,0));
 select name into title from public.elite_works where id=target_work and user_id=owner_id and archived_at is null for update;
 if not found then raise exception 'Obra no encontrada'; end if;
 select * into old_plan from public.elite_work_plans where work_id=target_work for update;
 if expected_revision is null or coalesce(old_plan.revision,0)<>expected_revision then raise exception 'La planificación cambió. Actualiza antes de guardar.'; end if;
 if jsonb_typeof(new_phases) is distinct from 'array' or jsonb_array_length(new_phases)>100 or octet_length(new_phases::text)>250000 then raise exception 'Planificación no válida'; end if;
 if (select count(*) from jsonb_array_elements(new_phases))<>(select count(distinct value->>'id') from jsonb_array_elements(new_phases)) then raise exception 'Identificador de fase repetido'; end if;
 for p in select value from jsonb_array_elements(new_phases) loop
  if nullif(p->>'id','') is null or length(trim(coalesce(p->>'name','')))=0 or length(p->>'name')>160 or jsonb_typeof(p->'weight') is distinct from 'number' then raise exception 'Indica nombre y peso de cada fase'; end if;
  perform (p->>'id')::uuid;
  if (p->>'start') is null or (p->>'end') is null or (p->>'start') !~ '^\d{4}-\d{2}-\d{2}$' or (p->>'end') !~ '^\d{4}-\d{2}-\d{2}$' or (p->>'end')::date<(p->>'start')::date or (p->>'end')::date-(p->>'start')::date>3660 then raise exception 'Fechas de fase no válidas'; end if;
  if ((p->>'weight')::numeric<0 or ((p->>'weight')::numeric=0 and coalesce((p->>'milestone')::boolean,false)=false)) or (p->>'weight')::numeric>100 then raise exception 'Peso de fase no válido'; end if;weight:=weight+(p->>'weight')::numeric;
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
end $function$

;
revoke all on function elite_private.gantt_save_core(uuid,jsonb,integer,boolean,boolean,text) from public,anon,authenticated;
create table public.elite_plan_versions (
 id bigint generated always as identity primary key,
 work_id uuid not null references public.elite_works(id) on delete cascade,user_id uuid not null references auth.users(id),
 revision integer not null, snapshot jsonb not null,created_at timestamptz not null default now(),unique(work_id,revision)
);
alter table public.elite_plan_versions enable row level security;
create policy elite_plan_versions_owner on public.elite_plan_versions for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.elite_plan_versions from public,anon,authenticated;
grant select on public.elite_plan_versions to authenticated;
create function elite_private.gantt_schedule(rows jsonb) returns jsonb language plpgsql set search_path='' as $$
declare result jsonb:='[]';done text[]:='{}';p jsonb;q jsonb;deps jsonb;earliest date;duration integer;lag integer;changed boolean;
begin
 while cardinality(done)<jsonb_array_length(rows) loop
 changed:=false;
 for p in select value from jsonb_array_elements(rows) loop
 if p->>'id'=any(done) then continue;end if;
 deps:=coalesce(p->'depends_on','[]');
 if exists(select 1 from jsonb_array_elements_text(deps) d where not d=any(done)) then continue;end if;
 duration:=(p->>'end')::date-(p->>'start')::date;lag:=coalesce((p->>'lag_days')::integer,0);
 if jsonb_array_length(deps)>0 then
 select max((r->>'end')::date)+1+lag into earliest from jsonb_array_elements(result) r where r->>'id' in(select jsonb_array_elements_text(deps));
 p:=p||jsonb_build_object('start',earliest,'end',earliest+duration);
 end if;
 result:=result||jsonb_build_array(p);done:=array_append(done,p->>'id');changed:=true;
 end loop;
 if not changed then raise exception 'Dependencia ausente o circular';end if;
 end loop;
 return (select coalesce(jsonb_agg(r order by o.n),'[]') from jsonb_array_elements(rows) with ordinality o(p,n) join jsonb_array_elements(result) r on r->>'id'=o.p->>'id');
end $$;
revoke all on function elite_private.gantt_schedule(jsonb) from public,anon,authenticated;
create function public.elite_save_gantt(target_work uuid,new_phases jsonb,expected_revision integer,freeze_baseline boolean default false,confirm_work boolean default false,exception_reason text default '') returns public.elite_work_plans language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();old_plan public.elite_work_plans;result public.elite_work_plans;p jsonb;o jsonb;t public.elite_tasks;tid uuid;previous_flag text:=current_setting('elite.gantt_sync',true);normalized jsonb:='[]';
begin
 if uid is null then raise exception 'Inicia sesión';end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text,0));
 if not exists(select 1 from public.elite_works where id=target_work and user_id=uid and archived_at is null) then raise exception 'Obra no encontrada';end if;
 select * into old_plan from public.elite_work_plans where work_id=target_work for update;
 if expected_revision is null or coalesce(old_plan.revision,0)<>expected_revision then raise exception 'La planificación cambió. Actualiza antes de guardar.';end if;
 if jsonb_typeof(new_phases) is distinct from 'array' or jsonb_array_length(new_phases)>100 or octet_length(new_phases::text)>250000 then raise exception 'Planificación no válida';end if;
 if exists(select 1 from jsonb_array_elements(coalesce(old_plan.phases,'[]')) old where not exists(select 1 from jsonb_array_elements(new_phases) candidate where candidate->>'id'=old->>'id')) then raise exception 'No se permite eliminar actividades existentes';end if;
 if exists(select 1 from jsonb_array_elements(new_phases) candidate where nullif(candidate->>'task_id','') is not null group by candidate->>'task_id' having count(*)>1) then raise exception 'Una tarea no puede vincularse dos veces';end if;
 for p in select value from jsonb_array_elements(new_phases) loop
 if coalesce(p->>'section','')<>'' and length(p->>'section')>160 then raise exception 'Fase demasiado larga';end if;
 if coalesce(p->>'activity_status','pending') not in ('pending','doing','blocked','done') then raise exception 'Estado no válido';end if;
 if p->>'lag_days' is not null and ((p->>'lag_days')::numeric<0 or (p->>'lag_days')::numeric<>trunc((p->>'lag_days')::numeric)) then raise exception 'Espera no válida';end if;
 if coalesce((p->>'milestone')::boolean,false) and p->>'start'<>p->>'end' then raise exception 'Un hito tiene una única fecha';end if;
 if p->>'actual_start' is not null and (p->>'actual_start')::date>(now() at time zone 'Europe/Madrid')::date then raise exception 'Inicio real futuro';end if;
 if p->>'actual_end' is not null and ((p->>'actual_start') is null or (p->>'actual_end')::date<(p->>'actual_start')::date or (p->>'actual_end')::date>(now() at time zone 'Europe/Madrid')::date) then raise exception 'Fechas reales no válidas';end if;
 if p->>'budget' is not null and (jsonb_typeof(p->'budget')<>'number' or (p->>'budget')::numeric<0 or (p->>'budget')::numeric>100000000000) then raise exception 'Presupuesto no válido';end if;
 for o in select value from jsonb_array_elements(coalesce(p->'economic_observations','[]')) loop
 if o->>'date' is null or (o->>'date')::date>(now() at time zone 'Europe/Madrid')::date or jsonb_typeof(o->'amount') is distinct from 'number' or (o->>'amount')::numeric<0 then raise exception 'Medición económica no válida';end if;
 end loop;
 tid:=nullif(p->>'task_id','')::uuid;
 if tid is not null then
 select * into t from public.elite_tasks where id=tid and user_id=uid and work_id=target_work and deleted_at is null for update;
 if not found or t.control_id is not null or t.recurrence<>'none' then raise exception 'Tarea no disponible para vincular';end if;
 if p->>'task_updated_at' is null or (p->>'task_updated_at')::timestamptz<>t.updated_at then raise exception 'La tarea vinculada cambió. Actualiza antes de guardar.';end if;
 end if;
 normalized:=normalized||jsonb_build_array(p);
 end loop;
 if old_plan.work_id is not null then insert into public.elite_plan_versions(work_id,user_id,revision,snapshot) values(target_work,uid,old_plan.revision,to_jsonb(old_plan)) on conflict do nothing;end if;
 result:=elite_private.gantt_save_core(target_work,normalized,expected_revision,freeze_baseline,confirm_work,exception_reason);
 perform set_config('elite.gantt_sync','on',true);
 for p in select value from jsonb_array_elements(result.phases) loop
 tid:=nullif(p->>'task_id','')::uuid;
 if tid is not null then
 select * into t from public.elite_tasks where id=tid;
 update public.elite_tasks set start_at=((p->>'start')::date+coalesce((t.start_at at time zone 'Europe/Madrid')::time,'09:00'::time)) at time zone 'Europe/Madrid',
 due_at=((p->>'end')::date+coalesce((t.due_at at time zone 'Europe/Madrid')::time,'18:00'::time)) at time zone 'Europe/Madrid',
 title=p->>'name',status=coalesce(p->>'activity_status',t.status),completed=coalesce(p->>'activity_status',t.status)='done'
 where id=tid and ((start_at at time zone 'Europe/Madrid')::date is distinct from (p->>'start')::date or (due_at at time zone 'Europe/Madrid')::date is distinct from (p->>'end')::date or title is distinct from p->>'name' or status is distinct from coalesce(p->>'activity_status',t.status));
 end if;
 end loop;
 perform set_config('elite.gantt_sync',coalesce(previous_flag,''),true);
 return result;
end $$;
revoke all on function public.elite_save_gantt(uuid,jsonb,integer,boolean,boolean,text) from public,anon;
grant execute on function public.elite_save_gantt(uuid,jsonb,integer,boolean,boolean,text) to authenticated;
create function elite_private.gantt_task_changed() returns trigger language plpgsql security definer set search_path='' as $$
declare plan public.elite_work_plans;rows jsonb;p jsonb;result public.elite_work_plans;duration integer;old_start date;new_start date;old_flag text:=current_setting('elite.gantt_sync',true);
begin
 if old_flag='on' or (new.title,new.start_at,new.due_at,new.status,new.work_id,new.deleted_at) is not distinct from (old.title,old.start_at,old.due_at,old.status,old.work_id,old.deleted_at) then return new;end if;
 select * into plan from public.elite_work_plans where user_id=new.user_id and exists(select 1 from jsonb_array_elements(phases) linked where linked->>'task_id'=new.id::text) for update;
 if not found then return new;end if;
 if new.work_id is distinct from old.work_id or new.deleted_at is distinct from old.deleted_at then raise exception 'Desvincula la tarea del Gantt antes de moverla o archivarla';end if;
 if new.start_at is null or new.due_at is null then raise exception 'La tarea vinculada necesita inicio y fin';end if;
 rows:='[]';
 for p in select value from jsonb_array_elements(plan.phases) loop
 if p->>'task_id'=new.id::text then
 p:=p||jsonb_build_object('name',new.title,'start',(new.start_at at time zone 'Europe/Madrid')::date,'end',(new.due_at at time zone 'Europe/Madrid')::date,'activity_status',new.status);
 if new.status='done' and old.status<>'done' then p:=p||jsonb_build_object('observations',(select coalesce(jsonb_agg(m),'[]') from jsonb_array_elements(coalesce(p->'observations','[]')) m where m->>'date'<>((now() at time zone 'Europe/Madrid')::date)::text)||jsonb_build_array(jsonb_build_object('date',(now() at time zone 'Europe/Madrid')::date,'percent',100)));end if;
 if jsonb_array_length(coalesce(p->'depends_on','[]'))>0 then
 select max((q->>'end')::date)+1 into old_start from jsonb_array_elements(plan.phases) q where q->>'id' in(select jsonb_array_elements_text(p->'depends_on'));
 if (p->>'start')::date<old_start then raise exception 'La fecha incumple una dependencia. Modifica la planificación desde Gantt';end if;
 p:=p||jsonb_build_object('lag_days',(p->>'start')::date-old_start);
 end if;
 end if;
 if nullif(p->>'task_id','') is not null then p:=p||jsonb_build_object('task_updated_at',(select updated_at from public.elite_tasks where id=(p->>'task_id')::uuid));end if;
 rows:=rows||jsonb_build_array(p);
 end loop;
 rows:=elite_private.gantt_schedule(rows);
 result:=public.elite_save_gantt(plan.work_id,rows,plan.revision,false,plan.confirmed_at is not null,'');
 return new;
end $$;
revoke all on function elite_private.gantt_task_changed() from public,anon,authenticated;
create trigger elite_gantt_task_sync after update on public.elite_tasks for each row execute function elite_private.gantt_task_changed();
