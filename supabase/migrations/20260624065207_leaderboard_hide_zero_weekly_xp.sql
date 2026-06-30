-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


CREATE OR REPLACE VIEW leaderboard_public AS
SELECT
  CASE
    WHEN id = auth.uid() THEN id
    ELSE md5(id::text || 'memorx-lb-v1'::text)::uuid
  END AS id,
  legacy_user_id,
  display_name,
  total_xp,
  weekly_xp,
  streak,
  level_title,
  drugs_studied,
  student_level
FROM users u
WHERE lower(btrim(display_name::text)) !~~ '%signed out%'::text
  AND weekly_xp > 0;
