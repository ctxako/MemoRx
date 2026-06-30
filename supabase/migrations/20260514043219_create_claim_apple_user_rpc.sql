-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Called by iOS immediately after signInWithIdToken(.apple) succeeds.
-- Three flows:
--   (1) Fresh user (no prior anon row): creates a stub users row tied to auth.uid().
--   (2) Anon → Apple upgrade (iOS knows the previous anon UID): migrates the anon
--       row's stats + dependent rows (drug_progress, quiz_attempts, daily_completions)
--       onto the new Apple-derived auth.uid(), then deletes the orphan.
--   (3) Second-device / reinstall (auth.uid() already has a row): no-op merge,
--       just refreshes apple_user_id and last_active.
CREATE OR REPLACE FUNCTION public.claim_apple_user(
  p_apple_user_id text,
  p_previous_anon_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_new_id  uuid := auth.uid();
  v_old_row public.users%ROWTYPE;
  v_found_old boolean := false;
BEGIN
  IF v_new_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_apple_user_id IS NULL OR length(btrim(p_apple_user_id)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_apple_user_id');
  END IF;

  -- Find the anon source row, in order: explicit hint from iOS, then by apple_user_id history.
  IF p_previous_anon_id IS NOT NULL AND p_previous_anon_id <> v_new_id THEN
    SELECT * INTO v_old_row FROM public.users WHERE id = p_previous_anon_id;
    IF FOUND THEN v_found_old := true; END IF;
  END IF;

  IF NOT v_found_old THEN
    SELECT * INTO v_old_row FROM public.users
     WHERE apple_user_id = p_apple_user_id AND id <> v_new_id
     ORDER BY total_xp DESC, last_active DESC NULLS LAST
     LIMIT 1;
    IF FOUND THEN v_found_old := true; END IF;
  END IF;

  IF v_found_old THEN
    -- Move stats onto the new Apple-derived id. Upsert to handle the "row already exists" case
    -- (e.g. syncToSupabase fired before claim_apple_user did).
    INSERT INTO public.users (
      id, legacy_user_id, display_name, total_xp, weekly_xp, streak,
      level, level_title, drugs_studied, is_lifetime, created_at,
      last_active, naplex_date, student_level, student_level_title, apple_user_id
    )
    VALUES (
      v_new_id,
      v_old_row.legacy_user_id,
      v_old_row.display_name,
      COALESCE(v_old_row.total_xp, 0),
      COALESCE(v_old_row.weekly_xp, 0),
      COALESCE(v_old_row.streak, 0),
      COALESCE(v_old_row.level, 1),
      v_old_row.level_title,
      COALESCE(v_old_row.drugs_studied, 0),
      COALESCE(v_old_row.is_lifetime, false),
      COALESCE(v_old_row.created_at, now()),
      now(),
      v_old_row.naplex_date,
      v_old_row.student_level,
      v_old_row.student_level_title,
      p_apple_user_id
    )
    ON CONFLICT (id) DO UPDATE SET
      total_xp           = GREATEST(public.users.total_xp,  EXCLUDED.total_xp),
      weekly_xp          = GREATEST(public.users.weekly_xp, EXCLUDED.weekly_xp),
      streak             = GREATEST(public.users.streak,    EXCLUDED.streak),
      level              = GREATEST(public.users.level,     EXCLUDED.level),
      level_title        = COALESCE(EXCLUDED.level_title,        public.users.level_title),
      drugs_studied      = GREATEST(public.users.drugs_studied, EXCLUDED.drugs_studied),
      is_lifetime        = public.users.is_lifetime OR EXCLUDED.is_lifetime,
      display_name       = COALESCE(EXCLUDED.display_name,       public.users.display_name),
      legacy_user_id     = COALESCE(public.users.legacy_user_id, EXCLUDED.legacy_user_id),
      naplex_date        = COALESCE(EXCLUDED.naplex_date,        public.users.naplex_date),
      student_level      = COALESCE(EXCLUDED.student_level,      public.users.student_level),
      student_level_title= COALESCE(EXCLUDED.student_level_title,public.users.student_level_title),
      apple_user_id      = EXCLUDED.apple_user_id,
      last_active        = now();

    -- Reassign dependent rows. Order: dependents first, then delete orphan.
    UPDATE public.drug_progress    SET user_id = v_new_id WHERE user_id = v_old_row.id;
    UPDATE public.quiz_attempts    SET user_id = v_new_id WHERE user_id = v_old_row.id;
    UPDATE public.daily_completions SET user_id = v_new_id WHERE user_id = v_old_row.id;

    DELETE FROM public.users WHERE id = v_old_row.id;

    RETURN jsonb_build_object(
      'success', true,
      'merged', true,
      'previous_id', v_old_row.id
    );
  ELSE
    -- No prior row to merge. Ensure a row exists for v_new_id and tag it with apple_user_id.
    INSERT INTO public.users (id, apple_user_id, display_name, total_xp, weekly_xp, streak, is_lifetime, created_at, last_active)
    VALUES (v_new_id, p_apple_user_id, NULL, 0, 0, 0, false, now(), now())
    ON CONFLICT (id) DO UPDATE SET
      apple_user_id = EXCLUDED.apple_user_id,
      last_active   = now();

    RETURN jsonb_build_object('success', true, 'merged', false);
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_apple_user(text, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.claim_apple_user(text, uuid) TO authenticated;
