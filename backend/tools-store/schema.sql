-- Mirsa Tools Store. Apply in the Mirsa Supabase project only. Only the edge function (service role) touches these tables.
create table if not exists public.mirsa_tools_items (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('tweaks','wallpapers','app_tweaks','sounds','fonts')),
  title text not null check (char_length(title) between 2 and 80),
  description text not null default '' check (char_length(description) <= 1000),
  target_app text check (target_app is null or char_length(target_app) <= 120),
  version text check (version is null or char_length(version) <= 40),
  author_name text check (author_name is null or char_length(author_name) <= 40),
  file_name text not null,
  file_ext text not null,
  file_size bigint not null check (file_size > 0 and file_size <= 157286400),
  storage_path text not null unique,
  preview_path text,
  -- uploading -> pending_review (after the bytes are verified) -> approved | rejected (admin only)
  status text not null default 'uploading' check (status in ('uploading','pending_review','held','approved','rejected')),
  review_note text check (review_note is null or char_length(review_note) <= 300),
  uploader uuid not null,
  uploader_device text,
  downloads integer not null default 0,
  rating_sum integer not null default 0,
  rating_count integer not null default 0,
  rating_avg numeric generated always as (case when rating_count > 0 then round(rating_sum::numeric / rating_count, 2) else 0 end) stored,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_at timestamptz
);
create index if not exists mirsa_tools_items_top on public.mirsa_tools_items (status, category, downloads desc);
create index if not exists mirsa_tools_items_new on public.mirsa_tools_items (status, category, created_at desc);
create index if not exists mirsa_tools_items_rated on public.mirsa_tools_items (status, category, rating_avg desc, rating_count desc);
create index if not exists mirsa_tools_items_uploader on public.mirsa_tools_items (uploader, created_at desc);

create table if not exists public.mirsa_tools_ratings (
  item_id uuid not null references public.mirsa_tools_items(id) on delete cascade,
  user_id uuid not null,
  stars smallint not null check (stars between 1 and 5),
  updated_at timestamptz not null default now(),
  primary key (item_id, user_id)
);

-- One counted download per user and item, so the "most downloaded" list cannot be inflated by one install.
create table if not exists public.mirsa_tools_downloads (
  item_id uuid not null references public.mirsa_tools_items(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (item_id, user_id)
);

create table if not exists public.mirsa_tools_usage (
  id bigserial primary key, user_id uuid not null, action text not null, created_at timestamptz not null default now());
create index if not exists mirsa_tools_usage_user_time on public.mirsa_tools_usage (user_id, action, created_at desc);

alter table public.mirsa_tools_items enable row level security;
alter table public.mirsa_tools_ratings enable row level security;
alter table public.mirsa_tools_downloads enable row level security;
alter table public.mirsa_tools_usage enable row level security;
revoke all on public.mirsa_tools_items, public.mirsa_tools_ratings, public.mirsa_tools_downloads, public.mirsa_tools_usage from public, anon, authenticated;

-- Upsert a rating and recompute the aggregate atomically. Only approved items can be rated.
create or replace function public.mirsa_tools_rate(p_item uuid, p_user uuid, p_stars int)
returns table (rating_sum int, rating_count int) language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform 1 from mirsa_tools_items where id = p_item and status = 'approved' for update;
  if not found then
    raise exception 'not_found';
  end if;
  insert into mirsa_tools_ratings(item_id, user_id, stars) values (p_item, p_user, p_stars)
    on conflict (item_id, user_id) do update set stars = excluded.stars, updated_at = now();
  return query
    update mirsa_tools_items i set
      rating_sum = (select coalesce(sum(r.stars), 0)::int from mirsa_tools_ratings r where r.item_id = p_item),
      rating_count = (select count(*)::int from mirsa_tools_ratings r where r.item_id = p_item)
    where i.id = p_item
    returning i.rating_sum, i.rating_count;
end $$;

-- Counts the first download of an approved item per user. Returns true when it was counted.
create or replace function public.mirsa_tools_count_download(p_item uuid, p_user uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare n int;
begin
  perform 1 from mirsa_tools_items where id = p_item and status = 'approved' for update;
  if not found then raise exception 'not_found'; end if;
  insert into mirsa_tools_downloads(item_id, user_id) values (p_item, p_user) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 1 then update mirsa_tools_items set downloads = downloads + 1 where id = p_item; end if;
  return n = 1;
end $$;

revoke all on function public.mirsa_tools_rate(uuid, uuid, int), public.mirsa_tools_count_download(uuid, uuid) from public, anon, authenticated;
grant execute on function public.mirsa_tools_rate(uuid, uuid, int), public.mirsa_tools_count_download(uuid, uuid) to service_role;

-- Private bucket: files are served only through short-lived signed URLs from the edge function.
insert into storage.buckets (id, name, public, file_size_limit)
values ('mirsa-tools', 'mirsa-tools', false, 157286400)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

-- Explicit grants: no assumption about a project's default privileges.
grant all on public.mirsa_tools_items, public.mirsa_tools_ratings, public.mirsa_tools_downloads, public.mirsa_tools_usage to service_role;
revoke all on sequence public.mirsa_tools_usage_id_seq from public, anon, authenticated;
grant usage, select on sequence public.mirsa_tools_usage_id_seq to service_role;

-- Existing broad storage policies must not grant app clients direct upload/download access.
-- Signed capabilities and service-role operations are separate trusted storage API paths.
drop policy if exists mirsa_tools_private_guard on storage.objects;
create policy mirsa_tools_private_guard on storage.objects as restrictive for all to anon, authenticated
  using (bucket_id <> 'mirsa-tools') with check (bucket_id <> 'mirsa-tools');

-- Durable owner-report outbox. A worker must poll admin_alerts, notify Alaa, THEN
-- admin_ack_alert. No worker/recipient/production endpoint is configured by this schema.
create table if not exists public.mirsa_tools_alerts (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.mirsa_tools_items(id),
  reason text not null,
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz
);
alter table public.mirsa_tools_alerts enable row level security;
revoke all on public.mirsa_tools_alerts from public, anon, authenticated;
grant all on public.mirsa_tools_alerts to service_role;

create or replace function public.mirsa_tools_item_guard()
returns trigger language plpgsql set search_path = public as $$
begin
  -- Serializes per-user inserts so parallel upload_begin cannot exceed the cap.
  if TG_OP = 'INSERT' then
    perform pg_advisory_xact_lock(hashtextextended('tools-upload:' || new.uploader::text, 0));
    if (select count(*) from mirsa_tools_items where uploader = new.uploader
        and status in ('uploading','pending_review','held')) >= 5 then
      raise exception 'pending_limit';
    end if;
  end if;
  if new.status = 'approved' then
    if new.storage_path not like 'review/%' or new.reviewed_at is null or
        coalesce(char_length(new.review_note), 0) < 3 then raise exception 'review_required'; end if;
    if TG_OP = 'UPDATE' then
      if old.status not in ('pending_review','approved') then raise exception 'review_required'; end if;
      if old.status = 'approved' and (new.storage_path <> old.storage_path or new.file_size <> old.file_size or
          new.file_ext <> old.file_ext) then raise exception 'immutable_approved_file'; end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists mirsa_tools_item_guard on public.mirsa_tools_items;
create trigger mirsa_tools_item_guard before insert or update on public.mirsa_tools_items
  for each row execute function public.mirsa_tools_item_guard();

create or replace function public.mirsa_tools_alert_held()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status = 'held' then
    if TG_OP = 'INSERT' then
      insert into mirsa_tools_alerts(item_id, reason) values (new.id, coalesce(new.review_note,'suspicious_upload'));
    elsif old.status is distinct from new.status then
      insert into mirsa_tools_alerts(item_id, reason) values (new.id, coalesce(new.review_note,'suspicious_upload'));
    end if;
  end if;
  return new;
end $$;
drop trigger if exists mirsa_tools_alert_held on public.mirsa_tools_items;
create trigger mirsa_tools_alert_held after insert or update on public.mirsa_tools_items
  for each row execute function public.mirsa_tools_alert_held();

-- Durable, serialized, fail-closed sliding-window rate limiting.
create or replace function public.mirsa_tools_allow(p_user uuid, p_action text, p_limit int, p_window_ms bigint)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if p_user is null or p_limit < 1 or p_window_ms < 1 then raise exception 'bad_limit'; end if;
  perform pg_advisory_xact_lock(hashtextextended('tools-rate:' || p_user::text || ':' || p_action, 0));
  if (select count(*) from mirsa_tools_usage where user_id = p_user and action = p_action
      and created_at >= now() - (p_window_ms * interval '1 millisecond')) >= p_limit then return false; end if;
  insert into mirsa_tools_usage(user_id, action) values (p_user,p_action);
  return true;
end $$;
revoke all on function public.mirsa_tools_allow(uuid,text,int,bigint),
  public.mirsa_tools_item_guard(), public.mirsa_tools_alert_held() from public, anon, authenticated;
grant execute on function public.mirsa_tools_allow(uuid,text,int,bigint) to service_role;
