-- mirsa-ar-localize: private per-user cache + hourly usage. Service role only (RLS on, no policies).
create table if not exists public.mirsa_ar_cache (
  user_id uuid not null, bundle_id text not null, version text not null, content_hash text not null,
  translations jsonb not null, created_at timestamptz not null default now(),
  primary key (user_id, bundle_id, version, content_hash)
);
create table if not exists public.mirsa_ar_usage (
  id bigint generated always as identity primary key, user_id uuid not null, created_at timestamptz not null default now()
);
create index if not exists mirsa_ar_usage_user_time on public.mirsa_ar_usage (user_id, created_at);
alter table public.mirsa_ar_cache enable row level security;
alter table public.mirsa_ar_usage enable row level security;
revoke all on public.mirsa_ar_cache, public.mirsa_ar_usage from anon, authenticated;
