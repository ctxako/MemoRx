-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- REBUILD: Option A cycle system
-- 7-day forward buffer, self-healing, auto-append on drug insert
-- ============================================================

BEGIN;

-- ── 1. Delete test drug from schedule and catalog
DELETE FROM public.daily_challenges WHERE drug_id = 'test';
DELETE FROM public.drugs WHERE id = 'test';

-- ── 2. Wipe all future challenge assignments beyond today
--    Today's assignment stays locked (users may be mid-session)
DELETE FROM public.daily_challenges
WHERE challenge_date > current_challenge_date();

-- ── 3. Drop old complex RPCs we are replacing
DROP FUNCTION IF EXISTS public.auto_fill_challenge_schedule(integer);
DROP FUNCTION IF EXISTS public.admin_reset_cycle();
DROP FUNCTION IF EXISTS public.get_available_cycle_drugs();

-- ── 4. Reset the cycle queue to full shuffled catalog
--    (minus today's drug which is already assigned)
UPDATE public.app_settings
SET value = (
  SELECT jsonb_agg(d.id ORDER BY random())
  FROM public.drugs d
  WHERE d.id != (
    SELECT drug_id FROM public.daily_challenges
    WHERE challenge_date = current_challenge_date()
    LIMIT 1
  )
)
WHERE key = 'challenge_cycle_remaining';

-- ── 5. NEW: fill_challenge_buffer(days_ahead)
--    Fills only N days ahead (default 7) from the cycle queue.
--    Called on every app launch via get_current_challenge.
--    When queue empties, reshuffles full catalog and continues.
CREATE OR REPLACE FUNCTION public.fill_challenge_buffer(
  p_days_ahead integer DEFAULT 7
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today      date := current_challenge_date();
  v_queue      text[];
  v_raw        jsonb;
  v_date       date;
  v_drug_id    text;
  v_filled     integer := 0;
  v_dates      date[];
BEGIN
  -- Find dates in the buffer window that have no assignment yet
  SELECT array_agg(d ORDER BY d)
  INTO v_dates
  FROM (
    SELECT (v_today + gs)::date AS d
    FROM generate_series(1, p_days_ahead) AS gs
  ) t
  WHERE NOT EXISTS (
    SELECT 1 FROM daily_challenges dc WHERE dc.challenge_date = t.d
  );

  -- Nothing to fill
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

  -- Fill each missing date
  FOREACH v_date IN ARRAY v_dates LOOP

    -- If queue is empty, reshuffle full catalog
    -- excluding drugs already assigned in the current buffer window
    IF array_length(v_queue, 1) IS NULL THEN
      SELECT array_agg(d.id ORDER BY random())
      INTO v_queue
      FROM drugs d
      WHERE d.id NOT IN (
        SELECT drug_id FROM daily_challenges
        WHERE challenge_date > v_today
      );
    END IF;

    -- Safety: if still empty (no drugs in catalog), bail
    IF array_length(v_queue, 1) IS NULL THEN
      EXIT;
    END IF;

    -- Take next drug from queue
    v_drug_id := v_queue[1];
    v_queue   := v_queue[2:array_length(v_queue, 1)];

    INSERT INTO daily_challenges (challenge_date, drug_id)
    VALUES (v_date, v_drug_id)
    ON CONFLICT (challenge_date) DO NOTHING;

    v_filled := v_filled + 1;
  END LOOP;

  -- Persist remaining queue
  UPDATE app_settings
  SET value = to_jsonb(COALESCE(v_queue, ARRAY[]::text[]))
  WHERE key = 'challenge_cycle_remaining';

  RETURN jsonb_build_object('filled', v_filled);
END;
$$;

-- ── 6. NEW: admin_reset_cycle()
--    Wipes all future assignments, reshuffles full catalog,
--    immediately fills 7-day buffer fresh.
CREATE OR REPLACE FUNCTION public.admin_reset_cycle()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- Immediately fill the 7-day buffer
  PERFORM fill_challenge_buffer(7);

  RETURN jsonb_build_object('ok', true, 'reset_date', v_today);
END;
$$;

-- ── 7. UPDATE: get_current_challenge()
--    Now calls fill_challenge_buffer(7) instead of the old 90-day fill.
--    Self-healing: every app launch tops up the 7-day buffer.
CREATE OR REPLACE FUNCTION public.get_current_challenge()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today  date;
  v_et     timestamptz;
  v_ch     record;
  v_result jsonb;
BEGIN
  v_today := current_challenge_date();
  v_et    := NOW() AT TIME ZONE 'America/New_York';

  -- Self-healing: fill 7-day buffer on every call
  PERFORM fill_challenge_buffer(7);

  -- Get today's drug
  SELECT drug_id INTO v_ch
  FROM daily_challenges
  WHERE challenge_date = v_today
  LIMIT 1;

  SELECT jsonb_build_object(
    'current_challenge_date',         v_today,
    'minutes_until_next_et_boundary',
      CASE
        WHEN EXTRACT(HOUR FROM v_et) < 4
          THEN CEIL(EXTRACT(EPOCH FROM (date_trunc('day', v_et) + INTERVAL '4 hours' - v_et)) / 60)::int
        ELSE CEIL(EXTRACT(EPOCH FROM (date_trunc('day', v_et) + INTERVAL '1 day 4 hours' - v_et)) / 60)::int
      END,
    'server_et_hour',   EXTRACT(HOUR   FROM v_et)::int,
    'server_et_minute', EXTRACT(MINUTE FROM v_et)::int,
    'drug_id',          v_ch.drug_id,
    'xp_base',          50
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- ── 8. NEW: get_cycle_status()
--    For the admin dashboard — returns full cycle picture:
--    current position, 7-day buffer, full remaining queue.
--    Used to render the dynamic cycle visualization.
CREATE OR REPLACE FUNCTION public.get_cycle_status()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today          date := current_challenge_date();
  v_total_drugs    integer;
  v_queue_raw      jsonb;
  v_queue_count    integer;
  v_used_count     integer;
  v_buffer         jsonb;
  v_queue_with_names jsonb;
BEGIN
  SELECT COUNT(*) INTO v_total_drugs FROM drugs;

  SELECT value INTO v_queue_raw
  FROM app_settings WHERE key = 'challenge_cycle_remaining';

  v_queue_count := COALESCE(jsonb_array_length(v_queue_raw), 0);

  -- How many drugs have been used in this cycle
  -- (total minus what's left in queue, minus buffer)
  SELECT COUNT(*) INTO v_used_count
  FROM daily_challenges
  WHERE challenge_date <= v_today;

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

  -- Queue with drug names (what comes after the buffer)
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
$$;

-- ── 9. NEW: Trigger — auto-append new drugs to cycle queue
--    When a drug is inserted into the drugs table,
--    it is immediately appended to challenge_cycle_remaining
--    so it flows into the rotation automatically.
CREATE OR REPLACE FUNCTION public.append_new_drug_to_cycle()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE app_settings
  SET value = COALESCE(value, '[]'::jsonb) || to_jsonb(NEW.id)
  WHERE key = 'challenge_cycle_remaining';

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_append_drug_to_cycle ON public.drugs;

CREATE TRIGGER trg_append_drug_to_cycle
AFTER INSERT ON public.drugs
FOR EACH ROW
EXECUTE FUNCTION public.append_new_drug_to_cycle();

-- ── 10. Fill the 7-day buffer immediately with clean data
SELECT fill_challenge_buffer(7);

COMMIT;
