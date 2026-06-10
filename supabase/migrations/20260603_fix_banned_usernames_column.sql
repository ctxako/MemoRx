-- Fix banned_usernames column name: functions referenced 'username' but the column is 'term'.
-- This caused change_display_name to throw an unhandled exception (PostgREST 400) and
-- is_display_name_available to be ambiguous (PostgREST 300) because the stale citext
-- overload from before display_name_rpcs was never dropped.
--
-- Fixes applied to live DB 2026-06-03; this file documents those changes.
--   1. Drop stale is_display_name_available(citext) overload  → resolves 300 ambiguity
--   2. Recreate is_display_name_available(text) with lower(term) instead of lower(username)
--   3. Recreate change_display_name with lower(term) instead of lower(username)

DROP FUNCTION IF EXISTS public.is_display_name_available(p_name citext);

CREATE OR REPLACE FUNCTION public.is_display_name_available(p_name text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_banned boolean := false;
BEGIN
  IF NOT (
    length(p_name) BETWEEN 2 AND 20
    AND p_name ~ '^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$'
    AND p_name !~ '  '
  ) THEN
    RETURN false;
  END IF;

  IF to_regclass('public.banned_usernames') IS NOT NULL THEN
    EXECUTE
      'SELECT EXISTS(SELECT 1 FROM public.banned_usernames WHERE lower(term) = lower($1))'
      INTO v_banned USING p_name;
    IF v_banned THEN RETURN false; END IF;
  END IF;

  RETURN NOT EXISTS(
    SELECT 1 FROM public.users WHERE display_name = p_name::citext
  );
END;
$$;

REVOKE ALL ON FUNCTION public.is_display_name_available(text) FROM public;
GRANT EXECUTE ON FUNCTION public.is_display_name_available(text) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.change_display_name(p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_current_name public.citext;
  v_updated_at   timestamp;
  v_unlock_date  timestamp;
  v_banned       boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'not_authenticated');
  END IF;

  IF NOT (
    length(p_name) BETWEEN 2 AND 20
    AND p_name ~ '^[A-Za-z0-9][A-Za-z0-9 ]{0,18}[A-Za-z0-9]$'
    AND p_name !~ '  '
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_format');
  END IF;

  IF to_regclass('public.banned_usernames') IS NOT NULL THEN
    EXECUTE
      'SELECT EXISTS(SELECT 1 FROM public.banned_usernames WHERE lower(term) = lower($1))'
      INTO v_banned USING p_name;
    IF v_banned THEN
      RETURN jsonb_build_object('success', false, 'error', 'banned');
    END IF;
  END IF;

  SELECT display_name, display_name_updated_at
    INTO v_current_name, v_updated_at
    FROM public.users WHERE id = v_uid;

  IF v_current_name IS DISTINCT FROM p_name::public.citext THEN
    IF v_updated_at IS NOT NULL THEN
      v_unlock_date := v_updated_at + interval '30 days';
      IF now() < v_unlock_date THEN
        RETURN jsonb_build_object(
          'success',   false,
          'error',     'cooldown',
          'unlock_at', to_char(v_unlock_date AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        );
      END IF;
    END IF;

    IF EXISTS(
      SELECT 1 FROM public.users
      WHERE display_name = p_name::public.citext AND id != v_uid
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'name_taken');
    END IF;
  END IF;

  UPDATE public.users SET display_name = p_name::public.citext WHERE id = v_uid;

  RETURN jsonb_build_object('success', true);

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error', 'name_taken');
END;
$$;

REVOKE ALL ON FUNCTION public.change_display_name(text) FROM public;
GRANT EXECUTE ON FUNCTION public.change_display_name(text) TO authenticated;
