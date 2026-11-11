-- Lapsy: share links for routes. Run this once in Supabase → SQL Editor
-- (after 0002_runs_and_routes.sql).

create table if not exists public.shared_routes (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null,
  activity_id text not null,
  distance_m  double precision not null,
  ascent_m    double precision not null default 0,
  polyline    text not null,
  created_at  timestamptz not null default now()
);

alter table public.shared_routes enable row level security;

-- Only the owner can list, add or remove their own shared routes.
create policy "shared_routes_select_own" on public.shared_routes
  for select to authenticated using (auth.uid() = user_id);
create policy "shared_routes_insert_own" on public.shared_routes
  for insert to authenticated with check (auth.uid() = user_id);
create policy "shared_routes_update_own" on public.shared_routes
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "shared_routes_delete_own" on public.shared_routes
  for delete to authenticated using (auth.uid() = user_id);

-- Anyone with the link can open ONE route by its id. The web page uses this.
-- The table itself can't be listed, and the owner's id is never returned.
create or replace function public.get_shared_route(p_id uuid)
returns table (name text, activity_id text, distance_m double precision, ascent_m double precision, polyline text)
language sql security definer set search_path = '' stable as $$
  select r.name, r.activity_id, r.distance_m, r.ascent_m, r.polyline
  from public.shared_routes r
  where r.id = p_id;
$$;

revoke all on function public.get_shared_route(uuid) from public;
grant execute on function public.get_shared_route(uuid) to anon, authenticated;
