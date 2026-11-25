-- Branch only. Apply manually with release approval. No text or raw tokens stored.
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
 translation text check(length(translation) between 1 and 256 and octet_length(translation)<=1024),
 created_at timestamptz not null default now(), resolved_at timestamptz,
 notified_at timestamptz,
 unique(user_id,bundle_id,revision,source)
);
alter table public.mirsa_runtime_labels enable row level security;
revoke all on public.mirsa_runtime_labels from public,anon,authenticated;
grant select,insert,update,delete on public.mirsa_runtime_labels to service_role;

create or replace function public.mirsa_runtime_queue(p_hash text,p_bundle text,p_revision text,p_items jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare c public.mirsa_runtime_caps%rowtype; item jsonb; added integer:=0; n integer;
begin
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash;
 if not found then return 0; end if;
 perform pg_advisory_xact_lock(hashtextextended(c.user_id::text,812589));
 select * into c from public.mirsa_runtime_caps where token_hash=p_hash for update;
 if not found or c.revoked or c.expires_at<=clock_timestamp() or c.bundle_id<>p_bundle or c.revision<>p_revision then return 0; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)>16 then return 0; end if;
 for item in select value from jsonb_array_elements(p_items) loop
   if jsonb_typeof(item->'text')<>'string' or length(item->>'text') not between 1 and 256 or octet_length(item->>'text')>1024 then continue; end if;
   -- HTTP privacy filter is mandatory before this service-only RPC.
   if (select count(*) from public.mirsa_runtime_labels where user_id=c.user_id and bundle_id=p_bundle and revision=p_revision)>=64 or
      (select count(*) from public.mirsa_runtime_labels where user_id=c.user_id)>=1024 then exit; end if;
   insert into public.mirsa_runtime_labels(user_id,bundle_id,revision,source)
     values(c.user_id,p_bundle,p_revision,item->>'text') on conflict do nothing;
   get diagnostics n=row_count; added:=added+n;
 end loop;
 return added;
end $$;
revoke all on function public.mirsa_runtime_queue(text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_queue(text,text,text,jsonb) to service_role;

create or replace function public.mirsa_runtime_refresh(p_hash text,p_bundle text,p_revision text)
returns jsonb language sql security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('source',l.source,'translation',l.translation) order by l.id),'[]'::jsonb)
 from public.mirsa_runtime_labels l join public.mirsa_runtime_caps c on c.user_id=l.user_id and c.bundle_id=l.bundle_id and c.revision=l.revision
 where c.token_hash=p_hash and not c.revoked and c.expires_at>clock_timestamp() and c.bundle_id=p_bundle and c.revision=p_revision
 and l.translation is not null;
$$;
revoke all on function public.mirsa_runtime_refresh(text,text,text) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_refresh(text,text,text) to service_role;
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
