-- Private, account-scoped photo/PDF uploads. File bytes are managed only by the Storage API.
begin;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('elite-work-files','elite-work-files',false,20971520,array['image/jpeg','image/png','image/webp','image/gif','image/avif','image/heic','image/heif','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists elite_work_files_read on storage.objects;
create policy elite_work_files_read on storage.objects for select to authenticated using(
 bucket_id='elite-work-files' and (storage.foldername(storage.objects.name))[1]=(select auth.uid())::text
 and exists(select 1 from public.elite_works w where w.id::text=(storage.foldername(storage.objects.name))[2] and w.user_id=(select auth.uid()))
);
drop policy if exists elite_work_files_insert on storage.objects;
create policy elite_work_files_insert on storage.objects for insert to authenticated with check(
 bucket_id='elite-work-files' and (storage.foldername(storage.objects.name))[1]=(select auth.uid())::text
 and array_length(storage.foldername(storage.objects.name),1)=2
 and exists(select 1 from public.elite_works w where w.id::text=(storage.foldername(storage.objects.name))[2] and w.user_id=(select auth.uid()) and w.archived_at is null)
);
drop policy if exists elite_work_files_delete on storage.objects;
create policy elite_work_files_delete on storage.objects for delete to authenticated using(
 bucket_id='elite-work-files' and (storage.foldername(storage.objects.name))[1]=(select auth.uid())::text
 and exists(select 1 from public.elite_works w where w.id::text=(storage.foldername(storage.objects.name))[2] and w.user_id=(select auth.uid()))
);
-- Prevent orphaning stored files when an older app or a direct API request deletes a work.
create or replace function public.elite_delete_work(target_work uuid, expected_updated_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare owner_id uuid:=auth.uid(); current_stamp timestamptz;
begin
 if owner_id is null then raise exception 'Inicia sesión'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(owner_id::text,0));
 select updated_at into current_stamp from public.elite_works where id=target_work and user_id=owner_id for update;
 if not found then raise exception 'Obra no encontrada'; end if;
 if expected_updated_at is null or current_stamp is distinct from expected_updated_at then raise exception 'La obra cambió. Actualiza antes de eliminar.'; end if;
 if exists(select 1 from storage.objects where bucket_id='elite-work-files' and (storage.foldername(storage.objects.name))[1]=owner_id::text and (storage.foldername(storage.objects.name))[2]=target_work::text) then raise exception 'La obra tiene adjuntos. Elimínala desde la versión actual de Elite para borrar también sus archivos.'; end if;
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
