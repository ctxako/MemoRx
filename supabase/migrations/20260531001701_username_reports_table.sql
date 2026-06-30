-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


CREATE TABLE public.username_reports (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id    uuid REFERENCES public.users(id) ON DELETE SET NULL,
  reported_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reported_name  text NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.username_reports ENABLE ROW LEVEL SECURITY;

-- Any authenticated/anonymous user can submit a report for their own session
CREATE POLICY "users can insert reports"
  ON public.username_reports
  FOR INSERT
  WITH CHECK (reporter_id = auth.uid());

-- Admin review query (run as service_role):
-- SELECT r.id, r.reported_name, r.created_at,
--        u.display_name AS current_name, u.apple_given_name, u.apple_user_id
-- FROM username_reports r
-- JOIN users u ON u.id = r.reported_id
-- ORDER BY r.created_at DESC;
