-- Drop the anon SELECT grant on leaderboard_public.
-- The iOS app always establishes an anonymous Supabase session before fetching
-- the leaderboard, so it runs as the authenticated role and is unaffected.
-- Removing the anon grant prevents unauthenticated enumeration of auth UUIDs
-- and legacy_user_ids via the public PostgREST endpoint.
revoke select on public.leaderboard_public from anon;
