create function public.elite_daily_rows_valid(rows jsonb, kind text) returns boolean
language plpgsql immutable security invoker set search_path='' as $$
declare r jsonb;
begin
 if jsonb_typeof(rows)<>'array' or jsonb_array_length(rows)>100 then return false;end if;
 for r in select value from jsonb_array_elements(rows) loop
  if jsonb_typeof(r)<>'object' or jsonb_typeof(r->'name') is distinct from 'string' or length(btrim(r->>'name')) not between 1 and 160 then return false;end if;
  if kind='incident' then
   if (r->>'state') not in ('open','resolved') or r->>'state' is null or (r->>'severity') not in ('info','warning','critical') or r->>'severity' is null then return false;end if;
  else
   if jsonb_typeof(r->'quantity') is distinct from 'number' or (r->>'quantity')::numeric not between 1 and 500 or (r->>'quantity')::numeric<>trunc((r->>'quantity')::numeric) then return false;end if;
   if r->>'unit' not in ('hour','day') or r->>'unit' is null or jsonb_typeof(r->'duration') is distinct from 'number' then return false;end if;
   if (r->>'duration')::numeric<=0 or (r->>'duration')::numeric>(case when r->>'unit'='hour' then 24 else 1 end) then return false;end if;
   if r->'rate' is not null and r->'rate'<>'null'::jsonb then
    if jsonb_typeof(r->'rate')<>'number' or (r->>'rate')::numeric not between 0 and 1000000 then return false;end if;
   end if;
   if kind='labor' and jsonb_typeof(r->'admin') is distinct from 'boolean' then return false;end if;
  end if;
 end loop;
 return true;
exception when others then return false;
end; $$;
revoke all on function public.elite_daily_rows_valid(jsonb,text) from public,anon;
grant execute on function public.elite_daily_rows_valid(jsonb,text) to authenticated;
create table public.elite_daily_reports (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null default auth.uid() references auth.users(id),
 work_id uuid not null,
 report_date date not null check(report_date between '2000-01-01' and '2100-12-31'),
 labor jsonb not null default '[]'::jsonb check(public.elite_daily_rows_valid(labor,'labor')),
 machines jsonb not null default '[]'::jsonb check(public.elite_daily_rows_valid(machines,'machine')),
 incidents jsonb not null default '[]'::jsonb check(public.elite_daily_rows_valid(incidents,'incident')),
 progress_pct numeric(5,2) check(progress_pct between 0 and 100),
 progress_note text not null default '' check(length(progress_note)<=10000),
 notes text not null default '' check(length(notes)<=10000),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(work_id,report_date),
 foreign key(work_id,user_id) references public.elite_works(id,user_id) on delete cascade
);
create index elite_daily_reports_owner_date on public.elite_daily_reports(user_id,report_date desc,work_id);
alter table public.elite_daily_reports enable row level security;
revoke all on public.elite_daily_reports from anon;
grant select,insert,update,delete on public.elite_daily_reports to authenticated;
create policy elite_daily_reports_owner on public.elite_daily_reports for all to authenticated
 using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create trigger elite_daily_reports_guard before insert or update on public.elite_daily_reports
 for each row execute function elite_private.native_guard();
create trigger elite_daily_reports_history after insert or update on public.elite_daily_reports
 for each row execute function elite_private.native_history();
