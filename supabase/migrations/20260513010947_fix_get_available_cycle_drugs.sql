-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- The queue IS the source of truth. Remove the NOT EXISTS future-slot filter
-- which incorrectly excluded cycle-2 queue drugs that also appeared in cycle-1 slots.
CREATE OR REPLACE FUNCTION get_available_cycle_drugs()
RETURNS TABLE(id text, generic_name text) LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
DECLARE
  v_queue jsonb;
BEGIN
  SELECT value INTO v_queue FROM app_settings WHERE key = 'challenge_cycle_remaining';

  IF v_queue IS NULL OR jsonb_array_length(v_queue) = 0 THEN
    -- Cycle complete — next auto-fill will shuffle a fresh cycle; show all drugs
    RETURN QUERY SELECT d.id, d.generic_name FROM drugs d ORDER BY d.generic_name;
  ELSE
    -- Return only drugs still in the queue (haven't had their slot this cycle yet)
    RETURN QUERY
      SELECT d.id, d.generic_name FROM drugs d
      WHERE d.id IN (SELECT jsonb_array_elements_text(v_queue))
      ORDER BY d.generic_name;
  END IF;
END;
$$;
