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
 if p_action is null or p_action not in ('issue','dictionary','missing') or p_chars is null or p_chars < 0 or
    p_chars > (case when p_action='missing' then 2048 else 8192 end) then return false; end if;
 if p_action='missing' then
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
 if p_action='missing' then
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
 if p_action='missing' then
   update public.mirsa_runtime_caps set requests=requests+1,chars=chars+p_chars where token_hash=p_hash;
 end if;
 return true;
end $$;
revoke all on function public.mirsa_runtime_reserve(uuid,text,text,text,text,integer) from public,anon,authenticated;
grant execute on function public.mirsa_runtime_reserve(uuid,text,text,text,text,integer) to service_role;
-- Optional operator retention: delete expired caps and usage older than 7 days.
