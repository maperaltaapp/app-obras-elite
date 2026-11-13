begin;
create table if not exists public.elite_work_checklist_items (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id),
 work_id uuid not null,
 section text not null check(section in ('prep','providers','execution','close')),
 title text not null check(length(btrim(title)) between 1 and 240),
 notes text not null default '' check(length(notes)<=5000),
 due_date date,
 completed_at timestamptz,
 position numeric not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(work_id,user_id) references public.elite_works(id,user_id) on delete cascade,
 check(due_date is null or due_date between '2000-01-01' and '2100-12-31')
);
create index if not exists elite_work_checklist_order on public.elite_work_checklist_items(user_id,work_id,section,position,created_at);
alter table public.elite_work_checklist_items enable row level security;
create policy elite_work_checklist_owner on public.elite_work_checklist_items for all to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
revoke all on public.elite_work_checklist_items from anon,authenticated;
grant select,insert,update,delete on public.elite_work_checklist_items to authenticated;
grant all on public.elite_work_checklist_items to service_role;
create or replace function elite_private.checklist_touch() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' then new.user_id:=old.user_id;new.created_at:=old.created_at;end if;
 new.updated_at:=now();return new;
end $$;
revoke all on function elite_private.checklist_touch() from public,anon,authenticated;
drop trigger if exists elite_work_checklist_touch on public.elite_work_checklist_items;
create trigger elite_work_checklist_touch before update on public.elite_work_checklist_items for each row execute function elite_private.checklist_touch();
commit;
