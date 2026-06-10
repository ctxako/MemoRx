-- ───────────────────────────────────────────────────────────────────────────
-- Migration: ensure_rls_on_missing_tables
--
-- WHY: daily_completions, weekly_results, and banned_usernames have RLS
-- enabled on the live database, but no prior migration file contained an
-- explicit ALTER TABLE ... ENABLE ROW LEVEL SECURITY statement for these
-- tables. Without this file, a fresh db reset would leave those tables
-- without RLS, exposing all rows to any authenticated or anonymous caller.
--
-- IDEMPOTENT: enabling RLS on an already-protected table is a no-op.
-- ───────────────────────────────────────────────────────────────────────────

ALTER TABLE public.daily_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.weekly_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.banned_usernames ENABLE ROW LEVEL SECURITY;
