-- Reconstructed from supabase_migrations.schema_migrations (remote archive pass, 2026-06-30)
-- Formatting/comments from the original submission are not preserved; statements only.


-- KB Nodes
create table if not exists kb_nodes (
  id text primary key,
  label text not null,
  type text not null,
  color text default '#94a3b8',
  size float default 0.3,
  description text,
  tags text[] default '{}',
  pos_x float default 0,
  pos_y float default 0,
  pos_z float default 0,
  metadata jsonb default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- KB Edges
create table if not exists kb_edges (
  id uuid primary key default gen_random_uuid(),
  source_id text not null references kb_nodes(id) on delete cascade,
  target_id text not null references kb_nodes(id) on delete cascade,
  label text,
  weight float default 1.0,
  created_at timestamptz default now(),
  unique(source_id, target_id)
);

-- Lock both tables — anon key gets nothing
alter table kb_nodes enable row level security;
alter table kb_edges enable row level security;

-- No public policies = full block on anon key
-- Service role (used by edge function) bypasses RLS automatically

-- Updated_at trigger
create or replace function kb_update_timestamp()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists kb_nodes_updated_at on kb_nodes;
create trigger kb_nodes_updated_at
  before update on kb_nodes
  for each row execute function kb_update_timestamp();
