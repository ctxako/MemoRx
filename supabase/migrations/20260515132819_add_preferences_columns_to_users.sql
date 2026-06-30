-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

alter table public.users add column if not exists flagged_drug_ids text[];
alter table public.users add column if not exists daily_reminder_enabled boolean default false;
alter table public.users add column if not exists daily_reminder_hour smallint;
alter table public.users add column if not exists daily_reminder_minute smallint;
alter table public.users add column if not exists selected_theme text;
alter table public.users add column if not exists high_contrast_enabled boolean default false;
alter table public.users add column if not exists apple_given_name text;
alter table public.users add column if not exists start_date timestamp;
