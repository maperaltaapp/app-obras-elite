begin;
alter table public.elite_tasks add column if not exists progress_pct numeric(5,2) check(progress_pct between 0 and 100);
create or replace function public.elite_save_gantt(target_work uuid,new_phases jsonb,expected_revision integer,freeze_baseline boolean default false,confirm_work boolean default false,exception_reason text default '') returns public.elite_work_plans language plpgsql security definer set search_path='' as $$
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
 title=p->>'name',status=coalesce(p->>'activity_status',t.status),completed=coalesce(p->>'activity_status',t.status)='done',progress_pct=case when coalesce(p->>'activity_status',t.status)='done' then 100 else (select (o->>'percent')::numeric from jsonb_array_elements(coalesce(p->'observations','[]')) o where o->>'date'<=(now() at time zone 'Europe/Madrid')::date::text order by o->>'date' desc limit 1) end
 where id=tid and ((start_at at time zone 'Europe/Madrid')::date is distinct from (p->>'start')::date or (due_at at time zone 'Europe/Madrid')::date is distinct from (p->>'end')::date or title is distinct from p->>'name' or status is distinct from coalesce(p->>'activity_status',t.status) or progress_pct is distinct from case when coalesce(p->>'activity_status',t.status)='done' then 100 else (select (o->>'percent')::numeric from jsonb_array_elements(coalesce(p->'observations','[]')) o where o->>'date'<=(now() at time zone 'Europe/Madrid')::date::text order by o->>'date' desc limit 1) end);
 end if;
 end loop;
 perform set_config('elite.gantt_sync',coalesce(previous_flag,''),true);
 return result;
end $$;
revoke all on function public.elite_save_gantt(uuid,jsonb,integer,boolean,boolean,text) from public,anon;
grant execute on function public.elite_save_gantt(uuid,jsonb,integer,boolean,boolean,text) to authenticated;
create or replace function elite_private.gantt_task_changed() returns trigger language plpgsql security definer set search_path='' as $$
declare plan public.elite_work_plans;rows jsonb;p jsonb;result public.elite_work_plans;duration integer;old_start date;new_start date;old_flag text:=current_setting('elite.gantt_sync',true);
begin
 if old_flag='on' or (new.title,new.start_at,new.due_at,new.status,new.progress_pct,new.work_id,new.deleted_at) is not distinct from (old.title,old.start_at,old.due_at,old.status,old.progress_pct,old.work_id,old.deleted_at) then return new;end if;
 select * into plan from public.elite_work_plans where user_id=new.user_id and exists(select 1 from jsonb_array_elements(phases) linked where linked->>'task_id'=new.id::text) for update;
 if not found then return new;end if;
 if new.work_id is distinct from old.work_id or new.deleted_at is distinct from old.deleted_at then raise exception 'Desvincula la tarea del Gantt antes de moverla o archivarla';end if;
 if new.start_at is null or new.due_at is null then raise exception 'La tarea vinculada necesita inicio y fin';end if;
 rows:='[]';
 for p in select value from jsonb_array_elements(plan.phases) loop
 if p->>'task_id'=new.id::text then
 p:=p||jsonb_build_object('name',new.title,'start',(new.start_at at time zone 'Europe/Madrid')::date,'end',(new.due_at at time zone 'Europe/Madrid')::date,'activity_status',new.status);
 if new.progress_pct=100 and new.status<>'done' then p:=p||jsonb_build_object('activity_status','done');elsif new.progress_pct is not null and new.progress_pct<100 and new.status='done' then p:=p||jsonb_build_object('activity_status','pending');end if;
 if new.progress_pct is distinct from old.progress_pct then p:=p||jsonb_build_object('observations',(select coalesce(jsonb_agg(m),'[]') from jsonb_array_elements(coalesce(p->'observations','[]')) m where m->>'date'<>((now() at time zone 'Europe/Madrid')::date)::text)||case when new.progress_pct is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('date',(now() at time zone 'Europe/Madrid')::date,'percent',new.progress_pct)) end);end if;
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
commit;
