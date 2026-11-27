-- Isolated WEB staging only. Production schema.sql is intentionally unchanged.
-- Every request is counted, but character work is billed on first source insertion.
-- No account counters, capabilities, auth, expiry or canonical values are reset.
begin;
set local lock_timeout='5s';
do $$ begin
 if current_setting('data_directory') <> '/home/kit/runtime-staging25/pgdata'
 and current_setting('data_directory') !~ '^/tmp/mrt-fair-pg-[A-Za-z0-9]+/db$' then
  raise exception 'isolated staging database required';
 end if;
end $$;
lock table public.mirsa_runtime_labels,public.mirsa_runtime_reviews in share row exclusive mode;
create table public.mirsa_staging_work27 (
 user_id uuid not null references auth.users(id) on delete cascade,
 bundle_id text not null, revision text not null, source text not null,
 primary key(user_id,bundle_id,revision,source)
);
alter table public.mirsa_staging_work27 enable row level security;
revoke all on public.mirsa_staging_work27 from public,anon,authenticated,service_role;
-- Existing work is already paid for, never retroactively charge it again.
insert into public.mirsa_staging_work27 select user_id,bundle_id,revision,source from public.mirsa_runtime_labels;
create table public.mirsa_staging_cache27 (
 user_id uuid not null references auth.users(id) on delete cascade,
 bundle_id text not null, revision text not null, payload jsonb not null,
 touched timestamptz not null default clock_timestamp(),
 primary key(user_id,bundle_id,revision),
 check(jsonb_typeof(payload)='array' and jsonb_array_length(payload)<=20000 and octet_length(payload::text)<=8388608)
);
alter table public.mirsa_staging_cache27 enable row level security;
revoke all on public.mirsa_staging_cache27 from public,anon,authenticated,service_role;
create or replace function public.mirsa_runtime_reserve(p_user uuid,p_hash text,p_bundle text,p_revision text,p_action text,p_chars integer)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
 c public.mirsa_runtime_caps%rowtype;
 u public.mirsa_runtime_usage%rowtype;
 owner_id uuid;
 now_at timestamptz := clock_timestamp();
 day_at date := (now_at at time zone 'UTC')::date;
 minute_at timestamptz := date_trunc('minute',now_at);
begin
 if p_action is null or p_action not in ('issue','dictionary','missing','refresh') or p_chars is null or p_chars < 0 or
    p_bundle is null or length(p_bundle) not between 3 and 255 or p_revision is null or p_revision !~ '^[0-9a-f]{64}$' or
    p_chars > (case when p_action='missing' then 2048 else 8192 end) then return false; end if;
 if p_action in ('missing','refresh') or (p_action='dictionary' and p_hash is not null) then
   select * into c from public.mirsa_runtime_caps where token_hash=p_hash;
   if not found then return false; end if;
   owner_id := c.user_id;
 else
   if p_user is null or p_hash is not null then return false; end if;
   owner_id := p_user;
 end if;
 -- All requests for a user, including different capabilities/revisions, serialize.
 perform pg_advisory_xact_lock(hashtextextended(owner_id::text,812589));
 now_at := clock_timestamp();
 day_at := (now_at at time zone 'UTC')::date;
 minute_at := date_trunc('minute',now_at);
 if p_action in ('missing','refresh') or (p_action='dictionary' and p_hash is not null) then
   select * into c from public.mirsa_runtime_caps where token_hash=p_hash for update;
   if not found or c.revoked or c.expires_at<=now_at or c.bundle_id<>p_bundle or c.revision<>p_revision or
      c.requests>=100000 or c.chars>67108864 then return false; end if;
 end if;
 insert into public.mirsa_runtime_usage(user_id,day,minute) values(owner_id,day_at,minute_at) on conflict do nothing;
 select * into u from public.mirsa_runtime_usage where user_id=owner_id and day=day_at for update;
 if u.requests>=100000 or u.chars>67108864 or
    (u.minute=minute_at and u.minute_requests>=2000) or
    (p_action='issue' and u.issues>=1000) then return false; end if;
 update public.mirsa_runtime_usage set requests=requests+1,chars=chars,
   issues=issues+case when p_action='issue' then 1 else 0 end,
   minute=minute_at,minute_requests=case when minute=minute_at then minute_requests+1 else 1 end
   where user_id=owner_id and day=day_at;
 if p_action in ('missing','refresh') or (p_action='dictionary' and p_hash is not null) then
   update public.mirsa_runtime_caps set requests=requests+1,chars=chars where token_hash=p_hash;
 end if;
 return true;
end $$;
revoke all on function public.mirsa_runtime_reserve(uuid,text,text,text,text,integer) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_reserve(uuid,text,text,text,text,integer) to service_role;

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
   if app_count>=20000 or account_count>=200000 or app_bytes+octet_length(item->>'text')>8388608 then raise exception 'queue_capacity';end if;
   insert into public.mirsa_runtime_labels(user_id,bundle_id,revision,source) values(c.user_id,p_bundle,p_revision,item->>'text') returning id into lid;
   added:=added+1; app_count:=app_count+1; account_count:=account_count+1; app_bytes:=app_bytes+octet_length(item->>'text');
  end if;
  if review_count>=400000 then raise exception 'review_capacity';end if;
  if exists(select 1 from public.mirsa_runtime_labels where id=lid and translation is null) then
   insert into public.mirsa_runtime_reviews(label_id,kind) values(lid,'missing') on conflict do nothing;
   get diagnostics n = row_count; review_count:=review_count+n;
  end if;
 end loop;
 return added;
end $$;
revoke all on function public.mirsa_runtime_queue(text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_queue(text,text,text,jsonb) to service_role;


create function public.mirsa_staging_charge27() returns trigger language plpgsql security definer set search_path='' as $$
declare n integer; cost integer; d date; t timestamptz;
begin
 perform pg_advisory_xact_lock(hashtextextended(new.user_id::text,812589));
 if new.bundle_id is null or length(new.bundle_id) not between 3 and 255 or new.revision !~ '^[0-9a-f]{64}$' or
 length(new.source) not between 1 and 256 or octet_length(new.source)>1024 then raise exception 'invalid_work';end if;
 insert into public.mirsa_staging_work27 values(new.user_id,new.bundle_id,new.revision,new.source) on conflict do nothing;
 get diagnostics n=row_count;
 if n=0 then return new;end if;
 -- UTF16 units match the existing JS request accounting, including astral text.
 select sum(case when ascii(ch)>65535 then 2 else 1 end)::integer into cost from regexp_split_to_table(new.source,'') ch;
 t:=clock_timestamp(); d:=(t at time zone 'UTC')::date;
 insert into public.mirsa_runtime_usage(user_id,day,minute) values(new.user_id,d,date_trunc('minute',t)) on conflict do nothing;
 update public.mirsa_runtime_usage set chars=chars+cost where user_id=new.user_id and day=d and chars+cost<=67108864;
 if not found then raise exception 'staging_character_budget';end if;
 return new;
end $$;
create trigger mirsa_staging_charge27 before insert on public.mirsa_runtime_labels for each row execute function public.mirsa_staging_charge27();
-- Source identities are immutable, so the once-per-scope ledger cannot be bypassed by updates.
create function public.mirsa_staging_invalidate27() returns trigger language plpgsql security definer set search_path='' as $$
declare uid uuid; b text; r text;
begin
 if TG_TABLE_NAME='mirsa_runtime_reviews' then
  if TG_OP='UPDATE' and new.label_id is distinct from old.label_id then raise exception 'immutable_review_scope';end if;
  select user_id,bundle_id,revision into uid,b,r from public.mirsa_runtime_labels where id=case when TG_OP='DELETE' then old.label_id else new.label_id end;
 else
  if TG_OP='UPDATE' and (new.user_id,new.bundle_id,new.revision,new.source) is distinct from (old.user_id,old.bundle_id,old.revision,old.source) then raise exception 'immutable_source_scope';end if;
  if TG_OP='DELETE' then uid:=old.user_id;b:=old.bundle_id;r:=old.revision;else uid:=new.user_id;b:=new.bundle_id;r:=new.revision;end if;
 end if;
 if uid is not null then
 perform pg_advisory_xact_lock(hashtextextended(uid::text,812589));
 delete from public.mirsa_staging_cache27 where user_id=uid and bundle_id=b and revision=r;
 end if;
 return null;
end $$;
create trigger mirsa_staging_invalidate_labels27 after insert or update or delete on public.mirsa_runtime_labels for each row execute function public.mirsa_staging_invalidate27();
create trigger mirsa_staging_invalidate_reviews27 after insert or update or delete on public.mirsa_runtime_reviews for each row execute function public.mirsa_staging_invalidate27();
create or replace function public.mirsa_runtime_refresh(p_hash text,p_bundle text,p_revision text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.mirsa_runtime_caps%rowtype; result jsonb;
begin
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash;
 if not found then return '[]'::jsonb;end if;
 perform pg_advisory_xact_lock(hashtextextended(c.user_id::text,812589));
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash for update;
 if not found or c.revoked or c.expires_at<=clock_timestamp() or c.bundle_id is distinct from p_bundle or c.revision is distinct from p_revision then return '[]'::jsonb;end if;
 select payload into result from public.mirsa_staging_cache27 where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision;
 if found then return result;end if;
 select coalesce(jsonb_agg(jsonb_build_object('source',l.source,'translation',l.translation,'version',l.version,'provenance',coalesce(l.provenance,'kat')) order by l.id),'[]'::jsonb)
 into result from public.mirsa_runtime_labels l where l.user_id=c.user_id and l.bundle_id=p_bundle and l.revision=p_revision and l.translation is not null;
 if jsonb_array_length(result)>20000 or octet_length(result::text)>8388608 then raise exception 'dictionary_capacity';end if;
 -- At most 64 scoped payloads and 16MiB serialized cache per account.
 if result<>'[]'::jsonb then
 while (select count(*)>=64 or coalesce(sum(octet_length(payload::text)),0)+octet_length(result::text)>16777216 from public.mirsa_staging_cache27 where user_id=c.user_id) loop
  delete from public.mirsa_staging_cache27 where (user_id,bundle_id,revision) in (select user_id,bundle_id,revision from public.mirsa_staging_cache27 where user_id=c.user_id order by touched limit 1);
 end loop;
 insert into public.mirsa_staging_cache27(user_id,bundle_id,revision,payload) values(c.user_id,p_bundle,p_revision,result);
 end if;
 return result;
end $$;
revoke all on function public.mirsa_staging_charge27(),public.mirsa_staging_invalidate27() from public,anon,authenticated,service_role;
commit;
