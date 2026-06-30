-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- drug_classes table
CREATE TABLE IF NOT EXISTS drug_classes (
  sub_collection TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  suffixes TEXT[] DEFAULT '{}',
  class_uses TEXT[] DEFAULT '{}',
  hallmark_side_effects TEXT[] DEFAULT '{}',
  high_yield_pearls TEXT[] DEFAULT '{}',
  high_risk_meds TEXT[] DEFAULT '{}'
);

-- drugs table
CREATE TABLE IF NOT EXISTS drugs (
  id TEXT PRIMARY KEY,
  generic_name TEXT NOT NULL,
  brand_names TEXT[] DEFAULT '{}',
  collection TEXT,
  sub_collection TEXT,
  drug_class TEXT,
  mechanism_of_action TEXT,
  indications TEXT[] DEFAULT '{}',
  dosage JSONB,
  side_effects TEXT[] DEFAULT '{}',
  warnings TEXT[] DEFAULT '{}',
  contraindications TEXT[] DEFAULT '{}',
  interactions TEXT[] DEFAULT '{}',
  monitoring TEXT[] DEFAULT '{}',
  counseling_points TEXT[] DEFAULT '{}',
  pearls TEXT[] DEFAULT '{}'
);

-- Enable RLS
ALTER TABLE drug_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE drugs ENABLE ROW LEVEL SECURITY;

-- Public read-only policies
CREATE POLICY "Public read drug_classes" ON drug_classes FOR SELECT USING (true);
CREATE POLICY "Public read drugs" ON drugs FOR SELECT USING (true);
