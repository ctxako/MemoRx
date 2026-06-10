-- Reference schema for MemoRx iOS ↔ Supabase row types (see SupabaseManager.swift).
-- This file reflects the live production schema as of 2026-05-14. It is documentation
-- only — the project is past bootstrap. Do not run end-to-end; use targeted ALTERs.
--
-- iOS directly queries: users, drug_progress, drug_submissions, quiz_attempts,
-- and the view leaderboard_public. Daily-challenge tables (daily_challenges,
-- daily_completions) are RPC-mediated (submit_daily_completion / get_current_challenge)
-- and are not queried from the client; see RPC notes at the bottom of this file.

-- ───────────────────────────────────────────────────────────────────────────
-- public.users
--
-- Drift notes vs. an earlier bootstrap-style schema:
--   • legacy_user_id is NULLABLE in live (was NOT NULL UNIQUE).
--   • display_name is the `citext` (case-insensitive) domain, NULLABLE. The UNIQUE
--     partial index (`users_display_name_unique WHERE display_name IS NOT NULL`)
--     is re-enabled as of 2026-05-30. Admin-cleared names (NULL) are allowed;
--     non-NULL names must be unique.
--   • display_name_updated_at is auto-stamped by trg_display_name_updated_at
--     whenever display_name changes. Used for the 30-day rename cooldown.
--   • Numeric counters (total_xp, streak, level, drugs_studied, level_title)
--     are NULLABLE with DEFAULT — live tolerates NULL even though the client
--     always writes a value.
--   • created_at / last_active are `timestamp without time zone` in live
--     (not timestamptz).
--   • Added columns: display_name_updated_at, student_level, student_level_title.
-- ───────────────────────────────────────────────────────────────────────────
create extension if not exists citext;

create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  legacy_user_id text,
  apple_user_id text,
  display_name public.citext,
  total_xp int default 0,
  streak int default 0,
  level int default 1,
  level_title text,
  drugs_studied int default 0,
  weekly_xp int not null default 0,
  is_anonymous boolean not null default false,
  is_lifetime boolean not null default false,
  subscription_status text not null default 'none',
  subscription_product_id text,
  subscription_expires_at timestamptz,
  subscription_started_at timestamptz,
  trial_started_at timestamptz,
  original_transaction_id text,
  display_name_updated_at timestamp,
  student_level text,
  student_level_title text,
  naplex_date date,
  flagged_drug_ids text[],
  daily_reminder_enabled boolean default false,
  daily_reminder_hour smallint,
  daily_reminder_minute smallint,
  selected_theme text,
  high_contrast_enabled boolean default false,
  apple_given_name text,
  start_date timestamp,
  created_at timestamp default now(),
  last_active timestamp
);

-- Cross-device preference sync (added 2026-05-15). Safe to re-run on live.
alter table public.users add column if not exists flagged_drug_ids text[];
alter table public.users add column if not exists daily_reminder_enabled boolean default false;
alter table public.users add column if not exists daily_reminder_hour smallint;
alter table public.users add column if not exists daily_reminder_minute smallint;
alter table public.users add column if not exists selected_theme text;
alter table public.users add column if not exists high_contrast_enabled boolean default false;
alter table public.users add column if not exists apple_given_name text;
alter table public.users add column if not exists start_date timestamp;

-- Partial index used by Apple sign-in lookups (claim_apple_user RPC).
create index if not exists users_apple_user_id_idx
  on public.users (apple_user_id)
  where apple_user_id is not null;

-- ───────────────────────────────────────────────────────────────────────────
-- public.drug_progress — per-user spaced repetition state.
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.drug_progress (
  user_id uuid not null references auth.users (id) on delete cascade,
  drug_id text not null,
  scores int[] not null default '{}',
  next_review timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, drug_id)
);

-- ───────────────────────────────────────────────────────────────────────────
-- public.drug_submissions — user-requested drugs (Settings → Request a drug).
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.drug_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  drug_name text not null,
  reason text,
  created_at timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────────────────────
-- public.quiz_attempts — analytics log written by logQuizAttempt(...).
-- XP is authoritative on `public.users.total_xp`; this table is for telemetry.
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  drug_id text not null,
  correct_count int not null,
  total_questions int not null,
  xp_awarded int not null,
  timestamp timestamptz not null default now()
);

-- ───────────────────────────────────────────────────────────────────────────
-- public.leaderboard_public — non-sensitive ranking projection over users.
-- security_invoker = false: view reads as owner so strict RLS on `users`
-- (own-row-only) does not collapse the leaderboard to one row.
-- ───────────────────────────────────────────────────────────────────────────
create or replace view public.leaderboard_public
with (security_invoker = false) as
select
  id,
  legacy_user_id,
  display_name,
  total_xp,
  weekly_xp,
  streak,
  level_title,
  drugs_studied,
  student_level
from public.users
where lower(btrim(display_name::text)) not like '%signed out%';

grant select on public.leaderboard_public to authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- Row Level Security
-- ───────────────────────────────────────────────────────────────────────────
alter table public.users enable row level security;
alter table public.drug_progress enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.drug_submissions enable row level security;

drop policy if exists "users_select" on public.users;
create policy "users_select" on public.users for select using (auth.uid() = id);
create policy "users_insert" on public.users for insert with check (auth.uid() = id);
create policy "users_update" on public.users for update using (auth.uid() = id);

create policy "drug_progress_all" on public.drug_progress for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "quiz_attempts_all" on public.quiz_attempts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "drug_submissions_all" on public.drug_submissions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ───────────────────────────────────────────────────────────────────────────
-- Tables NOT queried directly by the iOS client (RPC-mediated or admin-only).
-- Documented here for reference; see Supabase dashboard for full DDL.
--
--   • public.drugs              — drug catalog (also bundled as JSON in-app).
--   • public.daily_challenges   — daily-challenge schedule, written by admin
--                                 (and by fill_challenge_buffer / claim_challenge_drug
--                                 RPCs). Read via get_current_challenge RPC.
--   • public.daily_completions  — per-user, per-challenge completion records,
--                                 written exclusively by submit_daily_completion RPC.
--                                 Authoritative XP writer for the daily challenge.
--   • public.banned_usernames   — display-name moderation list.
--   • public.class_quizzes      — optional remote class quiz catalog.
--   • public.admin_audit_log    — admin-action audit trail.
--   • public.app_settings       — runtime feature flags / config.
--   • public.username_reports   — leaderboard name reports. Append-only for
--                                 users (RLS: insert own, select own). Admin
--                                 reviews via service_role. UNIQUE(reporter_id,
--                                 reported_id) prevents spam.
--
-- RPCs invoked by the iOS client:
--   • submit_daily_completion(p_user_id uuid, p_drug_id text,
--       p_correct_count int, p_total_questions int) returns jsonb
--   • get_current_challenge() returns jsonb
--   • claim_apple_user(p_apple_user_id text,
--       p_previous_anon_id uuid default null) returns jsonb
--
-- RPCs that exist server-side but are admin-only / not called by the client:
--   • fill_challenge_buffer(p_days_ahead int default 7) returns jsonb
--   • claim_challenge_drug(p_challenge_date date, p_drug_id text) returns jsonb
--   • check_challenge_locked() returns trigger
--   • current_challenge_date() returns date
-- ───────────────────────────────────────────────────────────────────────────

-- ───────────────────────────────────────────────────────────────────────────
-- Migration: add has_completed_onboarding
-- Run once via Supabase dashboard SQL editor or: supabase db push
-- ───────────────────────────────────────────────────────────────────────────
alter table public.users
  add column if not exists has_completed_onboarding boolean not null default false;


-- ───────────────────────────────────────────────────────────────────────────
-- Migration: auto-create public.users stub on every new auth.users row
-- Fixes FK violation when an anonymous session is created before claim_apple_user runs.
-- claim_apple_user uses ON CONFLICT DO UPDATE so it upgrades the stub cleanly.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, is_anonymous, created_at, last_active)
  VALUES (NEW.id, true, now(), now())
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_auth_user();
