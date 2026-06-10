-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: fix_username_reports_fk
--
-- WHY: The original migration declared reported_id with both NOT NULL and
-- ON DELETE SET NULL, which are mutually exclusive. When a reported user runs
-- delete_my_account(), Postgres tries to SET NULL reported_id but the NOT NULL
-- constraint rejects it — so any user who has been reported cannot delete their
-- account. This migration switches the FK to ON DELETE CASCADE so the report
-- row is deleted when the reported user's auth.users row is removed.
--
-- EFFECT: existing reports for deleted users are also removed (one-off).
-- IDEMPOTENT: safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

begin;

alter table public.username_reports
  drop constraint if exists username_reports_reported_id_fkey;

alter table public.username_reports
  add constraint username_reports_reported_id_fkey
    foreign key (reported_id) references auth.users (id) on delete cascade;

commit;
