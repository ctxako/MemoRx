# MemoRx Daily Marketing Capture Pipeline

**Status:** Revised for final approval (Phase 1 — in-app capture mode)  
**Owner:** MemoRx  
**Purpose:** Produce one silent, vertical MemoRx screen-recording each day from the authoritative Supabase daily challenge. The resulting MP4 is handed off for manual editing and posting.

## 1. Goal

Create a roughly 33-second, vertical MP4 that shows:

1. The day's MemoRx drug-card front.
2. Its back/clinical detail (opacity/blur crossfade transition, not a 3D flip).
3. The full **8-question** daily quiz sequence (7 drug questions + 1 bonus class question) with answer/reveal states.
4. The real QuizView results screen showing a score of **~71–75%**.

The video is silent and deliberately neutral: no captions, subtitles, music, voiceover, TikTok API, or promotional overlays are part of this system.

> The capture answers **6/8 correct (75%)** for an eight-question quiz, or **5/7 correct (71%)** when no bonus class question is generated. Both produce a "strong but not perfect" result.

## 2. Product contract

### Inputs

- `get_current_challenge` Supabase RPC: authoritative daily assignment (`challenge_date`, `drug_id`, title/difficulty/XP metadata when supplied). Called **sessionless** in capture mode (see §4.2).
- Supabase `drugs` catalog: complete content for the assigned `drug_id`. Sessionless read.
- Class quiz guides: needed for the bonus class-level question. Sessionless read of the base `class_quizzes` table (see §4.2 for why the view names the normal path uses are not anon-readable).
- A local capture configuration: timing values (configurable, not hard-coded).

### Outputs (Phase 1)

- A capture flow visible in the Simulator, triggered by the `-marketingCapture` launch argument.
- One local JSON manifest for retry/debugging, containing Codable question snapshots, the scripted answer plan, and run timestamps.
- An accessibility completion marker for future UI-test automation.

> Phase 2 (future): Mac automation runner, MP4 recording, LaunchAgent scheduler, output folder management. Also deferred: TikTok/social posting, captions, audio, overlays, and post-production.

### Safety boundaries — no user-scoped Supabase writes

**Core requirement:** Phase 1 capture mode makes **no user-scoped Supabase writes of any kind.** Concretely, a capture run must not:

- create an anonymous auth user (`signInAnonymously` / `ensureAnonymousSession`) — this matters because the `handle_new_auth_user` trigger auto-creates a `public.users` row on every auth signup, so even a "throwaway" anonymous session is a user-scoped write;
- create or modify any `public.users` row or profile;
- sync subscriptions (`SubscriptionManager.configureOnLaunch()` and everything downstream);
- sync onboarding state or flush the progress sync queue (`UserProgressService` background work);
- call `UserProgressService.finalizeQuizSession` (which internally invokes `submit_daily_completion`);
- change XP, streak, flags, quiz history, or write `quiz_attempts` rows;
- alter user settings or onboarding state;
- use the `UserProgressService.todaysDrugIndex()` fallback if the server assignment is unavailable.

**Accepted server-maintenance side effect:** `get_current_challenge` internally runs `fill_challenge_buffer(7)` (global next-day assignment auto-fill, per `20260514030523_rebuild_cycle_system_option_a.sql`). This is a global, non-user-scoped scheduling write that happens identically for every caller. Capture mode accepts it; it does not violate the "no user-scoped writes" rule.

These guarantees are enforced in code by the capture-runtime boundary (§4.1), **not** by running against a clean Simulator. A dirty Simulator with a pending sync queue must still produce zero user-scoped writes.

If the server assignment or its catalog drug cannot be loaded, the run fails cleanly and emits no "wrong drug" video.

## 3. Proposed user-visible sequence

| Segment | Target duration | Content |
| --- | ---: | --- |
| Card front | 2.4 sec | Current daily drug's card front (opacity crossfade in) |
| Card flip | 0.5 sec | Opacity/blur/scale crossfade (0.22s fade-out + 0.26s fade-in) |
| Card back | 3.5 sec | Clinical/back-card content (scrolled if needed) |
| Quiz 1–8 | ~20 sec | Prompt, automated answer, and visible answer reveal; seven-question runs (no bonus) are ~2.5 sec shorter |
| Results reveal | 4.5 sec | Real QuizView results screen with score ring, XP badge, and animations |
| Final hold | 2.0 sec | Clean ending frame for later editing |
| **Total** | **~32.9 sec (8 questions)** | A seven-question run (no bonus) is approximately 30.4 seconds |

All values will be stored in one `MarketingCaptureTiming` configuration so they can be tuned without altering app behavior. The first implementation will favor consistency over attempts to simulate human tap timing.

## 4. Architecture

### 4.1 Capture-runtime boundary

A single runtime flag — `MarketingCaptureRuntime.isActive`, resolved once from `ProcessInfo.processInfo.arguments.contains("-marketingCapture")` and gated with `#if DEBUG` — drives every capture-mode behavior change. All suppression below checks this flag; none of it relies on Simulator state.

**`MemoRxApp.init()`** (capture mode):
- **Retain** Sentry startup, unchanged.
- **Skip** `NotificationManager.shared.refreshDailyReminderIfAuthorized()`.
- **Skip** `SubscriptionManager.shared.configureOnLaunch()` (no subscription sync, no StoreKit/Supabase subscription writes).

**Root view routing:** when the flag is set, the app body renders `MarketingCaptureRootView` and **never instantiates `ContentView`** — bypassing all of its auth/anonymous-session, onboarding, paywall, progress-refresh, and subscription work.

**`UserProgressService` suppression:** `UserProgressService` is a singleton whose *initializer* schedules background work — a delayed pending-sync queue flush (which calls `ensureAnonymousSession()` then `flushPendingSyncQueue`) and a delayed `pushOnboardingCompletedWithRetry()` when `onboardingCompletedNeedsSync` is set. Bypassing ContentView is therefore not sufficient: any incidental first touch of `UserProgressService.shared` would fire these. `UserProgressService` will check `MarketingCaptureRuntime.isActive` and suppress **all** of its background remote sync, queue-flush, and onboarding-sync work when capture runtime is active. Locally queued events remain on disk untouched for the next normal launch.

The capture root only needs:
- a sessionless drugs-catalog load (§4.2),
- a sessionless `get_current_challenge` call + catalog validation (§4.2),
- a sessionless class-quiz-guide load for the bonus question (§4.2).

It does **not** need auth, onboarding, paywall, subscription, or user progress services.

### 4.2 Sessionless Supabase content reads (capture-only)

The normal read paths are unusable as-is in capture mode: `SupabaseManager.fetchRemoteDrugs()`, `SupabaseManager.fetchRemoteClassQuizGuides()`, and `DailyChallengeService.refreshFromServer()` all call `ensureAnonymousSession()` first, which signs in anonymously and (via the `handle_new_auth_user` trigger) creates a `public.users` row. Throwaway anonymous users are **not** an acceptable fallback.

Capture mode adds **sessionless variants** that use the configured Supabase anon key with no auth session — no `ensureAnonymousSession()`, no `signInAnonymously()` — so every request executes as the `anon` role. The three reads, verified against the existing migrations:

| Read | Capture path | Anon permission (verified) |
| --- | --- | --- |
| `get_current_challenge` | `rpc("get_current_challenge")`, sessionless | `SECURITY DEFINER`; EXECUTE deliberately left with `anon` — `20260527_lock_admin_rpcs.sql` names it among the user-facing RPCs that "stay executable." Its internal `fill_challenge_buffer(7)` auto-fill is the accepted global side effect (§2). |
| Drugs catalog | `from("drugs").select()`, sessionless | `GRANT SELECT ON public.drugs TO anon` (`20260604001602_tighten_table_grants…`) + RLS policy `"Public read drugs" … FOR SELECT USING (true)` (`20260420200307`), which applies to all roles. |
| Class quiz guides | `from("class_quizzes").select()`, sessionless — **base table, not the views** | The normal path reads the compatibility views `class_quiz_guides` / `class_quiz_content`, which are granted to `authenticated` only (`20260420211901`) and are therefore **not anon-readable**. The base table `class_quizzes` is: `GRANT SELECT … TO anon` (`20260604001602`) + policy `class_quizzes_read_anon` (`20260514023357`). The capture-only fetch targets `class_quizzes` directly and decodes into the same `ClassQuizGuide` model. |

With this base-table routing, **all three reads are anon-permitted today** — no migration, RLS change, or grant change is required. (If for any reason the base-table read were rejected during implementation, that is a **blocker** to raise — the resolution would be a one-line `GRANT SELECT ON public.class_quiz_guides TO anon`, not a throwaway anonymous user.)

Implementation shape: `SupabaseManager` gains capture-only static methods (e.g. `fetchRemoteDrugsSessionless()`, `fetchRemoteClassQuizGuidesSessionless()`, `fetchCurrentChallengeSessionless()`) that share the existing client/decoding but omit the session step; `DrugService`, `DailyChallengeService`, and the guide load route through them only when `MarketingCaptureRuntime.isActive`. Normal-mode paths are untouched.

### 4.3 Coordinator

`MarketingCaptureCoordinator` will be `@MainActor` and own a small state machine:

```text
loading -> front -> back -> quiz(question index, reveal state) -> results -> finished
                       \-> failed(reason)
```

It waits for the sessionless drug-catalog and challenge loads, then uses `DailyChallengeService.resolvedHighlightDrug(in:)` only after a successful server response.

### 4.4 Rendering approach — driving the real views

The capture view will **drive the actual production views** (`DrugCardView` and `QuizView`) rather than building lightweight replicas. This ensures pixel-perfect fidelity on camera. Both views self-drive their own existing private state; the capture layer only feeds them declarative inputs.

**`DrugCardView`:** the flip is internal `@State isFlipped` with an opacity/blur/scale crossfade. `DrugCardView` gains a capture-only **auto-flip input** (e.g. an optional `captureAutoFlipDelay` or equivalent trigger binding) that fires its existing internal flip transition after the configured front-hold. No change to normal (tap-driven) behavior.

**`QuizView`:** gains a capture-only **script input** — an optional `MarketingCaptureScript` value containing:
- the immutable, pre-generated question snapshots (from the manifest, §4.5),
- the scripted correct/wrong answer per question,
- per-step timings (from `MarketingCaptureTiming`).

When a script is present, `QuizView` self-drives its own existing private state and animations: a capture timer selects the scripted option, then triggers the same submit and advance behavior the buttons use, through every question to the real `resultsView`. To make that possible without duplicating logic, **the existing inline "Submit Answer" and "Next Question → / See Results" button closures will be factored into private shared helpers (e.g. `submitCurrentAnswer()` and `advanceToNextQuestion()`), called by both the buttons and the capture timer.** The buttons keep identical behavior in normal mode.

In capture mode, `QuizView` additionally:
- **skips `finalizeQuizSession`** — the results screen renders fully (score ring, XP badge, animations) but the "Done" finalization path is never invoked;
- **hides or disables all mutation-capable actions** on the results screen (Done/finalize, retry, and anything else that could write) for the duration of capture;
- **emits the completion accessibility marker** (§4.6) when the results reveal completes.

Question sourcing in capture mode comes exclusively from the script — `QuizView`'s own `loadQuestions()` generation is bypassed so the run exactly matches the persisted manifest.

### 4.5 Questions, manifest, and score

Capture-script generation mirrors `QuizView`'s real daily flow so the captured quiz is indistinguishable from a genuine one:

1. `QuizEngine.generateQuestions(for:allDrugs:)` produces the normal **seven** drug questions.
2. `ClassQuizEngine.generateBonusQuestion(for:guides:)` is attempted for the eighth, bonus class question.
3. If no bonus can be generated, mirror `QuizView.loadQuestions()`'s **replacement-drug-question fallback**: generate additional unique drug questions (signature-deduplicated, bounded attempts) toward the eight-question target.
4. Use the **actual final count** — typically 8, possibly 7, conceivably fewer if generation stalls. **If the final count is below four questions, the run fails visibly** (`failed:` state + on-screen reason); no video is produced from a degenerate quiz.

**Manifest:** the first run for a date/drug writes a `MarketingCaptureManifest` containing a **Codable question snapshot type** — a purpose-built mirror of each question's prompt, options, correct answers, and type — **not `QuizQuestion` directly**, so manifest persistence is decoupled from the engine model and retries stay deterministic across code changes. The manifest also stores the scripted answer plan and run timestamps. A retry reloads the manifest, reconstructs the identical script, and produces the same quiz and result. The manifest is local only and contains no credentials or learner data.

**Score plan — strong but not perfect, wrong answers distributed:** the approved score intent stands (6/8 = 75%, or 5/7 = 71%). Incorrect answers are placed **deterministically across the quiz**, not clustered at the end:

```text
8 questions: incorrect at questions 3 and 6 → 6/8 (75%)
7 questions: incorrect at questions 3 and 6 → 5/7 (71%)
4–6 questions (degraded fallback): incorrect at question 3 only
```

The positions are a fixed rule stored in the manifest with the answer plan, so retries reproduce them exactly.

### 4.6 Completion and failure signaling

The capture screen will expose an accessibility identifier `marketingCaptureStatus` with the terminal value `finished` or `failed:<reason>`. Phase 2's UI-test driver will wait for this marker.

Failures should also appear on the simulator screen (useful for manual runs during Phase 1).

## 5. Mac automation (Phase 2 — future)

Deferred. Phase 1 is triggered manually via Xcode's scheme editor or `xcrun simctl launch` with the `-marketingCapture` argument. Phase 2 will add:

- A Python-based Mac capture runner (boots Simulator, starts recording, launches app, waits for marker, stops recording).
- A macOS LaunchAgent template for scheduled daily runs.
- MP4 output management with date/drug filenames and no-clobber behavior.
- Scheduling, TikTok/social posting, captions, audio, overlays, and all post-production remain Phase 2+ (or out of scope entirely per §9).

## 6. Files expected to change (Phase 1)

| Area | Planned responsibility |
| --- | --- |
| `MemoRx/MemoRxApp.swift` | Resolve `MarketingCaptureRuntime.isActive` from `-marketingCapture` (`#if DEBUG`); keep Sentry startup; skip `NotificationManager.refreshDailyReminderIfAuthorized()` and `SubscriptionManager.configureOnLaunch()`; route to `MarketingCaptureRootView` instead of `ContentView`. |
| `MemoRx/ContentView.swift` | No change — capture mode never instantiates it. |
| `MemoRx/UserProgressService.swift` | Suppress init-time and background remote sync, pending-sync queue flush, and onboarding-sync retry when capture runtime is active. |
| `MemoRx/Services/SupabaseManager.swift` | Add sessionless capture-only reads: `get_current_challenge` RPC, `drugs` select, `class_quizzes` (base table) select — no `ensureAnonymousSession()`/`signInAnonymously()`. |
| `MemoRx/Services/DrugService.swift` | Route catalog load through the sessionless read when capture runtime is active. |
| `MemoRx/DailyChallengeService.swift` | Route `refreshFromServer()` through the sessionless RPC when capture runtime is active; `resolvedHighlightDrug(in:)` reused as-is. |
| `MemoRx/ClassQuizModels.swift` (`ClassQuizGuideService`) | Route guide load through the sessionless base-table read when capture runtime is active. |
| `MemoRx/QuizView.swift` | Capture script input; factor inline submit/advance button logic into private shared helpers used by buttons and capture timer; skip `finalizeQuizSession`; hide/disable mutation-capable actions during capture; emit completion marker; bypass internal question generation when scripted. |
| `MemoRx/DrugCardView.swift` | Capture-only auto-flip input triggering the existing internal crossfade transition. |
| New `MemoRx/MarketingCapture/` files | `MarketingCaptureRuntime.swift`, `MarketingCaptureCoordinator.swift`, `MarketingCaptureRootView.swift`, `MarketingCaptureTiming.swift`, `MarketingCaptureManifest.swift` (incl. the Codable question snapshot and `MarketingCaptureScript`). |
| `docs/` | This plan (updated). |

No Supabase migration, RLS policy, grant, Edge Function, Storage bucket, or API-key change is planned — all three capture reads are anon-permitted under existing migrations (§4.2).

## 7. Verification plan

### In-app (Phase 1) — acceptance criteria

Content and flow:

- Normal MemoRx launch still loads the existing Today experience unchanged (no capture flag → zero behavior change, including `UserProgressService` sync and both skipped launch calls).
- Capture mode uses the exact remote assignment returned by `get_current_challenge`.
- Missing assignment, stale catalog, network error, or a generated quiz below four questions produces a visible failure state and no capture.
- A second capture for the same date/drug reuses the exact manifest (identical questions, answers, and score).
- The results screen shows 6/8 (75%) or 5/7 (71%) with incorrect answers at the scripted mid-quiz positions, matching the real QuizView's visual design.
- The quiz includes the bonus class question when one is generated, and the replacement-drug-question fallback when not.
- Sentry remains initialized in capture mode.

No-user-scoped-writes verification (explicit, per call class — verified by instrumentation/breakpoint or network inspection during a capture run on a **dirty** simulator with a pending sync queue and `onboardingCompletedNeedsSync` set):

- **No anonymous sign-in call**: `signInAnonymously()` / `ensureAnonymousSession()` never invoked; no `auth/v1` signup request leaves the app.
- **No user/profile creation**: no `public.users` row is created (count unchanged before/after the run).
- **No subscription sync**: `SubscriptionManager.configureOnLaunch()` and downstream subscription writes never run.
- **No progress/onboarding queue flush**: `flushPendingSyncQueue` and `pushOnboardingCompletedWithRetry` never run; locally queued events are still on disk after the run.
- **No daily-completion call**: `finalizeQuizSession` / `submit_daily_completion` never invoked; no XP, streak, or quiz-history change.
- **No `quiz_attempts` writes.**
- The only Supabase traffic in a capture run is the three anon-role reads (and `get_current_challenge`'s accepted internal buffer auto-fill).

### Regression

- Existing unit and UI tests pass.
- A manual normal-quiz pass confirms learner XP/streak behavior and the submit/advance buttons (now backed by the shared helpers) remain unchanged.
- The `-marketingCapture` argument has no effect on release builds (`#if DEBUG` gate).

## 8. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| A user-scoped write slips through (sign-in, users row, sync, finalization) | Single `MarketingCaptureRuntime.isActive` boundary checked at every suppression point; dirty-simulator verification run in §7 is the acceptance gate, not a clean Simulator. |
| `UserProgressService` init-time tasks fire on incidental singleton access | Suppression lives inside `UserProgressService` itself, not in callers. |
| Base-table `class_quizzes` read fails despite verified grants | Treat as a blocker; resolution is a one-line anon grant on the view — never a throwaway anonymous user. |
| QuizView internal state is fragile to external driving | Script drives the same shared helpers the buttons use; if driving proves too coupled, fall back to a standalone capture results view (increases scope but improves isolation). |
| Drug content is too long for the capture frame | Use bounded text/layout rules and validate with several long-name drugs. |
| Random quiz generation changes a retry | Codable snapshot manifest per date/drug; script reconstructed from the manifest, never regenerated. |
| Daily assignment not yet rolled over | Validate returned `challenge_date`; fail visibly if stale. |
| Capture mode accessible in production | Gate the launch argument check with `#if DEBUG`. |

## 9. Explicit non-goals for Phase 1

- Mac automation, MP4 recording, LaunchAgent scheduling (Phase 2).
- Posting or uploading to TikTok or any social network.
- AI-generated captions, scripts, hashtags, voice, music, or visual overlays.
- Automated video editing, trimming, or background replacement.
- Recording a physical iPhone/iPad.
- Changing MemoRx's normal daily challenge selection, quiz scoring, or Supabase schema.
- Sending notifications or messages when a capture succeeds/fails.

## 10. Decisions made

1. **Quiz length:** Full 8 questions (7 drug + 1 bonus class question when available; replacement drug questions when not; actual final count used, hard floor of 4).
2. **Score rule:** Strong but not perfect — 6/8 (75%) or 5/7 (71%), with incorrect answers distributed deterministically mid-quiz (questions 3 and 6), not clustered at the end.
3. **Results UI:** Drive the real `QuizView` (script input + self-driven internal state); skip finalization; hide mutation-capable actions during capture.
4. **Supabase access:** Sessionless anon-key reads only; no anonymous auth user, ever — verified anon-permitted for all three reads under existing migrations, with the class-guide read targeting the `class_quizzes` base table.
5. **Scope:** In-app capture mode first (Phase 1). Mac automation, scheduling, TikTok, captions, audio, overlays, and post-production are Phase 2 or out of scope.
6. **Safety:** `#if DEBUG` gating; capture-runtime boundary enforced in code (`MemoRxApp`, `UserProgressService`, sessionless reads), not by Simulator hygiene; `get_current_challenge`'s global buffer auto-fill is the sole accepted server side effect.
