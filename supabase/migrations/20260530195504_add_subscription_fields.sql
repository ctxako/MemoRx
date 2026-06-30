-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- ============================================================
-- 1. Add subscription columns to public.users
-- ============================================================
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS subscription_status text NOT NULL DEFAULT 'none'
    CONSTRAINT users_subscription_status_check
      CHECK (subscription_status IN ('trial', 'active', 'expired', 'lifetime', 'none')),
  ADD COLUMN IF NOT EXISTS subscription_product_id text,
  ADD COLUMN IF NOT EXISTS subscription_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS trial_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS subscription_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS original_transaction_id text;

-- ============================================================
-- 2. Backfill existing lifetime users from legacy is_lifetime flag
-- ============================================================
UPDATE public.users
SET subscription_status = 'lifetime'
WHERE is_lifetime = true
  AND subscription_status = 'none';

-- ============================================================
-- 3. Indexes for subscription query performance
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_users_subscription_status
  ON public.users (subscription_status);

CREATE INDEX IF NOT EXISTS idx_users_subscription_expires_at
  ON public.users (subscription_expires_at)
  WHERE subscription_expires_at IS NOT NULL;

-- ============================================================
-- 4. Trigger: block authenticated/anon from writing subscription fields
--    service_role bypasses RLS but the trigger still fires — the
--    current_user check lets service_role writes through.
--    NOTE: no SECURITY DEFINER so current_user reflects the calling role.
-- ============================================================
CREATE OR REPLACE FUNCTION public.guard_subscription_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only service_role (server-side receipt validation) may change these fields
  IF current_user != 'service_role' THEN
    NEW.subscription_status      := OLD.subscription_status;
    NEW.subscription_product_id  := OLD.subscription_product_id;
    NEW.subscription_expires_at  := OLD.subscription_expires_at;
    NEW.trial_started_at         := OLD.trial_started_at;
    NEW.subscription_started_at  := OLD.subscription_started_at;
    NEW.original_transaction_id  := OLD.original_transaction_id;
    NEW.is_lifetime              := OLD.is_lifetime;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_subscription_fields ON public.users;
CREATE TRIGGER guard_subscription_fields
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_subscription_fields();

-- ============================================================
-- 5. Helper function: is_user_subscribed(uuid)
--    SECURITY DEFINER so it can read the row regardless of RLS.
--    Returns true for lifetime, active (not expired), or active trial.
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_user_subscribed(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_status    text;
  v_expires   timestamptz;
  v_trial_at  timestamptz;
BEGIN
  SELECT subscription_status, subscription_expires_at, trial_started_at
    INTO v_status, v_expires, v_trial_at
    FROM public.users
    WHERE id = p_user_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  RETURN (
    v_status = 'lifetime'
    OR (v_status = 'active'  AND v_expires  IS NOT NULL AND v_expires  > now())
    OR (v_status = 'trial'   AND v_trial_at IS NOT NULL AND v_trial_at + interval '7 days' > now())
  );
END;
$$;

-- Anon callers cannot invoke the function; authenticated users can
REVOKE EXECUTE ON FUNCTION public.is_user_subscribed(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.is_user_subscribed(uuid) TO authenticated;
