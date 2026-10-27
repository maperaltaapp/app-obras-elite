alter table public.elite_work_contractors add column contractor_id uuid,
 add constraint elite_control_contractor_owner foreign key(contractor_id,user_id)
 references public.elite_contractors(id,user_id);
insert into public.elite_contractors(user_id,name,kind,trade,capacity)
select c.user_id,c.name,min(c.kind),min(c.scope),1 from public.elite_work_contractors c
where not exists(select 1 from public.elite_contractors p where p.user_id=c.user_id and p.name=c.name)
group by c.user_id,c.name;
update public.elite_work_contractors c set contractor_id=(select p.id from public.elite_contractors p where p.user_id=c.user_id and p.name=c.name order by p.created_at,p.id limit 1)
where c.contractor_id is null;
create index elite_control_registry_link on public.elite_work_contractors(contractor_id,user_id);
create function public.elite_control_registry_snapshot() returns trigger language plpgsql security invoker set search_path='' as $$
declare p public.elite_contractors;
begin
 if new.contractor_id is null then raise exception 'Selecciona un proveedor o subcontrata del registro';end if;
 select * into p from public.elite_contractors where id=new.contractor_id and user_id=new.user_id;
 if not found then raise exception 'Proveedor no disponible para esta cuenta';end if;
 new.name:=p.name;new.scope:=p.trade;new.kind:=p.kind;return new;
end; $$;
revoke all on function public.elite_control_registry_snapshot() from public,anon;
create trigger zz_elite_control_registry_snapshot before insert or update on public.elite_work_contractors
 for each row execute function public.elite_control_registry_snapshot();
create function public.elite_registry_propagate() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if (new.name,new.trade,new.kind) is distinct from (old.name,old.trade,old.kind) then
  update public.elite_work_contractors set name=new.name,scope=new.trade,kind=new.kind where contractor_id=new.id and user_id=new.user_id;
 end if;return new;
end; $$;
revoke all on function public.elite_registry_propagate() from public,anon;
create trigger elite_registry_propagate after update on public.elite_contractors for each row execute function public.elite_registry_propagate();
