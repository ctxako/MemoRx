-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Create class_quizzes table (what the app actually looks for)
CREATE TABLE IF NOT EXISTS public.class_quizzes (
  sub_collection text PRIMARY KEY,
  display_name text NOT NULL,
  suffixes text[] NOT NULL DEFAULT '{}',
  class_uses text[] NOT NULL DEFAULT '{}',
  hallmark_side_effects text[] NOT NULL DEFAULT '{}',
  high_yield_pearls text[] NOT NULL DEFAULT '{}',
  high_risk_meds text[] NOT NULL DEFAULT '{}'
);

-- Copy data from drug_classes
INSERT INTO public.class_quizzes
SELECT sub_collection, display_name, suffixes, class_uses, hallmark_side_effects, high_yield_pearls, high_risk_meds
FROM public.drug_classes
ON CONFLICT (sub_collection) DO NOTHING;

-- RLS
ALTER TABLE public.class_quizzes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "class_quizzes_read_authenticated" ON public.class_quizzes;
CREATE POLICY "class_quizzes_read_authenticated"
  ON public.class_quizzes FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.class_quizzes TO authenticated;

-- Compatibility views for the other table names the app tries
CREATE OR REPLACE VIEW public.class_quiz_guides AS SELECT * FROM public.class_quizzes;
CREATE OR REPLACE VIEW public.class_quiz_content AS SELECT * FROM public.class_quizzes;
GRANT SELECT ON public.class_quiz_guides TO authenticated;
GRANT SELECT ON public.class_quiz_content TO authenticated;
