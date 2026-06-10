# Weekly Results — SwiftUI Client Spec

Backend is shipped. This spec is what Claude Code needs to build on the iOS side.

## What the backend gives you

**Supabase table: `public.weekly_results`**

| column           | type          | notes                                 |
|------------------|---------------|---------------------------------------|
| user_id          | uuid          | FK to `public.users.id` = `auth.uid()`|
| week_start_date  | date          | The Monday that began the archived week |
| rank             | int           | Standard competition rank (`RANK()`); ties share, next jumps |
| xp               | int           | weekly_xp at time of snapshot         |
| created_at       | timestamptz   | snapshot insertion time               |

PK is `(user_id, week_start_date)`. RLS allows the authenticated user to SELECT only their own rows.

**When snapshots get written:** Every Monday at ~4am ET, the cron `archive-and-reset-weekly-xp` runs `public.archive_and_reset_weekly_xp()`. It inserts one row per user with `weekly_xp >= 1` (excluding "signed out" users), zeros `weekly_xp`, and bumps `app_settings.weekly_reset_last`. Function is idempotent — fires multiple times per Monday morning, but only the first valid tick does work.

**Backfill:** None. Week 1 is the first Monday after launch. Earlier users get no historical rows.

## What to build

### 1. Fetch query

When the stats card view loads:

```swift
try await supabase
  .from("weekly_results")
  .select("week_start_date, rank, xp")
  .order("week_start_date", ascending: false)
```

No local caching for v1. Payload is tiny.

### 2. `lastSeenWeekStartDate` in UserDefaults

Key: `"lastSeenWeekStartDate"` (Date or ISO date string).

**On signup (new user, first launch):** Set it to the current week's Monday (computed client-side from today). This ensures new users don't see a moment for a week they didn't play.

**On every app foreground (and on app launch):**

1. Query the user's most recent `weekly_results` row:
   ```sql
   SELECT week_start_date, rank, xp
   FROM weekly_results
   WHERE user_id = auth.uid()
   ORDER BY week_start_date DESC
   LIMIT 1
   ```
2. If row exists AND `week_start_date > lastSeenWeekStartDate` → trigger the moment.
3. After the user dismisses the moment, update `lastSeenWeekStartDate = week_start_date` of the row that was shown.

Edge cases handled by this logic:
- **No row last week (didn't play):** Query returns nothing → no moment. ✓
- **Missed multiple weeks:** We only fetch the most recent row → only one moment shown. ✓
- **Already dismissed today:** `week_start_date <= lastSeenWeekStartDate` → no moment. ✓
- **Cross-device sync:** Not handled. UserDefaults only. Worst case user sees moment twice across devices — fine for v1.

### 3. The Acknowledgement Moment UI

Full-screen modal or large banner. Not a toast.

**Rank-aware copy + visual:**

| Rank tier            | Visual | Headline copy                                    |
|----------------------|--------|--------------------------------------------------|
| 1                    | 🥇     | "You finished #1 last week"                      |
| 2                    | 🥈     | "You finished #2 last week"                      |
| 3                    | 🥉     | "You finished #3 last week"                      |
| Top 10% (else)       | accent | "Top 10% — you finished #X of Y"                 |
| Everyone else        | neutral| "You finished #X of Y last week — added to your record" |

For "Top 10%" and "of Y" you'll need total participants for that week. Two ways:
- **Simple v1:** Skip "of Y" entirely. Just show "You finished #X last week — added to your record." Ship that, add denominator post-launch.
- **If you want denominator now:** Add a second query: `SELECT COUNT(*) FROM weekly_results WHERE week_start_date = $1`. But this requires loosening RLS (currently users only see own rows). Either add a SECURITY DEFINER function `get_weekly_participant_count(date)` or open a public read on count. **Recommend: skip for v1.**

Always include "added to your record" framing somewhere so users learn history is being kept.

**Single CTA:** "View your stats" → navigates to the stats card.

**Tiebreaker copy polish (optional, post-launch):** If you query and find `>1` row sharing the same rank for that week, say "You tied for #3" instead of "You finished #3". Add this when you have time.

### 4. Stats Card v1

Minimum viable: a list of past weeks, most recent first. Each row:

```
Week of May 18 — #3 · 142 XP
Week of May 11 — #7 · 86 XP
...
```

That's it. No streak detection, no best-rank-ever, no percentile stats. Build those post-launch when there's 4+ weeks of real data to design against.

## Ship order (your current Wed→Mon plan, updated)

- **Wed (done):** Backend table, function, cron all live.
- **Thu/Fri:** Client fetch + minimal stats card list view.
- **Sat:** Acknowledgement moment UI + `lastSeenWeekStartDate` logic.
- **Sun:** End-to-end test:
  1. Manually call `SELECT public.archive_and_reset_weekly_xp();` (this will no-op unless it's Monday — see "Test fixture" below for forcing a fire).
  2. Force-close app, reopen, confirm moment appears.
  3. Reopen again, confirm moment does NOT appear.
- **Mon:** First real cron run. Watch logs.

## Test fixture for Sunday e2e

The backend won't fire archive on Sunday because `DOW <> 1`. To test the full flow, manually insert a fake row for your test user:

```sql
INSERT INTO public.weekly_results (user_id, week_start_date, rank, xp)
VALUES ('<your-test-user-id>', current_date - 1, 1, 42);
```

Then open the app → moment should appear with "You finished #1 last week". Dismiss → reopen → no moment.

Cleanup:
```sql
DELETE FROM public.weekly_results
WHERE user_id = '<your-test-user-id>' AND week_start_date = current_date - 1;
```

## Things NOT to build for v1

- Streak detection across weekly_results
- Best-rank-ever badge
- Percentile / league assignment
- Cross-device sync for `lastSeenWeekStartDate`
- Backfill of historical weeks
- Public top-N leaderboard view of past weeks (RLS is currently own-rows-only; loosening can wait)

## What I (backend) verified before handing off

- Table + index + RLS policy + own-rows-only SELECT policy applied
- Function `archive_and_reset_weekly_xp()` created with `SECURITY DEFINER`, atomic insert → zero → bump-guard
- Cron job `archive-and-reset-weekly-xp` scheduled `*/2 8-12 * * 1` UTC (covers Monday 4am ET in both EDT and EST with idempotent retries)
- Called function on Wed — correctly no-oped (DOW guard works), no data changed
- `RANK()` tie behavior verified against synthetic data (4-way tie for 3rd → next user gets rank 7) ✓
- Test snapshot insert against current users + re-insert idempotency check (ON CONFLICT DO NOTHING) ✓, cleaned up
- Supabase security advisors show no new lints touching `weekly_results` or `archive_and_reset_weekly_xp`

Open ticket for me (backend) post-launch: when you want public top-N or percentile data, ask and I'll add a SECURITY DEFINER read function or a separate public-facing view.
