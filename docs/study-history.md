# Local study records

Implements [#3](https://github.com/kter/study_peaks/issues/3) in the [#2 plan](https://github.com/kter/study_peaks/issues/2). There are no prerequisite issues. Issues #4–#7 should consume this repository interface instead of deriving dates from session start times.

## Identity and ownership

A completed record has a stable `session_id`, an immutable `owner_id`, its room, its start timestamp, its total focus seconds, and focus intervals. SQLite enforces uniqueness on `(owner_id, session_id)`. Saving again replaces the same record, including after a crash between insertion and recovery cleanup.

The owner is captured when sitting down. `user:<Firebase UID>` identifies signed-in users. `guest:device` identifies the guest within this installation's local database. Guest history is retained when signing in; it is never adopted by the account. Signing out reveals the same device guest history. Different accounts read separate records. An already active session retains its original owner across an authentication change. A recovered session belonging to another owner is not restored or overwritten: switch back and leave it first. Guest avatar regeneration does not change history ownership. While another owner's recovery record exists, unbound timer starts are blocked after owner-aware recovery; every timer write also checks the active session ID to protect the startup window before recovery runs. Queued writes and removals for unrelated sessions cannot replace the recoverable journal.

History is stored only on this device. There is no cloud history, transfer, account merge, analytics, or cross-device recovery. Account deletion on the server does not delete this local database: records remain under their original UID and are not reassigned to the guest or a new account. Clearing app storage or uninstalling removes local records; the existing app backup policy remains applicable. A future account-deletion feature must provide an explicit local deletion policy if removal is required.

## Focus and civil dates

`TimerProvider` records UTC start/end timestamps for actual focus intervals. Normal pauses and Pomodoro breaks contribute zero. A Pomodoro focus interval is capped at its scheduled deadline, even when the process is absent beyond the deadline. The next phase waits for an explicit start. Resetting the visible timer or switching mode preserves earlier focus within the same seated session. Leaving ends the session and clears its timer journal. Unseated focus is never adopted: binding a new seat session clears unbound or previous-session intervals and starts its timing from that seat.

Each interval captures the device's UTC offset at its start. The offset stays fixed until that interval ends, including through travel or daylight-saving changes. The next interval captures the new offset. This policy deliberately uses fixed offsets, not IANA timezone rules: an offset change during a running interval does not retroactively move its study seconds. The device clock is the time source; this is not a trusted anti-tampering clock. If the clock moves backward between intervals, the next interval is aligned to the previous end and its elapsed wall time is retained using a persisted adjustment. This prevents overlapping intervals from blocking completion. Dates after a manual clock correction follow that ordered timeline until a new seat session begins.

Daily aggregation splits each interval at midnight in its captured offset. Date keys are UTC `DateTime` labels for year/month/day, not instants to convert with `toLocal()`. Milliseconds accumulate across interval/day boundaries before flooring to seconds. A fractional second is credited to the date on which it completes, so daily sums exactly match the session total. Weeks start on Monday. No streak/learning proficiency interpretation is added.

## Shared query interface

Every query requires an explicit `ownerId`; no unfiltered history query is exposed to screens. Aggregates include completed records only, so an active session is not counted again in history.

| Method | Result |
| --- | --- |
| `getDailyTotals(ownerId, start, end)` | Daily seconds, inclusive start and exclusive end |
| `getTodayStudyTime(ownerId, now)` | Today's completed seconds |
| `getWeek(ownerId, containing)` | Monday through Sunday containing the date |
| `getMonth(ownerId, containing)` | All dates of the specified month |
| `getTotalStudyTime(ownerId)` | Lifetime completed seconds |
| `getSessions(ownerId)` | Records, including timing evidence |
| `getHistory(ownerId)` | One snapshot for dashboard totals, calendar dates, and per-day session details |

All daily queries include zero entries for unstudied dates, including leap days. `now`/`containing` describe the caller's civil date. Travel never changes previously allocated dates. Querying today after travel uses today's device civil date against those fixed historical labels.

## Monthly calendar

The Week graph, Month graph, and Calendar views show their date range above the results. Switching between Month graph and Calendar keeps the same month. The calendar uses Monday as the first day of the week, matching the graph.

Each date with a positive daily total counts once, including days with less than a minute of study. Counts and session times use the completed seconds from the shared aggregation. A session that spans midnight contributes only its allocated seconds to each date, independent of breaks between sessions or any study goal. Selecting a date shows its full date and exact total, with the session start in the device's local time and the seconds credited to that date for each session. The recorded focus-date label stays fixed when the device timezone changes.

A dot marks each studied date. The legend groups daily totals into four bands.

| Band | Daily study time |
| --- | --- |
| Neutral | 0 seconds |
| Light | 1 to 1,799 seconds (under 30 minutes) |
| Medium | 1,800 to 3,599 seconds (30 to under 60 minutes) |
| Strong | 3,600 seconds or more |

Past and current dates with no records are selectable and show a zero total and an empty session list. On narrow displays the grid scrolls horizontally so each date keeps a 48 dp touch target. Future dates without recorded time are unshaded and unavailable. Dates that already have recorded time remain available even if the device's date or timezone moves backward. Date cells expose their full date, duration or future status, and selection state to screen readers.

## Weekly study goals

In Study History, use Week graph to set, change or clear the current week's goal. Enter a whole number of minutes from 15 to 10,080 (168 hours), in 15-minute steps. Goals are optional and stored on this device under the same guest or account owner as study records.

Each week runs from Monday through Sunday. Setting a goal midweek includes all completed study credited to the week, including days before the goal was set. The current goal carries forward until it is changed or cleared. Each change takes effect for its whole week and later weeks, so viewing an ended week shows its effective goal and actuals. Clearing a goal this week leaves earlier weeks intact. Weeks before the first setting or after a clear can be browsed normally, with their study records and calendar counts.

The dashboard uses the same completed seconds for totals, the graph, and goal progress. Remaining time is floored at zero. The percentage is rounded down to a whole percent and can exceed 100%. The bar fills at 100%. For example, 6 hours and 30 minutes toward a 10-hour goal yields 65% and leaves 3 hours and 30 minutes.

The device's civil date determines the current week. When the Week graph is shown in a new current week, its inherited goal is saved under the owner and the Monday date label. A null value represents an unset goal. Weeks between stored Mondays keep the last applicable goal. If the device date moves back and the latest observed week starts within the next 26 hours, editing waits until that week. This covers timezone shifts between UTC−12 and UTC+14. For larger clock corrections, **Use corrected date** lets the owner discard goal settings for weeks after the corrected current week. The confirmation restores editing while preserving earlier goals and all study records. Allocated study dates keep their recorded offsets, as described above.

## Recovery and finalization

The authoritative active metadata is a single `study_active_v2` SharedPreferences JSON value. It contains the stable seat session ID, owner, room, seat, start timestamp, and an optional frozen record pending completion. Timer state is an ordered journal containing closed focus intervals plus an open interval's timestamp, offset, and optional deadline. It is saved on transitions; wall time reconstructs running focus after process death without periodic counter writes.

On leave, freeze the timer, await its queued writes, and persist the frozen record before making the API request. Insert the record into SQLite before deleting recovery metadata. A local persistence failure retains the record and displays a localized retry message. A confirmed seat release is stored with the frozen record so a local retry can finish without contacting the server. Retrying or restarting reuses the frozen timestamps and identity. A pending record cannot resume the timer. Completed insertion followed by a failed cleanup is safe to replay.

Local recovery does not require a live foreground service or a valid server seat. It retries on authentication changes and applies to guests; its timer is restored before announcing the recovered seat. A running normal timer counts all process downtime as focus until it is paused or finalized; Pomodoro remains capped at its focus deadline. Network errors and server expiry do not erase focus evidence. Room occupancy is a separate API concern: the existing leave behavior still allows local completion after an API error, reporting that error. No backend deployment is required. Syncing an active seat stops while the authenticated owner differs from its captured owner; the server seat may expire, but local history remains recoverable. A local DB open failure can be retried.

Storage operations are asynchronous; a process killed before an initial transition reaches durable storage, disk corruption, or user deletion of app storage cannot be recovered. Failed writes are surfaced when completing the session, rather than reported as a completed save.

## Migration

SQLite opens at version 3. Upgrading from version 1 adds columns without deleting or recreating old rows. Each old row receives `legacy-<id>` and owner `legacy:unknown`. Its duration and original start string remain intact. Old timestamps lack timezone evidence and old durations lack pause/break intervals, so the entire old total stays on its original start date. It is not converted into fictitious exact focus intervals.

Version 3 adds the weekly goal table to both version 1 and version 2 databases. Every owner starts with an unset goal. Upgrading preserves all existing study records.

Legacy rows remain in the local database and are omitted from Study History and guest and account totals. Signing in leaves them under unknown ownership. Pre-v2 active metadata is also retained under unknown ownership. Pre-v2 timer totals are retained as estimates and allocated to the original start date.

## Verification

See [the Issue #3 validation record](validation/issue-3.md) for automated checks, device scenarios, and remaining limitations.
