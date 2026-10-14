begin;
create or replace function public.elite_delete_work(target_work uuid, expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); current_stamp timestamptz;
begin
 if owner_id is null then raise exception 'Inicia sesión'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text,0));
 select updated_at into current_stamp from public.elite_works where id=target_work and user_id=owner_id for update;
 if not found then raise exception 'Obra no encontrada'; end if;
 if expected_updated_at is null or current_stamp is distinct from expected_updated_at then raise exception 'La obra cambió. Actualiza antes de eliminar.'; end if;
 -- Lock all tasks before clearing recurrence links and removing their history.
 perform id from public.elite_tasks where work_id=target_work and user_id=owner_id for update;
 update public.elite_tasks set previous_task_id=null where user_id=owner_id and previous_task_id in(select id from public.elite_tasks where work_id=target_work and user_id=owner_id);
 delete from public.elite_history where user_id=owner_id and (entity_id=target_work or entity_id in(select id from public.elite_tasks where work_id=target_work and user_id=owner_id));
 delete from public.elite_plan_exceptions where work_id=target_work and user_id=owner_id;
 delete from public.elite_work_plans where work_id=target_work and user_id=owner_id;
 delete from public.elite_tasks where work_id=target_work and user_id=owner_id;
 delete from public.elite_works where id=target_work and user_id=owner_id;
end $$;
revoke all on function public.elite_delete_work(uuid,timestamptz) from public,anon;
grant execute on function public.elite_delete_work(uuid,timestamptz) to authenticated;
notify pgrst, 'reload schema';
commit;
