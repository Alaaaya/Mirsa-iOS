-- Apply before the backend switch; old jobs remain GitHub-owned.
begin;
alter table public.mirsa_forge_keys
 add column if not exists route text not null default 'github' check (route in ('github','oracle')),
 add column if not exists state text not null default 'queued' check (state in ('queued','running','completing','done','failed','delivered')),
 add column if not exists attempts integer not null default 1 check (attempts between 1 and 3),
 add column if not exists retained_source text,
 add column if not exists source_hash text,
 add column if not exists result_digest text;
-- Active old workflow jobs need a completion-compatible state.
update public.mirsa_forge_keys set state='running' where fetched and state='queued';
-- Already uploaded pre-migration results are detected via Storage metadata.
update public.mirsa_forge_keys k set state=case when exists(select 1 from storage.objects o where o.bucket_id='mirsa-ota-private' and o.name='forge/out/'||k.job||'.enc') then 'done' else 'failed' end
where exists(select 1 from storage.objects o where o.bucket_id='mirsa-ota-private' and o.name in ('forge/out/'||k.job||'.enc','forge/out/'||k.job||'.err'));
commit;
