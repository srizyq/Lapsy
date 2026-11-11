-- Lapsy: extra numbers kept with each run, and favourite routes.
-- Run this once in Supabase -> SQL Editor (after 0003_shared_routes.sql).

alter table public.runs
  add column if not exists ascent_m double precision,
  add column if not exists splits   jsonb,
  add column if not exists surface  jsonb;

alter table public.saved_routes
  add column if not exists favorite boolean not null default false;
