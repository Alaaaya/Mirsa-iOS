\set ON_ERROR_STOP on
create function pg_temp.ok(b boolean, m text) returns void language plpgsql as $$begin if b is distinct from true then raise exception 'FAIL %',m;end if;end$$;
insert into auth.users values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.mirsa_runtime_caps(token_hash,user_id,bundle_id,revision,expires_at)
values (repeat('a',64),'11111111-1111-4111-8111-111111111111','com.fair.app',repeat('b',64),now()+interval '1 day'),
(repeat('c',64),'11111111-1111-4111-8111-111111111111','com.fair.app',repeat('b',64),now()+interval '1 day'),
(repeat('d',64),'22222222-2222-4222-8222-222222222222','com.fair.app',repeat('b',64),now()+interval '1 day'),
(repeat('e',64),'11111111-1111-4111-8111-111111111111','com.fair.other',repeat('b',64),now()+interval '1 day'),
(repeat('f',64),'11111111-1111-4111-8111-111111111111','com.fair.app',repeat('a',64),now()+interval '1 day');
do $$ declare i integer; h text; begin
 foreach h in array array[repeat('a',64),repeat('d',64)] loop
 for i in 1..500 loop
 perform pg_temp.ok(public.mirsa_runtime_reserve(null,h,'com.fair.app',repeat('b',64),'dictionary',8192),'normal all-user signing');
 end loop;end loop;end$$;
select pg_temp.ok((select bool_and(chars=0) from public.mirsa_runtime_usage),'reserve does not bill retries');
select public.mirsa_runtime_queue(repeat('a',64),'com.fair.app',repeat('b',64),'[{"text":"Hello"},{"text":"Hello"},{"text":"World"}]');
select public.mirsa_runtime_queue(repeat('c',64),'com.fair.app',repeat('b',64),'[{"text":"World"},{"text":"New"}]');
select pg_temp.ok((select chars=13 from public.mirsa_runtime_usage where user_id='11111111-1111-4111-8111-111111111111'),'distinct source billing across fresh caps and overlap');
select public.mirsa_runtime_queue(repeat('d',64),'com.fair.app',repeat('b',64),'[{"text":"Hello"}]');
select public.mirsa_runtime_queue(repeat('e',64),'com.fair.other',repeat('b',64),'[{"text":"Hello"}]');
select public.mirsa_runtime_queue(repeat('f',64),'com.fair.app',repeat('a',64),'[{"text":"Hello"}]');
select pg_temp.ok((select chars=23 from public.mirsa_runtime_usage where user_id='11111111-1111-4111-8111-111111111111'),'new revision and app charged');
select pg_temp.ok((select chars=5 from public.mirsa_runtime_usage where user_id='22222222-2222-4222-8222-222222222222'),'new user charged');
-- Canonical refresh equality, no missing value manufacture, reissued cap shares account scope.
update public.mirsa_runtime_labels set translation='مرحبا',provenance='kat',version=2 where user_id='11111111-1111-4111-8111-111111111111' and source='Hello';
create temporary table snapshot27 as select public.mirsa_runtime_refresh(repeat('a',64),'com.fair.app',repeat('b',64)) as data;
select pg_temp.ok((select data=public.mirsa_runtime_refresh(repeat('c',64),'com.fair.app',repeat('b',64)) from snapshot27),'fresh capability cache equivalence');
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('d',64),'com.fair.app',repeat('b',64))='[]','cross-user isolation');
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('a',64),'com.fair.other',repeat('b',64))='[]','wrong scope denied');
select pg_temp.ok((select jsonb_array_length(data)=1 from snapshot27),'unresolved excluded');
select public.mirsa_runtime_review(r.id,l.version,'أهلا') from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id where l.user_id='11111111-1111-4111-8111-111111111111' and l.bundle_id='com.fair.app' and l.revision=repeat('b',64) and l.source='Hello' and r.status='pending' limit 1;
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('a',64),'com.fair.app',repeat('b',64))->0->>'translation'='أهلا','review invalidates cache');
update public.mirsa_runtime_labels set translation=null where user_id='11111111-1111-4111-8111-111111111111' and source='Hello' and revision=repeat('b',64) and bundle_id='com.fair.app';
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('a',64),'com.fair.app',repeat('b',64))='[]','null invalidates cache');
update public.mirsa_runtime_caps set revoked=true where token_hash=repeat('c',64);
update public.mirsa_runtime_caps set expires_at=now()-interval '1 second' where token_hash=repeat('e',64);
select pg_temp.ok(not public.mirsa_runtime_reserve(null,repeat('c',64),'com.fair.app',repeat('b',64),'refresh',0),'revoked reserve');
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('c',64),'com.fair.app',repeat('b',64))='[]','revoked cache read');
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('e',64),'com.fair.other',repeat('b',64))='[]','expired cache read');
select pg_temp.ok(not public.mirsa_runtime_reserve(null,repeat('a',64),null,repeat('b',64),'refresh',0),'malformed null scope');
select pg_temp.ok(not public.mirsa_runtime_reserve(null,repeat('a',64),'com.fair.app',repeat('b',64),'dictionary',8193),'per request preserved');
-- 20k distinct safe labels, chunked with existing scope preserved and repeats free.
do $$ declare i integer; batch jsonb; before_chars integer; after_chars integer; begin
 select chars into before_chars from public.mirsa_runtime_usage where user_id='11111111-1111-4111-8111-111111111111';
 for i in 0..156 loop
 select jsonb_agg(jsonb_build_object('text','Label '||n)) into batch from generate_series(i*128+1,least((i+1)*128,19999)) n;
 perform public.mirsa_runtime_queue(repeat('f',64),'com.fair.app',repeat('a',64),batch);
 end loop;
 -- scope already has Hello, so final total is capped at 20k; loop above uses 19999 labels instead.
 end$$;
select pg_temp.ok((select count(*)=20000 from public.mirsa_runtime_labels where revision=repeat('a',64)),'20k labels persisted');
create temporary table charged27 as select chars from public.mirsa_runtime_usage where user_id='11111111-1111-4111-8111-111111111111';
select public.mirsa_runtime_queue(repeat('f',64),'com.fair.app',repeat('a',64),'[{"text":"Label 1"},{"text":"Hello"}]');
select pg_temp.ok((select u.chars=c.chars from public.mirsa_runtime_usage u cross join charged27 c where u.user_id='11111111-1111-4111-8111-111111111111'),'full scope retries not billed');
-- Large cached dictionary is exactly the canonical projection, including versions/provenance.
update public.mirsa_runtime_labels set translation='نص',provenance='kat' where revision=repeat('a',64);
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('f',64),'com.fair.app',repeat('a',64))=(select jsonb_agg(jsonb_build_object('source',source,'translation',translation,'version',version,'provenance',coalesce(provenance,'kat')) order by id) from public.mirsa_runtime_labels where revision=repeat('a',64)),'20k canonical cache equivalence');
select pg_temp.ok(jsonb_array_length(public.mirsa_runtime_refresh(repeat('f',64),'com.fair.app',repeat('a',64)))=20000,'20k cache hit');
-- Store/review and metadata changes invalidate even when rendered text stays unchanged.
select public.mirsa_runtime_store(repeat('f',64),'com.fair.app',repeat('a',64),'[{"source":"Hello","translation":"مقترح"}]');
select pg_temp.ok(not exists(select 1 from public.mirsa_staging_cache27 where revision=repeat('a',64)),'store review invalidates');
select pg_temp.ok(jsonb_array_length(public.mirsa_runtime_refresh(repeat('f',64),'com.fair.app',repeat('a',64)))=20000,'store preserves Kat canonical');
update public.mirsa_runtime_labels set version=version+1,provenance='gemini' where revision=repeat('a',64) and source='Hello';
select pg_temp.ok(not exists(select 1 from public.mirsa_staging_cache27 where revision=repeat('a',64)),'version provenance invalidates');
select pg_temp.ok(exists(select 1 from jsonb_array_elements(public.mirsa_runtime_refresh(repeat('f',64),'com.fair.app',repeat('a',64))) x where x->>'source'='Hello' and x->>'provenance'='gemini'),'fresh provenance returned');
-- Auth is rechecked even on a fully populated cache.
update public.mirsa_runtime_caps set revoked=true where token_hash=repeat('f',64);
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('f',64),'com.fair.app',repeat('a',64))='[]','nonempty cached revoked denied');
update public.mirsa_runtime_caps set revoked=false,expires_at=now()-interval '1 second' where token_hash=repeat('f',64);
select pg_temp.ok(public.mirsa_runtime_refresh(repeat('f',64),'com.fair.app',repeat('a',64))='[]','nonempty cached expired denied');
-- Finite ceilings are preserved, no hidden unlimited shortcut.
update public.mirsa_runtime_usage set requests=100000 where user_id='22222222-2222-4222-8222-222222222222';
select pg_temp.ok(not public.mirsa_runtime_reserve(null,repeat('d',64),'com.fair.app',repeat('b',64),'refresh',0),'daily flood ceiling');
update public.mirsa_runtime_usage set requests=0,issues=1000,minute_requests=0 where user_id='22222222-2222-4222-8222-222222222222';
select pg_temp.ok(not public.mirsa_runtime_reserve('22222222-2222-4222-8222-222222222222',null,'com.fair.app',repeat('b',64),'issue',0),'issue flood ceiling');
update public.mirsa_runtime_usage set issues=0,chars=67108864 where user_id='22222222-2222-4222-8222-222222222222';
do $$begin
 begin
 perform public.mirsa_runtime_queue(repeat('d',64),'com.fair.app',repeat('b',64),'[{"text":"Over budget"}]');
 raise exception 'FAIL character ceiling';
 exception when raise_exception then if sqlerrm <> 'staging_character_budget' then raise;end if;end;
end$$;
select pg_temp.ok(not exists(select 1 from public.mirsa_staging_work27 where source='Over budget'),'failed charge is atomic');
update public.mirsa_runtime_usage set chars=5,requests=0,minute= date_trunc('minute',clock_timestamp()),minute_requests=1990 where user_id='22222222-2222-4222-8222-222222222222';
