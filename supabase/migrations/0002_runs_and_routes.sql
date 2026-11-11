-- Lapsy: finished runs and saved routes. Run this once in Supabase → SQL Editor
-- (after 0001_profiles.sql).

create table if not exists public.runs (
  id                 uuid primary key,
  user_id            uuid not null default auth.uid() references auth.users (id) on delete cascade,
  activity_id        text not null,
  started_at         timestamptz not null,
  duration_s         double precision not null check (duration_s >= 0),
  distance_m         double precision not null check (distance_m >= 0),
  energy_kcal        double precision not null default 0,
  start_name         text,
  track              text not null default '',
  planned_polyline   text,
  planned_distance_m double precision,
  rating             smallint check (rating between 1 and 5),
  created_at         timestamptz not null default now()
);

create index if not exists runs_user_started_idx on public.runs (user_id, started_at desc);

alter table public.runs enable row level security;

create policy "runs_select_own" on public.runs
  for select to authenticated using (auth.uid() = user_id);
create policy "runs_insert_own" on public.runs
  for insert to authenticated with check (auth.uid() = user_id);
create policy "runs_update_own" on public.runs
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "runs_delete_own" on public.runs
  for delete to authenticated using (auth.uid() = user_id);


create table if not exists public.saved_routes (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null,
  activity_id text not null,
  start_name  text,
  distance_m  double precision not null,
  ascent_m    double precision not null default 0,
  duration_s  double precision not null default 0,
  route       jsonb not null,
  created_at  timestamptz not null default now()
);

create index if not exists saved_routes_user_idx on public.saved_routes (user_id, created_at desc);

alter table public.saved_routes enable row level security;

create policy "saved_routes_select_own" on public.saved_routes
  for select to authenticated using (auth.uid() = user_id);
create policy "saved_routes_insert_own" on public.saved_routes
  for insert to authenticated with check (auth.uid() = user_id);
create policy "saved_routes_update_own" on public.saved_routes
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "saved_routes_delete_own" on public.saved_routes
  for delete to authenticated using (auth.uid() = user_id);
