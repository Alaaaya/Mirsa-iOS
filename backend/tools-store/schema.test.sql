-- Run only against an isolated test database after schema.sql. Always rollback.
begin;
do $$
declare i uuid; u uuid := gen_random_uuid(); j int; ok boolean;
begin
  if has_table_privilege('authenticated','public.mirsa_tools_items','SELECT') or
     has_function_privilege('anon','public.mirsa_tools_rate(uuid,uuid,int)','EXECUTE') or
     has_function_privilege('authenticated','public.mirsa_tools_allow(uuid,text,int,bigint)','EXECUTE') then
    raise exception 'untrusted privilege'; end if;
  if not has_function_privilege('service_role','public.mirsa_tools_allow(uuid,text,int,bigint)','EXECUTE') then
    raise exception 'missing service privilege'; end if;
  insert into mirsa_tools_items(category,title,file_name,file_ext,file_size,storage_path,uploader)
    values ('tweaks','Test','a.dylib','dylib',1024,'uploads/test/a',u) returning id into i;
  begin
    perform mirsa_tools_count_download(i,u);
    raise exception 'download allowed unapproved';
  exception when raise_exception then
    if SQLERRM <> 'not_found' then raise; end if;
  end;
  update mirsa_tools_items set status='held',review_note='header_mismatch' where id=i;
  if (select count(*) from mirsa_tools_alerts where item_id=i) <> 1 then raise exception 'no durable alert'; end if;
  update mirsa_tools_items set title='Still held' where id=i;
  if (select count(*) from mirsa_tools_alerts where item_id=i) <> 1 then raise exception 'duplicate alert'; end if;
  begin
    update mirsa_tools_items set status='approved',storage_path='review/test/a',reviewed_at=now(),review_note='reviewed' where id=i;
    raise exception 'held approved';
  exception when raise_exception then
    if SQLERRM <> 'review_required' then raise; end if;
  end;
  update mirsa_tools_items set status='rejected' where id=i;
  insert into mirsa_tools_items(category,title,file_name,file_ext,file_size,storage_path,uploader,status)
    values ('tweaks','Safe','b.dylib','dylib',1024,'review/test/b',u,'pending_review') returning id into i;
  update mirsa_tools_items set status='approved',reviewed_at=now(),review_note='Manually reviewed' where id=i;
  perform mirsa_tools_rate(i,u,5);
  perform mirsa_tools_rate(i,u,2);
  if (select rating_sum=2 and rating_count=1 from mirsa_tools_items where id=i) is not true then raise exception 'rating aggregation'; end if;
  perform mirsa_tools_count_download(i,u); perform mirsa_tools_count_download(i,u);
  if (select downloads from mirsa_tools_items where id=i) <> 1 then raise exception 'download duplication'; end if;
  begin
    update mirsa_tools_items set storage_path='review/changed' where id=i;
    raise exception 'approved mutable';
  exception when raise_exception then
    if SQLERRM <> 'immutable_approved_file' then raise; end if;
  end;
  for j in 1..5 loop
    insert into mirsa_tools_items(category,title,file_name,file_ext,file_size,storage_path,uploader)
      values ('fonts','Font','a.ttf','ttf',1,'uploads/limit/'||j,u);
  end loop;
  begin
    insert into mirsa_tools_items(category,title,file_name,file_ext,file_size,storage_path,uploader)
      values ('fonts','Font','a.ttf','ttf',1,'uploads/limit/6',u);
    raise exception 'cap bypassed';
  exception when raise_exception then
    if SQLERRM <> 'pending_limit' then raise; end if;
  end;
  for j in 1..3 loop
    ok := mirsa_tools_allow(u,'test',2,10000);
    if ok <> (j <= 2) then raise exception 'rate limit bypassed'; end if;
  end loop;
  raise notice 'PASS privileges, unapproved download, hold/report, no held approval, immutability, aggregates, cap, rate limit';
end $$;
-- An existing permissive policy cannot override the restrictive bucket guard.
grant usage on schema storage to authenticated;
grant select on storage.objects to authenticated;
create policy test_broad_access on storage.objects for select to authenticated using (true);
insert into storage.objects values (gen_random_uuid(),'mirsa-tools'),(gen_random_uuid(),'other-bucket');
set local role authenticated;
do $$ begin
  if exists(select 1 from storage.objects where bucket_id='mirsa-tools') then raise exception 'bucket exposed'; end if;
  if not exists(select 1 from storage.objects where bucket_id='other-bucket') then raise exception 'other bucket regressed'; end if;
  raise notice 'PASS restrictive storage policy';
end $$;
reset role;
rollback;
