# Claude review of Issue #3

Claude Code reviewed the final working-tree implementation against baseline `3325115835ad5f4557f9f4ab583ea0773d27b0cd`, independently along the Standards and Spec axes. Reviews used read-only tools and no MCP servers. The model reported by Claude Code was `claude-opus-5-5`.

| Round | Standards | Spec |
| --- | --- | --- |
| 1 | No medium-or-higher findings | High 1, medium 1: unseated focus adoption and another owner's journal overwrite |
| 2 | No medium-or-higher findings | Medium 2: clock rollback preventing finalization and missing recovery on owner change |
| 3 | No medium-or-higher findings; low 4 | No medium-or-higher findings; low 4 |

Every high/medium finding was reproduced with a failing regression test before correction. The final non-golden suite passes all 200 tests. See [device validation](issue-3.md) for the dev checks. The final reports below are retained separately, with only heading depth adjusted for this document.

## Standards

621, here is the standards-axis report for round 3. I found no medium-or-higher issues. There are four low maintainability findings; none of them blocks the merge.

**Sources checked:** `analysis_options.yaml` (only `flutter_lints` and two `prefer_const` rules, which tooling already enforces), `pubspec.yaml` (`uuid`, `intl` and `sqflite` were already dependencies, so nothing was added), README, and the surrounding code's conventions. No written coding standard is broken.

**L1 — low, heuristic (Duplicated Code / Primitive Obsession)**
- **Where:** `lib/providers/session_provider.dart:48-51`, `lib/screens/study_history_screen.dart:31-37` and `:98-103`.
- **What:** The rule that turns a user ID into an owner ID (`guest:device` or `user:<uid>`) is written out three times.
- **Trigger:** Someone later changes the owner format (say, a provider prefix for #4–#7) and updates only `historyOwnerId`.
- **Impact:** Records are still written, but the history screen queries a different owner and quietly shows zero.
- **Fix:** Add one shared function, such as `StudySession.ownerFor(String? uid)`, and call it from all three places.

**L2 — low, departs from existing convention**
- **Where:** `session_provider.dart:159, 279, 347, 399, 652`; `room_detail_screen.dart:140-141`.
- **What:** The error keys `'historySaveFailed'` and `'historyOtherOwnerActive'` are bare string literals. The existing code uses named constants for this (`NetworkErrorKey` in `network_exception.dart:20`).
- **Impact:** A typo on either side would show the raw key to the user instead of a localized message, and no compile-time check would catch it.
- **Fix:** Put both keys in a `HistoryErrorKey` constants class and use it at every site.

**L3 — low, heuristic (Speculative Generality / stale API)**
- **Where:** `session_provider.dart:578-586`.
- **What:** `restoreFromSeatData` still requires `roomId`, `seats`, `userId` and `roomName`, and its doc comment still describes searching the seat map. It now ignores all four and just calls `restoreSessionIfNeeded()`. I am not reopening the decision not to restore seats that exist only on the server; this is only about the interface.
- **Impact:** Callers like `room_detail_screen.dart:97-105` still gather seat data for nothing, and readers of the doc will expect behaviour that no longer exists.
- **Fix:** Have the screen call `restoreSessionIfNeeded()` directly and delete the old method, or at least fix its doc comment.

**L4 — low, heuristic (Duplicated Code)**
- **Where:** `room_detail_screen.dart:110-121` and `room_list_screen.dart:54-58`.
- **What:** `_restoreLocalSession` now restores or starts the timer before it reports the seat as restored. Both screens then repeat that sequence (`restoreState`, `setInitialDuration`, `start`).
- **Impact:** It looks harmless today: the restore waits for pending writes first, and the `isFinalizing` checks keep the timer from restarting during finalization. But the timer-binding rules now live in three places, which is exactly how the round-1 H1 problem came about.
- **Fix:** Rely on the provider to bind the timer and drop the screen-side fallback, or move it into one shared helper.

**Things that check out:**
- `StudyPersistenceKeys` gets rid of the duplicated literal keys across the two providers.
- The timer persistence error is now private.
- The owner-aware guard and the clock-shift field have clear names and comments.
- Dependency injection (`now`, `historyRepository`, `withDatabase`) follows the constructor-injection pattern the existing code uses.
- The localized strings fill both `.arb` files.

**Optional only:** the public static name `StudyHistoryRepository.date` doesn't say what it does; something like `civilDateKey` would. Separately, `study_history_screen.dart:94-104` calls `_loadData()` from inside a `setState` callback. That works, but it is untidy.

**Medium-or-higher findings: 0**

## Spec

621, here is the round-3 spec review. I read the patch and the current source. Both round-3 fixes hold, the round-2 fixes still hold, and I found nothing at medium or above.

### Fix verification

- **M-A, clock rollback (fixed).** `timer_provider.dart:250-263`: each new interval now starts at or after the previous interval's end. The open interval's end is never earlier than its start (`:48`), and the Pomodoro deadline is measured from the same adjusted start. So "Overlapping focus intervals" (`study_session.dart:63-67`) can no longer block leave. When the clock hasn't moved backward, the adjustment is zero.
- **M-B, returning to the guest owner (fixed).** `session_provider.dart:100-104` and `:589-593`: auth changes trigger recovery, all callers share one in-flight attempt, and the timer is restored before the seat shows as seated (`:639-647`). Guests can recover from a room (`room_detail_screen.dart:95`).
- **H1 / M1 (still fixed).** Starting a new session resets the timer (`timer_provider.dart:238-246`). The write queue checks which session is active before every write or removal (`:573-587`), so a stale queued removal can't wipe the active journal.
- **Other spec checks pass:**
  - SQLite replace on `(owner_id, session_id)` prevents double counting.
  - Pending records ignore `updateDuration` (`:313`).
  - Cleanup removes `study_active_v2` last.
  - v1 migration is additive and keeps old totals on their start day.
  - Every query takes an owner, and each one fills unstudied days with 0.
  - Day splitting keeps daily sums equal to the total, and weeks start on Monday.
- **Legacy bucketing is not a regression.** The old code used `DateTime(start.year, month, day)` on the parsed value. That gives the same calendar day as the new `DateTime.utc(...)` label (diff 1636-1640).

### Findings (all low, none block merge)

**L1 — Possible regression: the app may not return to the room after a restart** (`room_list_screen.dart:50-51` with `session_provider.dart:100-104`)
- "プロセス終了後の復元と確定処理を整合させる" (keep restore after process death consistent with finalization).
- **Trigger:** after a kill -9, the first Firebase auth event starts recovery while the room list is still waiting on `fetchRooms()`. If recovery finishes first, the room list's own `restoreSessionIfNeeded()` returns false (`_sessionId != null`), so it never navigates into the room.
- **Impact:** the user lands on the room list while still seated, with the timer running. No data is lost, and opening the room shows the seat and allows leave. The earlier kill -9 device check probably ran before this listener existed, so it doesn't cover this.
- **Fix:** navigate when `restored || sessionProvider.isSeated`, then confirm on device.

**L2 — Raw error keys in the sit-failure snackbar** (`room_detail_screen.dart:470`)
- "日本語と英語の表示に対応" (support Japanese and English display).
- **Trigger:** sitting down while another owner's session exists, or after a storage failure.
- **Impact:** the snackbar shows "Failed to sit: historyOtherOwnerActive" next to the correctly localized message from `_onErrorChanged`.
- **Fix:** skip the generic snackbar for known keys.

**L3 — Corrupt saved data can leave the user stuck** (`session_provider.dart:624-636`)
- **Trigger:** a malformed `startedAt` or `pending` value makes recovery throw after `_sessionId` is already set.
- **Impact:** the state is idle but `_sessionId` is set, so `sit()` silently returns false until the app is restarted, and a restart repeats the same failure. This needs corrupted storage, so it's unlikely.
- **Fix:** parse into local variables first and assign only once everything succeeds.

**L4 — Misleading blocked-sit message** (`session_provider.dart:157-161`)
- **Trigger:** the current owner's own active record exists but hasn't been restored yet, or its restore failed.
- **Impact:** `sit()` reports "another owner active" even though the record is the user's own.
- **Fix:** compare `ownerId` before choosing the message.

`sit()` failing after the seat is taken (`:278-282`) only happens on a SharedPreferences write failure. `startStudySession` already handles denied notification permission and wraps the service start in try/catch.

### Optional (maintainability)
- `sit()` repeats the seated-state setup in the normal path and the 401 retry path. Pulling it into a helper would keep the two in sync.

**Findings at medium or above: 0.**

Final totals: Standards — high 0, medium 0, low 4. Spec — high 0, medium 0, low 4.
