-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Phase 2 (additive): add normalized taxonomy link + per-drug label, backfill from existing data.
-- Flat columns (collection, sub_collection, drug_class) are intentionally left UNCHANGED
-- so the shipped app sees no difference. FK + NOT NULL are added in a later step after QC.
alter table public.drugs
  add column if not exists drug_class_id text,
  add column if not exists class_label   text;

update public.drugs set
  drug_class_id = case sub_collection
      when 'antiepileptics'                          then 'anticonvulsants'
      when 'muscleRelaxants'                         then 'skeletalMuscleRelaxants'
      when 'dihydropyridineCalciumChannelBlockers'   then 'calciumChannelBlockers'
      when '5AlphaReductaseInhibitors'               then 'alphaReductaseInhibitors'
      else sub_collection
    end,
  class_label = drug_class;
