-- Apply once before deploying the updated index.html. Existing works remain unclassified.
begin;
alter table public.elite_works add column if not exists lifecycle text
 check (lifecycle in ('study','execution','closing'));
-- Existing owner policies and the generic history trigger cover this column.
notify pgrst, 'reload schema';
commit;
