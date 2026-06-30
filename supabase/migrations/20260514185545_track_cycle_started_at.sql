-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Track when the current cycle began. `app_settings.cycle_started_at` holds an
-- ISO date string. It is updated by:
--   • admin_reset_cycle()                 — admin presses Reset Cycle in MemoRx Admin
--   • fill_challenge_buffer() (mid-fill)  — queue exhausted, auto-reshuffles full catalog
--
-- get_cycle_status().drugs_used_this_cycle now counts only daily_challenges
-- whose challenge_date is in [cycle_started_at, current_challenge_date()].

INSERT INTO public.app_settings (key, value)
VALUES ('cycle_started_at', to_jsonb(public.current_challenge_date()::text))
ON CONFLICT (key) DO NOTHING;

-- ─── admin_reset_cycle: stamp cycle_started_at on every reset ──────────────
CREATE OR REPLACE FUNCTION public.admin_reset_cycle()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_today date := current_challenge_date();
BEGIN
  -- Wipe all future assignments (today stays)
  DELETE FROM daily_challenges WHERE challenge_date > v_today;

  -- Fresh shuffle of full catalog minus today's drug
  UPDATE app_settings
  SET value = (
    SELECT jsonb_agg(id ORDER BY random())
    FROM drugs
    WHERE id != (
      SELECT drug_id FROM daily_challenges
      WHERE challenge_date = v_today
      LIMIT 1
    )
  )
  WHERE key = 'challenge_cycle_remaining';

  -- Stamp the current cycle's start date so per-cycle counters reset.
  INSERT INTO app_settings (key, value)
  VALUES ('cycle_started_at', to_jsonb(v_today::text))
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  -- Immediately fill the 7-day buffer
  PERFORM fill_challenge_buffer(7);

  RETURN jsonb_build_object('ok', true, 'reset_date', v_today);
END;
$function$;

-- ─── fill_challenge_buffer: stamp cycle_started_at on auto-reshuffle ───────
CREATE OR REPLACE FUNCTION public.fill_challenge_buffer(p_days_ahead integer DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_today      date := current_challenge_date();
  v_queue      text[];
  v_raw        jsonb;
  v_date       date;
  v_drug_id    text;
  v_filled     integer := 0;
  v_dates      date[];
BEGIN
  -- Dates in the buffer window that have no assignment yet
  SELECT array_agg(d ORDER BY d)
  INTO v_dates
  FROM (
    SELECT (v_today + gs)::date AS d
    FROM generate_series(1, p_days_ahead) AS gs
  ) t
  WHERE NOT EXISTS (
    SELECT 1 FROM daily_challenges dc WHERE dc.challenge_date = t.d
  );

  IF v_dates IS NULL THEN
    RETURN jsonb_build_object('filled', 0);
  END IF;

  -- Load current queue
  SELECT value INTO v_raw FROM app_settings WHERE key = 'challenge_cycle_remaining';
  IF v_raw IS NOT NULL AND jsonb_array_length(v_raw) > 0 THEN
    SELECT array_agg(x ORDER BY ord)
    INTO v_queue
    FROM jsonb_array_elements_text(v_raw) WITH ORDINALITY AS t(x, ord);
  ELSE
    v_queue := ARRAY[]::text[];
  END IF;

  FOREACH v_date IN ARRAY v_dates LOOP

    -- Queue empty → start a new cycle: reshuffle full catalog (minus drugs
    -- already pinned to future slots), and stamp cycle_started_at to this
    -- buffer date (the first day of the new cycle).
    IF array_length(v_queue, 1) IS NULL THEN
      SELECT array_agg(d.id ORDER BY random())
      INTO v_queue
      FROM drugs d
      WHERE d.id NOT IN (
        SELECT drug_id FROM daily_challenges
        WHERE challenge_date > v_today
      );

      INSERT INTO app_settings (key, value)
      VALUES ('cycle_started_at', to_jsonb(v_date::text))
      ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
    END IF;

    IF array_length(v_queue, 1) IS NULL THEN
      EXIT;
    END IF;

    v_drug_id := v_queue[1];
    v_queue   := v_queue[2:array_length(v_queue, 1)];

    INSERT INTO daily_challenges (challenge_date, drug_id)
    VALUES (v_date, v_drug_id)
    ON CONFLICT (challenge_date) DO NOTHING;

    v_filled := v_filled + 1;
  END LOOP;

  UPDATE app_settings
  SET value = to_jsonb(COALESCE(v_queue, ARRAY[]::text[]))
  WHERE key = 'challenge_cycle_remaining';

  RETURN jsonb_build_object('filled', v_filled);
END;
$function$;

-- ─── get_cycle_status: per-cycle counter via cycle_started_at ──────────────
CREATE OR REPLACE FUNCTION public.get_cycle_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_today              date := current_challenge_date();
  v_cycle_start        date;
  v_total_drugs        integer;
  v_queue_raw          jsonb;
  v_queue_count        integer;
  v_used_count         integer;
  v_buffer             jsonb;
  v_queue_with_names   jsonb;
BEGIN
  SELECT (value #>> '{}')::date INTO v_cycle_start
  FROM app_settings WHERE key = 'cycle_started_at';
  IF v_cycle_start IS NULL THEN
    v_cycle_start := v_today;  -- defensive: should always be set post-migration
  END IF;

  SELECT COUNT(*) INTO v_total_drugs FROM drugs;

  SELECT value INTO v_queue_raw
  FROM app_settings WHERE key = 'challenge_cycle_remaining';
  v_queue_count := COALESCE(jsonb_array_length(v_queue_raw), 0);

  -- Drugs served in the CURRENT cycle: challenge_date in [cycle_start, today].
  SELECT COUNT(*) INTO v_used_count
  FROM daily_challenges
  WHERE challenge_date >= v_cycle_start
    AND challenge_date <= v_today;

  -- 7-day buffer with drug names
  SELECT jsonb_agg(
    jsonb_build_object(
      'date', dc.challenge_date,
      'drug_id', dc.drug_id,
      'generic_name', d.generic_name,
      'drug_class', d.drug_class
    ) ORDER BY dc.challenge_date
  )
  INTO v_buffer
  FROM daily_challenges dc
  JOIN drugs d ON d.id = dc.drug_id
  WHERE dc.challenge_date > v_today
    AND dc.challenge_date <= v_today + 7;

  -- Queue with drug names (post-buffer order)
  SELECT jsonb_agg(
    jsonb_build_object(
      'drug_id', q.drug_id,
      'generic_name', d.generic_name,
      'drug_class', d.drug_class,
      'position', q.ord
    ) ORDER BY q.ord
  )
  INTO v_queue_with_names
  FROM jsonb_array_elements_text(v_queue_raw) WITH ORDINALITY AS q(drug_id, ord)
  JOIN drugs d ON d.id = q.drug_id;

  RETURN jsonb_build_object(
    'today', v_today,
    'cycle_started_at', v_cycle_start,
    'today_drug', (
      SELECT jsonb_build_object(
        'drug_id', dc.drug_id,
        'generic_name', d.generic_name
      )
      FROM daily_challenges dc
      JOIN drugs d ON d.id = dc.drug_id
      WHERE dc.challenge_date = v_today
    ),
    'total_drugs_in_catalog', v_total_drugs,
    'drugs_used_this_cycle', v_used_count,
    'drugs_remaining_in_queue', v_queue_count,
    'cycle_progress_pct', ROUND(100.0 * v_used_count / NULLIF(v_total_drugs, 0)),
    'buffer_next_7_days', COALESCE(v_buffer, '[]'::jsonb),
    'upcoming_queue', COALESCE(v_queue_with_names, '[]'::jsonb)
  );
END;
$function$;
