-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

CREATE OR REPLACE FUNCTION public.claim_apple_user(p_apple_user_id text, p_previous_anon_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_new_id               uuid    := auth.uid();
  v_old_row              public.users%ROWTYPE;
  v_found_old            boolean := false;
  v_saved_name           text;
  v_existing_apple_acct  boolean := false;
BEGIN
  IF v_new_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;
  IF p_apple_user_id IS NULL OR length(btrim(p_apple_user_id)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'missing_apple_user_id');
  END IF;

  -- Verify the caller actually owns the Apple identity they claim. Native Apple
  -- sign-in (signInWithIdToken) records the verified sub in auth.identities, so
  -- this blocks passing someone else's Apple sub.
  IF NOT EXISTS (
    SELECT 1 FROM auth.identities
    WHERE user_id = v_new_id
      AND provider = 'apple'
      AND provider_id = p_apple_user_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'apple_identity_mismatch');
  END IF;

  -- Detect before any writes whether this Apple ID already has an account.
  -- This drives the Swift onboarding-skip decision on the client.
  SELECT EXISTS(
    SELECT 1 FROM public.users
    WHERE apple_user_id = p_apple_user_id
  ) INTO v_existing_apple_acct;

  -- Locate the source row to merge from. Only a genuinely anonymous account may
  -- be absorbed, so a caller cannot merge/delete another real (non-anon) account
  -- by passing its UUID. auth.users.is_anonymous is the authoritative flag.
  IF p_previous_anon_id IS NOT NULL AND p_previous_anon_id <> v_new_id THEN
    SELECT u.* INTO v_old_row
    FROM public.users u
    JOIN auth.users au ON au.id = u.id
    WHERE u.id = p_previous_anon_id AND au.is_anonymous = true;
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
    v_saved_name := v_old_row.display_name;

    INSERT INTO public.users (
      id, legacy_user_id, display_name, total_xp, weekly_xp, streak,
      level, level_title, drugs_studied, is_lifetime, created_at,
      last_active, naplex_date, student_level, student_level_title,
      apple_user_id, is_anonymous, start_date
    )
    VALUES (
      v_new_id,
      v_old_row.legacy_user_id,
      NULL,
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
      p_apple_user_id,
      false,  -- authenticated: never anonymous
      v_old_row.start_date
    )
    ON CONFLICT (id) DO UPDATE SET
      total_xp            = GREATEST(public.users.total_xp,       EXCLUDED.total_xp),
      weekly_xp           = GREATEST(public.users.weekly_xp,      EXCLUDED.weekly_xp),
      streak              = GREATEST(public.users.streak,         EXCLUDED.streak),
      level               = GREATEST(public.users.level,          EXCLUDED.level),
      level_title         = COALESCE(EXCLUDED.level_title,        public.users.level_title),
      drugs_studied       = GREATEST(public.users.drugs_studied,  EXCLUDED.drugs_studied),
      is_lifetime         = public.users.is_lifetime OR EXCLUDED.is_lifetime,
      legacy_user_id      = COALESCE(public.users.legacy_user_id, EXCLUDED.legacy_user_id),
      naplex_date         = COALESCE(EXCLUDED.naplex_date,        public.users.naplex_date),
      student_level       = COALESCE(EXCLUDED.student_level,      public.users.student_level),
      student_level_title = COALESCE(EXCLUDED.student_level_title,public.users.student_level_title),
      apple_user_id       = EXCLUDED.apple_user_id,
      is_anonymous        = false,
      last_active         = now(),
      start_date          = COALESCE(public.users.start_date, EXCLUDED.start_date);

    UPDATE public.drug_progress     SET user_id = v_new_id WHERE user_id = v_old_row.id;
    UPDATE public.quiz_attempts     SET user_id = v_new_id WHERE user_id = v_old_row.id;
    UPDATE public.daily_completions SET user_id = v_new_id WHERE user_id = v_old_row.id;

    DELETE FROM public.users WHERE id = v_old_row.id;

    IF v_saved_name IS NOT NULL AND length(v_saved_name) > 0 THEN
      UPDATE public.users
         SET display_name = v_saved_name
       WHERE id = v_new_id AND display_name IS NULL;
    END IF;

    RETURN jsonb_build_object(
      'success',               true,
      'merged',                true,
      'previous_id',           v_old_row.id,
      'existing_apple_account', v_existing_apple_acct
    );
  ELSE
    INSERT INTO public.users (
      id, apple_user_id, display_name, total_xp, weekly_xp, streak,
      is_lifetime, is_anonymous, created_at, last_active
    )
    VALUES (
      v_new_id, p_apple_user_id, NULL, 0, 0, 0, false, false, now(), now()
    )
    ON CONFLICT (id) DO UPDATE SET
      apple_user_id = EXCLUDED.apple_user_id,
      is_anonymous  = false,
      last_active   = now();

    RETURN jsonb_build_object(
      'success',               true,
      'merged',                false,
      'existing_apple_account', v_existing_apple_acct
    );
  END IF;
END;
$function$
