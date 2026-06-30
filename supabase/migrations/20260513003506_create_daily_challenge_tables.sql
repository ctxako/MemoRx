-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- Helper function (needed by lock trigger below)
CREATE OR REPLACE FUNCTION current_challenge_date()
RETURNS date LANGUAGE sql STABLE AS $$
  SELECT (NOW() AT TIME ZONE 'America/New_York' - INTERVAL '4 hours')::date;
$$;

-- Daily challenge schedule (one row per day)
CREATE TABLE daily_challenges (
  challenge_date  date      PRIMARY KEY,
  drug_id         text      NOT NULL REFERENCES drugs(id),
  title           text,
  difficulty      text,
  notes           text,
  xp_base         integer   NOT NULL DEFAULT 50,
  created_at      timestamp NOT NULL DEFAULT now(),
  updated_at      timestamp NOT NULL DEFAULT now()
);

-- One completion per user per day
CREATE TABLE daily_completions (
  id              uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         text      NOT NULL REFERENCES users(id),
  challenge_date  date      NOT NULL REFERENCES daily_challenges(challenge_date),
  completed_at    timestamp NOT NULL DEFAULT now(),
  xp_awarded      integer   NOT NULL DEFAULT 0,
  correct_count   integer   NOT NULL,
  total_questions integer   NOT NULL,
  UNIQUE (user_id, challenge_date)
);

-- Admin XP adjustment audit trail
CREATE TABLE admin_audit_log (
  id           uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id     text      NOT NULL,
  action       text      NOT NULL,
  entity_type  text      NOT NULL,
  entity_id    text      NOT NULL,
  reason       text,
  ticket_id    text,
  before_data  jsonb,
  after_data   jsonb,
  created_at   timestamp NOT NULL DEFAULT now()
);

-- Key/value store for app state (e.g. weekly reset tracking)
CREATE TABLE app_settings (
  key   text  PRIMARY KEY,
  value jsonb NOT NULL
);

INSERT INTO app_settings (key, value)
VALUES ('weekly_reset_last', '"1970-01-01"')
ON CONFLICT DO NOTHING;

-- Prevent editing past/current challenges
CREATE OR REPLACE FUNCTION check_challenge_locked()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.challenge_date <= current_challenge_date() THEN
    RAISE EXCEPTION 'daily_challenge_locked';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER daily_challenges_lock_check
  BEFORE UPDATE ON daily_challenges
  FOR EACH ROW EXECUTE FUNCTION check_challenge_locked();
