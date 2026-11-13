CREATE OR REPLACE FUNCTION elite_private.gantt_save_core(target_work uuid, new_phases jsonb, expected_revision integer, freeze_baseline boolean DEFAULT false, confirm_work boolean DEFAULT false, exception_reason text DEFAULT ''::text)
 RETURNS elite_work_plans
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare owner_id uuid:=auth.uid();old_plan public.elite_work_plans;result public.elite_work_plans;p jsonb;pre jsonb;normalized jsonb:='[]';conflicts jsonb;obs jsonb;weight numeric:=0;title text;cid uuid;lvl integer;parent_id text;child_count integer;parent_row jsonb;min_child date;max_child date;
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
  lvl:=coalesce(nullif(p->>'level','')::integer,1);parent_id:=nullif(p->>'parent_id','');
  if lvl not between 1 and 3 then raise exception 'Nivel de actividad no válido'; end if;
  if parent_id is not null then
   select value into parent_row from jsonb_array_elements(new_phases) where value->>'id'=parent_id;
   if parent_row is null or coalesce(nullif(parent_row->>'level','')::integer,1)<>lvl-1 then raise exception 'El elemento superior debe pertenecer al nivel inmediatamente anterior'; end if;
  end if;
  select count(*) into child_count from jsonb_array_elements(new_phases) where value->>'parent_id'=p->>'id';
  if child_count>0 then
   if coalesce((p->>'is_group')::boolean,false)=false or (p->>'weight')::numeric<>0 or coalesce((p->>'milestone')::boolean,false) or nullif(p->>'task_id','') is not null or nullif(p->>'contractor_id','') is not null or jsonb_array_length(coalesce(p->'depends_on','[]'))>0 or jsonb_array_length(coalesce(p->'observations','[]'))>0 or jsonb_array_length(coalesce(p->'economic_observations','[]'))>0 or nullif(p->>'budget','') is not null then raise exception 'Una fase o tarea contenedora no puede tener peso, mediciones, vínculo ni dependencias'; end if;
   select min((value->>'start')::date),max((value->>'end')::date) into min_child,max_child from jsonb_array_elements(new_phases) where value->>'parent_id'=p->>'id';
   if (p->>'start')::date<>min_child or (p->>'end')::date<>max_child then raise exception 'Las fechas de los elementos contenedores deben coincidir con sus descendientes'; end if;
  else
   if coalesce((p->>'is_group')::boolean,false) then raise exception 'El elemento contenedor no tiene tareas'; end if;
   if (p->>'weight')::numeric<0 or ((p->>'weight')::numeric=0 and coalesce((p->>'milestone')::boolean,false)=false) or (p->>'weight')::numeric>100 then raise exception 'Peso de actividad no válido'; end if;
   weight:=weight+(p->>'weight')::numeric;
  end if;
  if jsonb_typeof(coalesce(p->'depends_on','[]')) is distinct from 'array' then raise exception 'Dependencias no válidas'; end if;
  for pre in select value from jsonb_array_elements(coalesce(p->'depends_on','[]')) loop
   if not exists(select 1 from jsonb_array_elements(new_phases) f where f->>'id'=pre#>>'{}' and (f->>'end')::date<(p->>'start')::date and not exists(select 1 from jsonb_array_elements(new_phases) child where child->>'parent_id'=f->>'id')) then raise exception 'Dependencia ausente, cíclica o con fechas incompatibles'; end if;
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
CREATE OR REPLACE FUNCTION elite_private.gantt_schedule(rows jsonb) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $schedule$
declare result jsonb:='[]';ordered jsonb;done text[]:='{}';p jsonb;deps jsonb;earliest date;duration integer;lag integer;changed boolean;lvl integer;
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
 select coalesce(jsonb_agg(r order by o.n),'[]') into ordered from jsonb_array_elements(rows) with ordinality o(p,n) join jsonb_array_elements(result) r on r->>'id'=o.p->>'id';
 result:=ordered;
 for lvl in reverse 3..1 loop
  select coalesce(jsonb_agg(case when coalesce(nullif(row->>'level','')::integer,1)=lvl and exists(select 1 from jsonb_array_elements(result) child where child->>'parent_id'=row->>'id') then
   row||jsonb_build_object('is_group',true,'weight',0,'milestone',false,'task_id',null,'contractor_id',null,'observations','[]'::jsonb,'economic_observations','[]'::jsonb,'budget',null,'actual_start',null,'actual_end',null,'depends_on','[]'::jsonb,'start',(select min((child->>'start')::date) from jsonb_array_elements(result) child where child->>'parent_id'=row->>'id'),'end',(select max((child->>'end')::date) from jsonb_array_elements(result) child where child->>'parent_id'=row->>'id'))
   else row end order by ordinality),'[]') into result from jsonb_array_elements(result) with ordinality;
 end loop;
 return result;
end $schedule$;
REVOKE ALL ON FUNCTION elite_private.gantt_schedule(jsonb) FROM public,anon,authenticated;
