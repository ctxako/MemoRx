-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Phase 1: normalized taxonomy reference tables (additive; app-invisible)
create table if not exists public.collections (
  id text primary key,
  display_name text not null,
  sort_order int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.drug_classes (
  id text primary key,
  collection_id text not null references public.collections(id),
  display_name text not null,
  suffixes text[] not null default '{}',
  class_uses text[] not null default '{}',
  hallmark_side_effects text[] not null default '{}',
  high_yield_pearls text[] not null default '{}',
  high_risk_meds text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- RLS mirrors public.drugs / public.class_quizzes: anon+authenticated read-only, service_role full
alter table public.collections enable row level security;
alter table public.drug_classes enable row level security;

create policy "collections_read_anon"           on public.collections  for select to anon          using (true);
create policy "collections_read_authenticated"  on public.collections  for select to authenticated using (true);
create policy "drug_classes_read_anon"          on public.drug_classes for select to anon          using (true);
create policy "drug_classes_read_authenticated" on public.drug_classes for select to authenticated using (true);

grant select on public.collections  to anon, authenticated;
grant select on public.drug_classes to anon, authenticated;
grant all    on public.collections  to service_role;
grant all    on public.drug_classes to service_role;
