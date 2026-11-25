-- Branch only. Apply manually with release approval. Safe consented UI labels are stored privately; raw tokens never stored.
create table if not exists public.mirsa_runtime_caps (
 token_hash text primary key check(token_hash ~ '^[0-9a-f]{64}$'),
 user_id uuid not null references auth.users(id) on delete cascade,
 bundle_id text not null, revision text not null check(revision ~ '^[0-9a-f]{64}$'),
 expires_at timestamptz not null, revoked boolean not null default false,
 requests integer not null default 0, chars integer not null default 0
);
create table if not exists public.mirsa_runtime_usage (
 user_id uuid not null references auth.users(id) on delete cascade,
 day date not null, requests integer not null default 0, chars integer not null default 0,
 issues integer not null default 0, minute timestamptz not null, minute_requests integer not null default 0,
 primary key(user_id,day)
);
alter table public.mirsa_runtime_caps enable row level security;
alter table public.mirsa_runtime_usage enable row level security;
revoke all on public.mirsa_runtime_caps,public.mirsa_runtime_usage from public,anon,authenticated;
grant select,insert,update,delete on public.mirsa_runtime_caps,public.mirsa_runtime_usage to service_role;

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
      c.requests>=256 or c.chars+p_chars>32768 then return false; end if;
 end if;
 insert into public.mirsa_runtime_usage(user_id,day,minute) values(owner_id,day_at,minute_at) on conflict do nothing;
 select * into u from public.mirsa_runtime_usage where user_id=owner_id and day=day_at for update;
 if u.requests>=100 or u.chars+p_chars>65536 or
    (u.minute=minute_at and u.minute_requests>=10) or
    (p_action='issue' and u.issues>=12) then return false; end if;
 update public.mirsa_runtime_usage set requests=requests+1,chars=chars+p_chars,
   issues=issues+case when p_action='issue' then 1 else 0 end,
   minute=minute_at,minute_requests=case when minute=minute_at then minute_requests+1 else 1 end
   where user_id=owner_id and day=day_at;
 if p_action in ('missing','refresh') or (p_action='dictionary' and p_hash is not null) then
   update public.mirsa_runtime_caps set requests=requests+1,chars=chars+p_chars where token_hash=p_hash;
 end if;
 return true;
end $$;
revoke all on function public.mirsa_runtime_reserve(uuid,text,text,text,text,integer) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_reserve(uuid,text,text,text,text,integer) to service_role;
-- Optional operator retention: delete expired caps and usage older than 7 days.

-- Branch-only safe-label queue and reviewed OTA dictionary. No client table grants.
create table if not exists public.mirsa_runtime_labels (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 bundle_id text not null, revision text not null,
 source text not null check(length(source) between 1 and 256 and octet_length(source)<=1024),
 translation text check(length(translation) between 1 and 1024 and octet_length(translation)<=4096),
 created_at timestamptz not null default now(), resolved_at timestamptz,
 notified_at timestamptz,
 unique(user_id,bundle_id,revision,source)
);
alter table public.mirsa_runtime_labels enable row level security;
revoke all on public.mirsa_runtime_labels from public,anon,authenticated;
grant select,insert,update,delete on public.mirsa_runtime_labels to service_role;

-- Hash-only anomaly evidence. IPs are keyed-HMACed before entering the database.
create table if not exists public.mirsa_runtime_ip_audit (
 token_hash text not null references public.mirsa_runtime_caps(token_hash) on delete cascade,
 ip_hash text not null check(ip_hash ~ '^[0-9a-f]{64}$'),
 seen_at timestamptz not null default now(), primary key(token_hash,ip_hash)
);
alter table public.mirsa_runtime_ip_audit enable row level security;
revoke all on public.mirsa_runtime_ip_audit from public,anon,authenticated;
grant all on public.mirsa_runtime_ip_audit to service_role;
create or replace function public.mirsa_runtime_anomaly(p_hash text,p_ip text,p_window integer,p_throttle integer,p_revoke integer)
returns text language plpgsql security definer set search_path='' as $$
declare n integer; c public.mirsa_runtime_caps%rowtype;
begin
 if p_window not between 60 and 3600 or p_throttle not between 2 and 32 or p_revoke not between p_throttle+2 and 64 or p_ip !~ '^[0-9a-f]{64}$' then return 'denied'; end if;
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash for update;
 if not found or c.revoked or c.expires_at<=clock_timestamp() then return 'denied'; end if;
 delete from public.mirsa_runtime_ip_audit where token_hash=p_hash and seen_at<clock_timestamp()-interval '24 hours';
 if (select count(*) from public.mirsa_runtime_ip_audit where token_hash=p_hash)<64 then
 insert into public.mirsa_runtime_ip_audit(token_hash,ip_hash) values(p_hash,p_ip)
 on conflict(token_hash,ip_hash) do update set seen_at=excluded.seen_at;
 end if;
 select count(*) into n from public.mirsa_runtime_ip_audit where token_hash=p_hash and seen_at>clock_timestamp()-make_interval(secs=>p_window);
 if n>=p_revoke then update public.mirsa_runtime_caps set revoked=true where token_hash=p_hash; return 'revoked'; end if;
 if n>=p_throttle then return 'throttled'; end if;
 return 'ok';
end $$;
revoke all on function public.mirsa_runtime_anomaly(text,text,integer,integer,integer) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_anomaly(text,text,integer,integer,integer) to service_role;

-- Canonical dictionaries and an immutable distinct-output review outbox.
-- Gemini candidates remain reviewable even after a Kat correction wins canonically.
alter table public.mirsa_runtime_labels add column if not exists version bigint not null default 1;
alter table public.mirsa_runtime_labels add column if not exists provenance text check(provenance in ('gemini','kat'));
create table if not exists public.mirsa_runtime_reviews (
 id uuid primary key default gen_random_uuid(),
 label_id uuid not null references public.mirsa_runtime_labels(id) on delete cascade,
 kind text not null check(kind in ('missing','review')),
 candidate text check(length(candidate) between 1 and 1024 and octet_length(candidate)<=4096),
 version bigint not null default 1 check(version>0),
 status text not null default 'pending' check(status in ('pending','approved','superseded')),
 created_at timestamptz not null default clock_timestamp(),
 notified_at timestamptz, reviewed_at timestamptz,
 check((kind='missing' and candidate is null) or (kind='review' and candidate is not null))
);
create unique index if not exists mirsa_runtime_distinct_review on public.mirsa_runtime_reviews(label_id,candidate) where kind='review';
create unique index if not exists mirsa_runtime_distinct_missing on public.mirsa_runtime_reviews(label_id) where kind='missing';
create index if not exists mirsa_runtime_review_outbox on public.mirsa_runtime_reviews(created_at,id) where status='pending' and notified_at is null;
alter table public.mirsa_runtime_reviews enable row level security;
revoke all on public.mirsa_runtime_reviews from public,anon,authenticated;
grant select,insert,update,delete on public.mirsa_runtime_reviews to service_role;

-- Existing dictionaries are conservative Kat-priority until explicitly reviewed, never silently overwritten.
update public.mirsa_runtime_labels set provenance='kat' where translation is not null and provenance is null;
insert into public.mirsa_runtime_reviews(label_id,kind,candidate)
select l.id,'review',l.translation from public.mirsa_runtime_labels l where l.translation is not null and not exists(select 1 from public.mirsa_runtime_reviews r where r.label_id=l.id) on conflict do nothing;
insert into public.mirsa_runtime_reviews(label_id,kind)
select l.id,'missing' from public.mirsa_runtime_labels l where l.translation is null on conflict do nothing;

-- Internal helpers are service-only as well. All mutations use the same account lock.
create or replace function public.mirsa_runtime_queue(p_hash text,p_bundle text,p_revision text,p_items jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare c public.mirsa_runtime_caps%rowtype; item jsonb; added integer:=0; n integer; lid uuid;
begin
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash;
 if not found then return 0;end if;
 perform pg_advisory_xact_lock(hashtextextended(c.user_id::text,812589));
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash for update;
 if not found or c.revoked or c.expires_at<=clock_timestamp() or c.bundle_id<>p_bundle or c.revision<>p_revision then return 0;end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)>128 then raise exception 'invalid_queue';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(item->'text') is distinct from 'string' or length(item->>'text') not between 1 and 256 or octet_length(item->>'text')>1024 then raise exception 'invalid_label';end if;
  select id into lid from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision and source=item->>'text';
  if lid is null then
   if (select count(*) from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision)>=1500 or
      (select count(*) from public.mirsa_runtime_labels where user_id=c.user_id)>=20000 or
      (select coalesce(sum(octet_length(source)+coalesce(octet_length(translation),0)),0) from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision)>780000 then raise exception 'queue_capacity';end if;
   insert into public.mirsa_runtime_labels(user_id,bundle_id,revision,source) values(c.user_id,p_bundle,p_revision,item->>'text') returning id into lid;
   added:=added+1;
  end if;
  if (select count(*) from public.mirsa_runtime_reviews r join public.mirsa_runtime_labels l on l.id=r.label_id where l.user_id=c.user_id)>=40000 then raise exception 'review_capacity';end if;
  if exists(select 1 from public.mirsa_runtime_labels where id=lid and translation is null) then
   insert into public.mirsa_runtime_reviews(label_id,kind) values(lid,'missing') on conflict do nothing;
  end if;
 end loop;
 return added;
end $$;
revoke all on function public.mirsa_runtime_queue(text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_queue(text,text,text,jsonb) to service_role;

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
   if (select coalesce(sum(octet_length(source)+coalesce(octet_length(translation),0)),0) from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision)+octet_length(item->>'translation')>786432 then raise exception 'dictionary_capacity';end if;
   update public.mirsa_runtime_labels set translation=item->>'translation',provenance='gemini',version=version+1 where id=l.id;
  end if;
  n:=n+1;
 end loop;
 return n;
end $$;
revoke all on function public.mirsa_runtime_store(text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_store(text,text,text,jsonb) to service_role;

create or replace function public.mirsa_runtime_refresh(p_hash text,p_bundle text,p_revision text)
returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('source',l.source,'translation',l.translation,'version',l.version,'provenance',coalesce(l.provenance,'kat')) order by l.id),'[]'::jsonb)
 from public.mirsa_runtime_labels l join public.mirsa_runtime_caps c on c.user_id=l.user_id and c.bundle_id=l.bundle_id and c.revision=l.revision
 where c.token_hash=p_hash and not c.revoked and c.expires_at>clock_timestamp() and c.bundle_id=p_bundle and c.revision=p_revision and l.translation is not null;
$$;
revoke all on function public.mirsa_runtime_refresh(text,text,text) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_refresh(text,text,text) to service_role;

-- A Kat edit is an explicit compare-and-swap, never a last-write-wins overwrite.
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
 if (select coalesce(sum(octet_length(source)+coalesce(octet_length(translation),0)),0) from public.mirsa_runtime_labels where user_id=l.user_id and bundle_id=l.bundle_id and revision=l.revision)+octet_length(p_translation)>786432 then raise exception 'dictionary_capacity';end if;
 update public.mirsa_runtime_labels set translation=p_translation,provenance='kat',version=version+1,resolved_at=clock_timestamp() where id=l.id returning * into l;
 update public.mirsa_runtime_reviews set status=case when id=p_id then 'approved' else 'superseded' end,reviewed_at=clock_timestamp() where label_id=l.id and status='pending';
 return jsonb_build_object('id',r.id,'resolved',true,'version',l.version,'provenance','kat');
end $$;
revoke all on function public.mirsa_runtime_review(uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_review(uuid,bigint,text) to service_role;

-- Immutable metadata batches make a crash after relay acceptance replay the exact same event.
create table if not exists public.mirsa_runtime_batches (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('missing','review')),
 entries jsonb not null check(jsonb_typeof(entries)='array' and jsonb_array_length(entries) between 1 and 32),
 created_at timestamptz not null default clock_timestamp(), notified_at timestamptz
);
alter table public.mirsa_runtime_batches enable row level security;
revoke all on public.mirsa_runtime_batches from public,anon,authenticated;
grant select,insert,update,delete on public.mirsa_runtime_batches to service_role;

-- Shared provider budget, single credential/model. DB row lock serializes all workers.
create table if not exists public.mirsa_runtime_provider_budget(
 singleton boolean primary key default true check(singleton),
 next_at timestamptz not null default '-infinity', failures integer not null default 0 check(failures between 0 and 4)
);
insert into public.mirsa_runtime_provider_budget(singleton) values(true) on conflict do nothing;
alter table public.mirsa_runtime_provider_budget enable row level security;
revoke all on public.mirsa_runtime_provider_budget from public,anon,authenticated;
grant select,update on public.mirsa_runtime_provider_budget to service_role;
create or replace function public.mirsa_runtime_provider_slot()
returns boolean language plpgsql security definer set search_path='' as $$
begin
 -- At most five calls in any rolling minute, including retries and all accounts.
 update public.mirsa_runtime_provider_budget set next_at=clock_timestamp()+interval '13 seconds'
 where singleton and next_at<=clock_timestamp();
 return found;
end $$;
create or replace function public.mirsa_runtime_provider_backoff()
returns boolean language plpgsql security definer set search_path='' as $$
begin
 -- Retry is deferred to a future batch, never sleeps/blocks rendering or floods another worker.
 update public.mirsa_runtime_provider_budget set failures=least(4,failures+1),
 next_at=greatest(next_at,clock_timestamp()+make_interval(secs=>least(240,15*power(2,failures+1)::integer))) where singleton;
 return found;
end $$;
create or replace function public.mirsa_runtime_receipt(p_hash text,p_bundle text,p_revision text,p_items jsonb)
returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('source',l.source,'labelId',l.id,'reviewId',r.id,'kind',r.kind,'version',l.version) order by l.id),'[]'::jsonb)
 from public.mirsa_runtime_labels l join public.mirsa_runtime_caps c
 on c.user_id=l.user_id and c.bundle_id=l.bundle_id and c.revision=l.revision
 join lateral(select id,kind from public.mirsa_runtime_reviews where label_id=l.id order by created_at,id limit 1) r on true
 where c.token_hash=p_hash and not c.revoked and c.expires_at>clock_timestamp() and c.bundle_id=p_bundle and c.revision=p_revision
 and l.source in(select value->>'text' from jsonb_array_elements(p_items));
$$;
revoke all on function public.mirsa_runtime_provider_slot(),public.mirsa_runtime_provider_backoff(),public.mirsa_runtime_receipt(text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_provider_slot(),public.mirsa_runtime_provider_backoff(),public.mirsa_runtime_receipt(text,text,text,jsonb) to service_role;
