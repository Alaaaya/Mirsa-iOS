-- Staging capacity hotfix. Function bodies only; no canonical data mutation.

begin;

create or replace function public.mirsa_runtime_queue(p_hash text,p_bundle text,p_revision text,p_items jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare c public.mirsa_runtime_caps%rowtype; item jsonb; added integer:=0; n integer; lid uuid; app_count bigint; account_count bigint; app_bytes bigint; review_count bigint;
begin
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash;
 if not found then return 0;end if;
 perform pg_advisory_xact_lock(hashtextextended(c.user_id::text,812589));
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash for update;
 if not found or c.revoked or c.expires_at<=clock_timestamp() or c.bundle_id<>p_bundle or c.revision<>p_revision then return 0;end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)>128 then raise exception 'invalid_queue';end if;
 -- Snapshot under the account advisory lock, then update totals per inserted row.
 select count(*),coalesce(sum(octet_length(source)+coalesce(octet_length(translation),0)),0) into app_count,app_bytes from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision;
 select count(*) into account_count from public.mirsa_runtime_labels where user_id=c.user_id;
 select count(*) into review_count from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id where l.user_id=c.user_id;
 for item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(item->'text') is distinct from 'string' or length(item->>'text') not between 1 and 256 or octet_length(item->>'text')>1024 then raise exception 'invalid_label';end if;
  select id into lid from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision and source=item->>'text';
  if lid is null then
   if app_count>=20000 or account_count>=20000 or app_bytes+octet_length(item->>'text')>4194304 then raise exception 'queue_capacity';end if;
   insert into public.mirsa_runtime_labels(user_id,bundle_id,revision,source) values(c.user_id,p_bundle,p_revision,item->>'text') returning id into lid;
   added:=added+1; app_count:=app_count+1; account_count:=account_count+1; app_bytes:=app_bytes+octet_length(item->>'text');
  end if;
  if review_count>=40000 then raise exception 'review_capacity';end if;
  if exists(select 1 from public.mirsa_runtime_labels where id=lid and translation is null) then
   insert into public.mirsa_runtime_reviews(label_id,kind) values(lid,'missing') on conflict do nothing;
   get diagnostics n = row_count; review_count:=review_count+n;
  end if;
 end loop;
 return added;
end $$;

create or replace function public.mirsa_runtime_store(p_hash text,p_bundle text,p_revision text,p_entries jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare c public.mirsa_runtime_caps%rowtype; item jsonb; n integer:=0; l public.mirsa_runtime_labels%rowtype;
begin
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash;
 if not found then return 0;end if;
 perform pg_advisory_xact_lock(hashtextextended(c.user_id::text,812589));
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash for update;
 if not found or c.revoked or c.expires_at<=clock_timestamp() or c.bundle_id<>p_bundle or c.revision<>p_revision then return 0;end if;
 if jsonb_typeof(p_entries) is distinct from 'array' or jsonb_array_length(p_entries)>128 then raise exception 'invalid_entries';end if;
 for item in select value from jsonb_array_elements(p_entries) loop
  if jsonb_typeof(item->'source') is distinct from 'string' or jsonb_typeof(item->'translation') is distinct from 'string' or length(item->>'source') not between 1 and 256 or length(item->>'translation') not between 1 and 1024 or octet_length(item->>'translation')>4096 then raise exception 'invalid_candidate';end if;
  perform public.mirsa_runtime_queue(p_hash,p_bundle,p_revision,jsonb_build_array(jsonb_build_object('text',item->>'source')));
  select * into l from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision and source=item->>'source' for update;
  if (select count(*) from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels x on x.id=r.label_id where x.user_id=c.user_id)>=40000 then raise exception 'review_capacity';end if;
  insert into public.mirsa_runtime_reviews(label_id,kind,candidate) values(l.id,'review',item->>'translation') on conflict do nothing;
  -- A review remains pending until Kat, including when instant Gemini has filled the UI.
  if l.provenance is distinct from 'kat' and l.translation is distinct from item->>'translation' then
   if (select coalesce(sum(octet_length(source)+coalesce(octet_length(translation),0)),0) from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision)+octet_length(item->>'translation')>4194304 then raise exception 'dictionary_capacity';end if;
   update public.mirsa_runtime_labels set translation=item->>'translation',provenance='gemini',version=version+1 where id=l.id;
  end if;
  n:=n+1;
 end loop;
 return n;
end $$;

create or replace function public.mirsa_runtime_review(p_id uuid,p_expected bigint,p_translation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare l public.mirsa_runtime_labels%rowtype; r public.mirsa_runtime_reviews%rowtype;
begin
 select x.* into l from public.mirsa_runtime_labels x join public.mirsa_runtime_reviews y on y.label_id=x.id where y.id=p_id;
 if not found then raise exception 'unknown_review';end if;
 perform pg_advisory_xact_lock(hashtextextended(l.user_id::text,812589));
 select * into r from public.mirsa_runtime_reviews where id=p_id for update;
 select * into l from public.mirsa_runtime_labels where id=r.label_id for update;
 if r.status<>'pending' or l.version<>p_expected or p_translation is null or length(p_translation) not between 1 and 1024 or octet_length(p_translation)>4096 then raise exception using errcode='40001',message='review_conflict_or_invalid';end if;
 if (select coalesce(sum(octet_length(source)+coalesce(octet_length(translation),0)),0) from public.mirsa_runtime_labels where user_id=l.user_id and bundle_id=l.bundle_id and revision=l.revision)+octet_length(p_translation)>4194304 then raise exception 'dictionary_capacity';end if;
 update public.mirsa_runtime_labels set translation=p_translation,provenance='kat',version=version+1,resolved_at=clock_timestamp() where id=l.id returning * into l;
 update public.mirsa_runtime_reviews set status=case when id=p_id then 'approved' else 'superseded' end,reviewed_at=clock_timestamp() where label_id=l.id and status='pending';
 return jsonb_build_object('id',r.id,'resolved',true,'version',l.version,'provenance','kat');
end $$;

commit;
