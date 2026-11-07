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
