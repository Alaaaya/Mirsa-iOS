create table if not exists mirsa_forge_usage (
  id bigserial primary key, user_id uuid not null, action text not null, created_at timestamptz not null default now());
create index if not exists mirsa_forge_usage_user_time on mirsa_forge_usage (user_id, created_at desc);
create table if not exists mirsa_forge_gallery (
  id uuid primary key default gen_random_uuid(), user_id uuid not null, name text not null, target_bundle_id text not null,
  description text not null default '', code text not null, settings jsonb not null default '[]',
  installs int not null default 0, reported int not null default 0, created_at timestamptz not null default now());
alter table mirsa_forge_usage enable row level security;
alter table mirsa_forge_gallery enable row level security; -- only the edge function (service role) touches these
create or replace function mirsa_forge_install(p_id uuid) returns void language sql security definer as $$ update mirsa_forge_gallery set installs = installs + 1 where id = p_id $$;
create or replace function mirsa_forge_report(p_id uuid) returns void language sql security definer as $$ update mirsa_forge_gallery set reported = reported + 1 where id = p_id $$;
revoke all on function mirsa_forge_install(uuid), mirsa_forge_report(uuid) from public, anon, authenticated;

create table if not exists mirsa_forge_keys(job text primary key, user_id uuid not null, k text not null, fetched boolean not null default false, created_at timestamptz not null default now());
alter table mirsa_forge_keys enable row level security;

create table if not exists mirsa_forge_llm (id bigserial primary key, user_id uuid not null, tier text not null, created_at timestamptz not null default now());
create index if not exists mirsa_forge_llm_time on mirsa_forge_llm (created_at desc);
create table if not exists mirsa_forge_flags (tier text primary key, until timestamptz not null);
alter table mirsa_forge_llm enable row level security; alter table mirsa_forge_flags enable row level security;
create or replace function mirsa_forge_reserve(p_user uuid, p_tier text, p_user_day int, p_tier_day int, p_tier_min int) returns text language plpgsql security definer as $$
declare dstart timestamptz := date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles';
begin
  perform pg_advisory_xact_lock(7771001);
  if exists (select 1 from mirsa_forge_flags where tier = p_tier and until > now()) then return 'tier_day'; end if;
  if (select count(*) from mirsa_forge_llm where user_id = p_user and created_at >= dstart) >= p_user_day then return 'user_day'; end if;
  if (select count(*) from mirsa_forge_llm where tier = p_tier and created_at >= dstart) >= p_tier_day then return 'tier_day'; end if;
  if (select count(*) from mirsa_forge_llm where tier = p_tier and created_at >= now() - interval '60 seconds') >= p_tier_min then return 'busy'; end if;
  insert into mirsa_forge_llm(user_id, tier) values (p_user, p_tier);
  delete from mirsa_forge_llm where created_at < now() - interval '3 days';
  return 'ok';
end $$;
create or replace function mirsa_forge_flag(p_tier text) returns void language sql security definer as $$
  insert into mirsa_forge_flags values (p_tier, date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles' + interval '1 day') on conflict (tier) do update set until = excluded.until $$;
revoke all on function mirsa_forge_reserve(uuid,text,int,int,int), mirsa_forge_flag(text) from public, anon, authenticated;

-- Per-device + per-IP request caps (translate/generate). Day boundary = Pacific time, same as the provider's RPD reset.
create table if not exists mirsa_forge_devices (device text primary key, user_id uuid not null, created_at timestamptz not null default now());
create table if not exists mirsa_forge_gate_use (id bigserial primary key, device text not null, user_id uuid not null, iph text not null, action text not null, created_at timestamptz not null default now());
create index if not exists mirsa_forge_gate_use_dev on mirsa_forge_gate_use (device, action, created_at desc);
create index if not exists mirsa_forge_gate_use_ip on mirsa_forge_gate_use (iph, action, created_at desc);
alter table mirsa_forge_devices enable row level security; alter table mirsa_forge_gate_use enable row level security;
create or replace function mirsa_forge_gate(p_device text, p_user uuid, p_iph text, p_action text, p_dev_cap int, p_ip_cap int, p_max_dev int) returns text language plpgsql security definer as $$
declare dstart timestamptz := date_trunc('day', now() at time zone 'America/Los_Angeles') at time zone 'America/Los_Angeles'; owner uuid;
begin
  perform pg_advisory_xact_lock(7771002);
  select user_id into owner from mirsa_forge_devices where device = p_device;
  if owner is not null and owner <> p_user then return 'device_bound'; end if;
  if owner is null then
    if (select count(*) from mirsa_forge_devices where user_id = p_user and created_at >= dstart) >= p_max_dev then return 'device_rotate'; end if;
    insert into mirsa_forge_devices(device, user_id) values (p_device, p_user);
  end if;
  if (select count(*) from mirsa_forge_gate_use where device = p_device and action = p_action and created_at >= dstart) >= p_dev_cap then return 'device_day'; end if;
  if (select count(*) from mirsa_forge_gate_use where iph = p_iph and action = p_action and created_at >= dstart) >= p_ip_cap then return 'ip_day'; end if;
  insert into mirsa_forge_gate_use(device, user_id, iph, action) values (p_device, p_user, p_iph, p_action);
  delete from mirsa_forge_gate_use where created_at < now() - interval '3 days';
  delete from mirsa_forge_devices where created_at < now() - interval '30 days';
  return 'ok';
end $$;
revoke all on function mirsa_forge_gate(text,uuid,text,text,int,int,int) from public, anon, authenticated;

alter table mirsa_forge_gallery add column if not exists owner_device text;
