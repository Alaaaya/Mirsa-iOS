begin;
insert into auth.users values ('33333333-3333-4333-8333-333333333333');
insert into public.mirsa_runtime_caps(token_hash,user_id,bundle_id,revision,expires_at)
values(repeat('f',64),'33333333-3333-4333-8333-333333333333','com.example.queue',repeat('a',64),now()+interval '1 day');
do $$
declare n integer; v jsonb; x text; i integer; rid uuid;
begin
 if has_table_privilege('authenticated','public.mirsa_runtime_labels','select') or
 has_function_privilege('anon','public.mirsa_runtime_refresh(text,text,text)','execute') or
 has_table_privilege('authenticated','public.mirsa_runtime_reviews','select') or
 has_table_privilege('authenticated','public.mirsa_runtime_batches','select') or
 has_function_privilege('anon','public.mirsa_runtime_review(uuid,bigint,text)','execute') then raise exception 'public queue access'; end if;
 n:=public.mirsa_runtime_queue(repeat('f',64),'com.other.app',repeat('a',64),'[{"text":"设置"}]');
 if n<>0 then raise exception 'cross app queued';end if;
 n:=public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('b',64),'[{"text":"设置"}]');
 if n<>0 then raise exception 'cross revision queued';end if;
 n:=public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('a',64),'[{"text":"设置"},{"text":"设置"}]');
 if n<>1 then raise exception 'dedupe failed';end if;
 if public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('a',64),'[{"text":"设置"}]')<>0 then raise exception 'persistent dedupe failed';end if;
 if public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64))<>'[]'::jsonb then raise exception 'unreviewed leaked';end if;

 select r.id into rid from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id where l.user_id='33333333-3333-4333-8333-333333333333' and r.kind='missing';
 perform public.mirsa_runtime_review(rid,1,'الإعدادات');
 if not exists(select 1 from public.mirsa_runtime_labels where user_id='33333333-3333-4333-8333-333333333333' and provenance='kat' and version=2) then raise exception 'canonical Kat provenance absent';end if;
 begin
  perform public.mirsa_runtime_review(rid,0,'نص قديم');
  raise exception 'stale review allowed';
 exception when serialization_failure then null; end;
 if public.mirsa_runtime_store(repeat('f',64),'com.example.queue',repeat('a',64),'[{"source":"设置","translation":"خيارات جديدة"}]')<>1 then raise exception 'Gemini candidate not queued';end if;
 if not exists(select 1 from public.mirsa_runtime_reviews where kind='review' and candidate='خيارات جديدة') then raise exception 'Gemini after Kat missing review';end if;
 if public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64))->0->>'translation'<>'الإعدادات' then raise exception 'Gemini overwrote Kat';end if;
 perform public.mirsa_runtime_store(repeat('f',64),'com.example.queue',repeat('a',64),'[{"source":"设置","translation":"خيارات جديدة"}]');
 if (select count(*) from public.mirsa_runtime_reviews where kind='review' and candidate='خيارات جديدة')<>1 then raise exception 'candidate review replay not deduped';end if;
 select r.id into rid from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id where l.user_id='33333333-3333-4333-8333-333333333333' and r.kind='review';
 begin
  perform public.mirsa_runtime_review(rid,0,'تصحيح قديم');
  raise exception 'stale candidate review allowed';
 exception when serialization_failure then null; end;
 perform public.mirsa_runtime_review(rid,2,'الإعدادات المعتمدة');
 if public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64))->0->>'version'<>'3' then raise exception 'Kat version did not increment';end if;
 begin
  perform public.mirsa_runtime_review(rid,3,'إعادة اعتماد');
  raise exception 'already resolved review allowed';
 exception when serialization_failure then null; end;
 -- A second source starts as Gemini, but is still separately queued for Kat.
 perform public.mirsa_runtime_store(repeat('f',64),'com.example.queue',repeat('a',64),'[{"source":"关于","translation":"حول التطبيق"}]');
 if not exists(select 1 from public.mirsa_runtime_labels where source='关于' and translation='حول التطبيق' and version=2 and provenance='gemini') then raise exception 'initial Gemini dictionary not persisted';end if;
 perform public.mirsa_runtime_store(repeat('f',64),'com.example.queue',repeat('a',64),'[{"source":"关于","translation":"عن التطبيق"}]');
 if not exists(select 1 from public.mirsa_runtime_labels where source='关于' and translation='عن التطبيق' and version=3 and provenance='gemini') then raise exception 'Gemini version not monotonic';end if;

 v:=public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64));
 if not jsonb_path_exists(v,'$[*] ? (@.translation == "الإعدادات المعتمدة" && @.provenance == "kat" && @.version == 3)') then raise exception 'OTA absent';end if;
 if public.mirsa_runtime_refresh(repeat('f',64),'com.other.app',repeat('a',64))<>'[]'::jsonb then raise exception 'cross app leaked';end if;
 for i in 1..12 loop
 x:=public.mirsa_runtime_anomaly(repeat('f',64),lpad(i::text,64,'0'),600,4,12);
 if i<4 and x<>'ok' then raise exception 'premature throttle';end if;
 if i between 4 and 11 and x<>'throttled' then raise exception 'throttle first missing';end if;
 end loop;
 if x<>'revoked' then raise exception 'clear threshold no revocation';end if;
 if public.mirsa_runtime_reserve(null,repeat('f',64),'com.example.queue',repeat('a',64),'dictionary',1) then raise exception 'revoked dict accepted';end if;
 if public.mirsa_runtime_refresh(repeat('f',64),'com.example.queue',repeat('a',64))<>'[]'::jsonb then raise exception 'revoked read accepted';end if;
 if public.mirsa_runtime_queue(repeat('f',64),'com.example.queue',repeat('a',64),'[{"text":"其他"}]')<>0 then raise exception 'revoked queue accepted';end if;
end $$;
rollback;
