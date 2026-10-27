create or replace function public.elite_daily_rows_valid(rows jsonb, kind text) returns boolean
language plpgsql immutable security invoker set search_path='' as $$
declare r jsonb;
begin
 if jsonb_typeof(rows)<>'array' or jsonb_array_length(rows)>100 then return false;end if;
 for r in select value from jsonb_array_elements(rows) loop
  if jsonb_typeof(r)<>'object' or jsonb_typeof(r->'name') is distinct from 'string' or length(btrim(r->>'name')) not between 1 and 160 then return false;end if;
  if kind='incident' then
   if (r->>'state') not in ('open','resolved') or r->>'state' is null or (r->>'severity') not in ('info','warning','critical') or r->>'severity' is null then return false;end if;
  else
   if kind='labor' and r->>'pricing'='units' then
    if jsonb_typeof(r->'quantity') is distinct from 'number' or (r->>'quantity')::numeric<=0 or (r->>'quantity')::numeric>1000000 or r->>'unit' not in ('hour','day') or r->>'unit' is null then return false;end if;
   else
   if jsonb_typeof(r->'quantity') is distinct from 'number' or (r->>'quantity')::numeric not between 1 and 500 or (r->>'quantity')::numeric<>trunc((r->>'quantity')::numeric) then return false;end if;
   if r->>'unit' not in ('hour','day') or r->>'unit' is null or jsonb_typeof(r->'duration') is distinct from 'number' then return false;end if;
   if (r->>'duration')::numeric<=0 or (r->>'duration')::numeric>(case when r->>'unit'='hour' then 24 else 1 end) then return false;end if;
   end if;
   if r->'rate' is not null and r->'rate'<>'null'::jsonb then
    if jsonb_typeof(r->'rate')<>'number' or (r->>'rate')::numeric not between 0 and 1000000 then return false;end if;
   end if;
   if kind='labor' and jsonb_typeof(r->'admin') is distinct from 'boolean' then return false;end if;
  end if;
 end loop;
 return true;
exception when others then return false;
end; $$;
