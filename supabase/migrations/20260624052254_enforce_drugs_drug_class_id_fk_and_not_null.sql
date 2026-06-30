-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.

-- Phase 2 enforcement (after QC passed): integrity for the new link.
alter table public.drugs
  add constraint drugs_drug_class_id_fkey foreign key (drug_class_id) references public.drug_classes(id),
  alter column drug_class_id set not null,
  alter column class_label   set not null;
