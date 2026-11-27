-- Synthetic fixture in disposable test-postgres DB only. Never run in live relay DB.
begin;
insert into auth.users values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
insert into public.mirsa_runtime_caps(token_hash,user_id,bundle_id,revision,expires_at)
values(repeat('c',64),'cccccccc-cccc-4ccc-8ccc-cccccccccccc','com.example.capacity',repeat('c',64),now()+interval '1 day');
do $$
declare batch jsonb; i integer; n integer; v jsonb; rid uuid;
begin
 for i in 0..78 loop
  select jsonb_agg(jsonb_build_object('text','Menu item '||translate(lpad(to_hex(x),4,'0'),'0123456789abcdef','abcdefghijklmnop'))) into batch from generate_series(i*128,least(i*128+127,9999)) x;
  n:=public.mirsa_runtime_queue(repeat('c',64),'com.example.capacity',repeat('c',64),batch);
  if n<>jsonb_array_length(batch) then raise exception 'queue fixture lost rows';end if;
 end loop;
 if (select count(*) from public.mirsa_runtime_labels where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc')<>10000 then raise exception '10k queue incomplete';end if;
 if (select count(*) from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id where l.user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc')<>10000 then raise exception '10k outbox incomplete';end if;
 -- Bulk synthetic canonical fixture seeding is confined to this rollback test DB.
 update public.mirsa_runtime_labels set translation='خيار من قائمة التطبيق لعرض تفاصيل العنصر المحدد',provenance='kat',version=2 where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 v:=public.mirsa_runtime_refresh(repeat('c',64),'com.example.capacity',repeat('c',64));
 if jsonb_array_length(v)<>10000 or octet_length(v::text)<=1048576 or octet_length(v::text)>8388608 then raise exception 'refresh fixture size/count';end if;
 if exists(select 1 from jsonb_array_elements(v) x where x->>'translation'<>'خيار من قائمة التطبيق لعرض تفاصيل العنصر المحدد' or x->>'provenance'<>'kat') then raise exception 'canonical fixture changed';end if;
 -- Count guard is exercised without emitting additional queue outbox rows.
 insert into public.mirsa_runtime_labels(user_id,bundle_id,revision,source)
 select 'cccccccc-cccc-4ccc-8ccc-cccccccccccc','com.example.capacity',repeat('c',64),'Boundary '||x from generate_series(10000,19999) x;
 begin
  perform public.mirsa_runtime_queue(repeat('c',64),'com.example.capacity',repeat('c',64),'[{"text":"Beyond count"}]');
  raise exception 'overflow accepted';
 exception when raise_exception then if sqlerrm<>'queue_capacity' then raise;end if;end;
 delete from public.mirsa_runtime_labels where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and source like 'Boundary %';
 update public.mirsa_runtime_labels set translation=repeat('ش',220) where user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';
 begin
  perform public.mirsa_runtime_queue(repeat('c',64),'com.example.capacity',repeat('c',64),'[{"text":"Beyond bytes"}]');
  raise exception 'byte overflow accepted';
 exception when raise_exception then if sqlerrm<>'queue_capacity' then raise;end if;end;
 raise notice 'capacity PASS 10000 queued, full Kat refresh >1MiB and <8MiB, 20000 count and 4MiB dictionary guards reject';
end $$;
rollback;
