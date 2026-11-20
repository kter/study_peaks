import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/study_session.dart';
import '../services/study_persistence_keys.dart';
import '../services/lock_task_service.dart';
import '../services/notification_service.dart';

import '../models/timer_mode.dart';
export '../models/timer_mode.dart'; // Export for other files using TimerProvider

/// Provider for managing timer state.
///
/// Uses timestamp-based calculation to ensure accurate time tracking
/// even when the app is in background or the screen is off.
class TimerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final DateTime Function() _now;
  final List<FocusInterval> _focusIntervals = [];
  DateTime? _focusOpenedAt;
  DateTime? _focusDeadline;
  Duration _focusClockShift = Duration.zero;
  int _focusOffset = 0;
  int _unallocatedSeconds = 0;
  Object? _persistenceError;
  bool _recoveryBlocked = false;

  /// A different owner's recoverable session must not be replaced by a free timer.
  void setRecoveryBlocked(bool blocked) {
    _recoveryBlocked = blocked;
  }

  bool _finalizing = false;
  void freezeForFinalization() {
    pause();
    _finalizing = true;
    _persistState();
  }

  List<FocusInterval> get focusIntervals {
    final result = List<FocusInterval>.of(_focusIntervals);
    if (_focusOpenedAt != null) {
      var end = _now().toUtc().add(_focusClockShift);
      if (_focusDeadline != null && end.isAfter(_focusDeadline!)) {
        end = _focusDeadline!;
      }
      if (end.isBefore(_focusOpenedAt!)) end = _focusOpenedAt!;
      result.add(FocusInterval(
          start: _focusOpenedAt!, end: end, offsetMinutes: _focusOffset));
    }
    return result;
  }

  bool get hasExactIntervals => _unallocatedSeconds == 0;
  void _closeFocus() {
    final snapshot = focusIntervals;
    _focusIntervals
      ..clear()
      ..addAll(snapshot);
    _focusOpenedAt = null;
    _focusDeadline = null;
    _focusClockShift = Duration.zero;
  }

  /// Wait for ordered writes and expose storage failure to the leave flow.
  Future<void> ensurePersisted() async {
    _persistState();
    await _pendingPersistence;
    if (_persistenceError != null) {
      throw StateError('Timer storage failed: $_persistenceError');
    }
  }

  TimerMode _mode = TimerMode.normal;
  bool _isRunning = false;
  Timer? _timer;
  bool _disposed = false;
  static const _keyTimerState = StudyPersistenceKeys.timerState;

  // Seat session the running timer belongs to. Saved with the timer state so
  // a stale timer from an ended session is never restored onto another one.
  String? _sessionId;
  Future<void> _pendingPersistence = Future<void>.value();

  // Timestamp-based tracking for accurate elapsed time
  DateTime? _startedAt;
  Duration _pausedDuration = Duration.zero;

  // Pomodoro settings
  int pomodoroFocusDuration = AppConfig.pomodoroFocusDurationMinutes * 60;
  int pomodoroBreakDuration = AppConfig.pomodoroBreakDurationMinutes * 60;
  PomodoroPhase _pomodoroPhase = PomodoroPhase.focus;
  int _pomodoroCompletedCycles = 0;

  // Pomodoro timestamp tracking
  DateTime? _pomodoroPhaseStartedAt;
  Duration _pomodoroElapsedBeforePause = Duration.zero;

  final NotificationService _notificationService;

  // Lock task (screen pinning) state
  final LockTaskService _lockTaskService;
  bool _screenLockEnabled = false;
  bool _isScreenLocked = false;
  bool _pinning = false;
  StreamSubscription<bool>? _lockTaskExitedSubscription;

  /// Callback invoked when lock task mode is exited by the user.
  /// The UI layer can set this to show a Toast/SnackBar.
  VoidCallback? onLockTaskExited;

  TimerProvider({
    DateTime Function()? now,
    NotificationService? notificationService,
    LockTaskService? lockTaskService,
  })  : _now = now ?? DateTime.now,
        _notificationService = notificationService ?? NotificationService(),
        _lockTaskService = lockTaskService ?? LockTaskService() {
    WidgetsBinding.instance.addObserver(this);
    _lockTaskExitedSubscription =
        _lockTaskService.onLockTaskModeExited.listen((_) {
      _handleLockTaskExited();
    });
  }

  // Localized strings for notifications
  String? _focusFinishedTitle;
  String? _breakFinishedTitle;
  String? _focusFinishedBody;
  String? _breakFinishedBody;

  void updateLocalization({
    required String focusFinishedTitle,
    required String breakFinishedTitle,
    required String focusFinishedBody,
    required String breakFinishedBody,
  }) {
    _focusFinishedTitle = focusFinishedTitle;
    _breakFinishedTitle = breakFinishedTitle;
    _focusFinishedBody = focusFinishedBody;
    _breakFinishedBody = breakFinishedBody;
  }

  TimerMode get mode => _mode;

  /// Seat session the timer state belongs to (null when not bound).
  String? get sessionId => _sessionId;
  bool get isRunning => _isRunning;
  bool get waitingToStart => !_isRunning &&
      (_mode == TimerMode.normal
          ? _pausedDuration == Duration.zero
          : _pomodoroElapsedBeforePause == Duration.zero);
  PomodoroPhase get pomodoroPhase => _pomodoroPhase;
  bool get isOnBreak =>
      mode == TimerMode.pomodoro && pomodoroPhase == PomodoroPhase.shortBreak;
  int get pomodoroCompletedCycles => _pomodoroCompletedCycles;

  // Lock task getters
  bool get screenLockEnabled => _screenLockEnabled;
  bool get isScreenLocked => _isScreenLocked;
  bool get shouldPromptForScreenLock =>
      screenLockEnabled && !isScreenLocked && !isOnBreak;

  /// Get elapsed seconds using timestamp-based calculation.
  /// This ensures accurate time even when the app is in background.
  int get elapsedSeconds =>
      (_pausedDuration + _timeSince(_startedAt)).inSeconds;

  Duration _timeSince(DateTime? start) {
    if (start == null) return Duration.zero;
    final elapsed = _now().difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration get _pomodoroRemaining {
    final phaseSeconds = _pomodoroPhase == PomodoroPhase.focus
        ? pomodoroFocusDuration
        : pomodoroBreakDuration;
    final elapsed =
        _pomodoroElapsedBeforePause + _timeSince(_pomodoroPhaseStartedAt);
    final remaining = Duration(seconds: phaseSeconds) - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Round up so a partially elapsed second is still visible on the countdown.
  int get pomodoroRemainingSeconds =>
      (_pomodoroRemaining.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;

  /// Format duration as "HH:MM:SS" or "MM:SS".
  String get formattedTime {
    if (_mode == TimerMode.normal) {
      return _formatDuration(elapsedSeconds);
    } else {
      return _formatDuration(pomodoroRemainingSeconds);
    }
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Handle app lifecycle changes to recalculate time when resuming.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning) {
      // Force UI update when app resumes - the getters will calculate
      // the correct time based on timestamps
      notifyListeners();

      // Check if pomodoro phase should switch
      if (_mode == TimerMode.pomodoro && pomodoroRemainingSeconds <= 0) {
        _switchPomodoroPhase();
      }
    }
  }

  /// Toggle timer mode.
  void setMode(TimerMode mode) {
    if (_isRunning || _finalizing) return;
    _mode = mode;
    reset();
    _persistState();
    notifyListeners();
  }

  /// Toggle screen lock preference (opt-in).
  void setScreenLockEnabled(bool enabled) {
    _screenLockEnabled = enabled;
    notifyListeners();
  }

  /// Start the timer.
  ///
  /// [sessionId] ties the saved timer state to the current seat session.
  void start({String? sessionId}) {
    if (_finalizing || _recoveryBlocked) return;
    if (sessionId != null && sessionId != _sessionId) {
      // A newly seated session starts with its own journal. Unseated focus and
      // a previous seat's focus must never be adopted by this seat's owner.
      _resetFields();
      _focusIntervals.clear();
      _unallocatedSeconds = 0;
      _pomodoroCompletedCycles = 0;
      _sessionId = sessionId;
    }
    if (_isRunning) return;
    _isRunning = true;
    if (_mode == TimerMode.normal || _pomodoroPhase == PomodoroPhase.focus) {
      final now = _now();
      final wallStart = now.toUtc();
      final previousEnd =
          _focusIntervals.isEmpty ? null : _focusIntervals.last.end;
      _focusOpenedAt = previousEnd != null && previousEnd.isAfter(wallStart)
          ? previousEnd
          : wallStart;
      // A device-clock rollback must not create overlapping intervals or make
      // completion impossible. Keep their order while retaining elapsed time.
      _focusClockShift = _focusOpenedAt!.difference(wallStart);
      _focusOffset = now.timeZoneOffset.inMinutes;
      _focusDeadline = _mode == TimerMode.pomodoro
          ? _focusOpenedAt!.add(_pomodoroRemaining)
          : null;
    }

    if (_mode == TimerMode.normal) {
      _startedAt = _now();
    } else {
      _pomodoroPhaseStartedAt = _now();
    }

    _updateNotification();
    _startUiTimer();
    _persistState();
    notifyListeners();
  }

  // The actual time is calculated from timestamps; this timer only updates UI.
  void _startUiTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_mode == TimerMode.pomodoro && pomodoroRemainingSeconds <= 0) {
        _switchPomodoroPhase();
      }
      notifyListeners();
      // We don't need to update notification on every tick because background task handles it,
      // EXCEPT when phase changes (handled in _switchPomodoroPhase).
    });
  }

  /// Start timer with screen lock (called from UI after dialog confirmation).
  Future<void> startWithLock() async {
    if (_disposed || _finalizing || _recoveryBlocked || _isRunning || _pinning) return;
    _pinning = true;
    final sessionId = _sessionId;
    try {
      final pinned = await _lockTaskService.startLockTask();
      if (_disposed || _finalizing || _recoveryBlocked || sessionId != _sessionId) {
        if (pinned) await _lockTaskService.stopLockTask();
        return;
      }
      _isScreenLocked = pinned;
      if (pinned) await _lockTaskService.setKeepScreenOn(true);
      start();
    } finally {
      _pinning = false;
    }
  }

  /// Pause the timer.
  void pause() {
    if (!_isRunning) return;

    _closeFocus();
    _timer?.cancel();
    _isRunning = false;

    if (_mode == TimerMode.normal) {
      // Save elapsed time when pausing
      _pausedDuration += _timeSince(_startedAt);
      _startedAt = null;
    } else {
      // Save pomodoro elapsed time when pausing
      _pomodoroElapsedBeforePause += _timeSince(_pomodoroPhaseStartedAt);
      _pomodoroPhaseStartedAt = null;
    }

    _persistState();
    _updateNotification();
    notifyListeners();
  }

  /// Reset the timer.
  ///
  /// The stopped, reset state is saved for the current session so that a
  /// restore keeps it stopped (and keeps the mode) instead of auto-starting.
  void reset() {
    if (_finalizing) return;
    _resetFields();
    _persistState();
    notifyListeners();
  }

  /// Reset the timer and forget its seat session. Call when leaving the seat;
  /// plain [reset] (reset button, mode switch) keeps the session binding.
  void endSession() {
    _sessionId = null;
    _resetFields();
    _finalizing = false;
    _focusIntervals.clear();
    _unallocatedSeconds = 0;
    _queuePersistence(null);
    notifyListeners();
  }

  void _resetFields() {
    _closeFocus();
    _timer?.cancel();
    _isRunning = false;

    // Reset normal mode
    _startedAt = null;
    _pausedDuration = Duration.zero;

    // Reset pomodoro mode
    _pomodoroPhase = PomodoroPhase.focus;
    _pomodoroPhaseStartedAt = null;
    _pomodoroElapsedBeforePause = Duration.zero;

    // Release lock task if active
    _releaseLockTask();

    _updateNotification();
  }

  /// Set the initial duration (e.g. when restoring a session).
  void setInitialDuration(Duration duration) {
    if (_isRunning) return;
    _pausedDuration = duration;
    _unallocatedSeconds = duration.inSeconds;
    _persistState();
    notifyListeners();
  }

  /// Switch between focus and break phases in Pomodoro mode.
  void _switchPomodoroPhase() {
    // Notify about the finished phase BEFORE switching
    // Determine the title/body based on what JUST finished
    _closeFocus();
    final finishedPhase = _pomodoroPhase;

    // Use localized strings if available, otherwise fall back to English defaults
    final title = finishedPhase == PomodoroPhase.focus
        ? (_focusFinishedTitle ?? 'Focus Finished!')
        : (_breakFinishedTitle ?? 'Break Finished!');

    final body = finishedPhase == PomodoroPhase.focus
        ? (_focusFinishedBody ?? 'Time for a break.')
        : (_breakFinishedBody ?? 'Time to focus.');

    _notificationService.showPhaseFinishedNotification(
      phase: finishedPhase,
      title: title,
      body: body,
    );

    if (_pomodoroPhase == PomodoroPhase.focus) {
      _pomodoroPhase = PomodoroPhase.shortBreak;
      _pomodoroCompletedCycles++;
      // Release lock task when switching to break
      _releaseLockTask();
    } else {
      _pomodoroPhase = PomodoroPhase.focus;
    }

    // Reset phase timer
    _pomodoroElapsedBeforePause = Duration.zero;
    _pomodoroPhaseStartedAt = null;
    _isRunning = false;
    _timer?.cancel();

    _persistState();
    _updateNotification();
    notifyListeners();
  }

  Future<void> _updateNotification() async {
    // Only update if service is running
    if (!await _notificationService.isRunning()) return;

    final seconds =
        _mode == TimerMode.normal ? elapsedSeconds : pomodoroRemainingSeconds;

    await _notificationService.updateTimerState(
      sessionId: _sessionId,
      mode: _mode,
      isRunning: _isRunning,
      waitingToStart: waitingToStart,
      pomodoroPhase: _mode == TimerMode.pomodoro ? _pomodoroPhase : null,
      seconds: seconds,
    );
  }

  /// Release lock task mode and keep-screen-on flag.
  void _releaseLockTask() {
    if (_isScreenLocked) {
      _lockTaskService.stopLockTask();
      _lockTaskService.setKeepScreenOn(false);
      _isScreenLocked = false;
    }
  }

  /// Restore saved timestamps and restart UI updates for a running timer.
  ///
  /// Only restores state saved for the same [sessionId]; state from another
  /// (ended) session is discarded and false is returned.
  Future<bool> restoreState({String? sessionId}) async {
    try {
      await _pendingPersistence;
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return false;
      final saved = prefs.getString(_keyTimerState);
      if (saved == null) return false;

      final state = jsonDecode(saved) as Map<String, dynamic>;
      if ((state['sessionId'] as String?) != sessionId) {
        _queuePersistence(null);
        return false;
      }
      final mode = TimerMode.values[state['mode'] as int];
      final isRunning = state['isRunning'] as bool;
      final phase = PomodoroPhase.values[state['pomodoroPhase'] as int];
      final cycles = state['pomodoroCompletedCycles'] as int;
      final pausedDurationMs = state['pausedDurationMs'] as int;
      final elapsedBeforePauseMs = state['pomodoroElapsedBeforePauseMs'] as int? ??
          (state['pomodoroElapsedBeforePause'] as int) *
              Duration.millisecondsPerSecond;
      final startedAtMs = state['startedAt'] as int?;
      final phaseStartedAtMs = state['pomodoroPhaseStartedAt'] as int?;
      if (cycles < 0 ||
          pausedDurationMs < 0 ||
          elapsedBeforePauseMs < 0 ||
          (isRunning &&
              (mode == TimerMode.normal
                  ? startedAtMs == null
                  : phaseStartedAtMs == null))) {
        return false;
      }
      final startedAt = startedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(startedAtMs);
      final phaseStartedAt = phaseStartedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(phaseStartedAtMs);

      _timer?.cancel();
      _finalizing = state['finalizing'] as bool? ?? false;
      _mode = mode;
      _isRunning = isRunning;
      _startedAt = isRunning ? startedAt : null;
      _pausedDuration = Duration(milliseconds: pausedDurationMs);
      _pomodoroPhase = phase;
      _pomodoroCompletedCycles = cycles;
      _pomodoroPhaseStartedAt = isRunning ? phaseStartedAt : null;
      _pomodoroElapsedBeforePause = Duration(milliseconds: elapsedBeforePauseMs);
      _sessionId = sessionId;
      _focusIntervals
        ..clear()
        ..addAll((state['focusIntervals'] as List? ?? []).map(
            (i) => FocusInterval.fromMap(Map<String, dynamic>.from(i as Map))));
      _unallocatedSeconds = state['unallocatedSeconds'] as int? ??
          (state.containsKey('focusIntervals')
              ? 0
              : (_mode == TimerMode.normal
                  ? elapsedSeconds
                  : cycles * pomodoroFocusDuration +
                      (_pomodoroPhase == PomodoroPhase.focus
                          ? pomodoroFocusDuration - pomodoroRemainingSeconds
                          : 0)));
      _focusOpenedAt = state['focusOpenedAt'] == null
          ? null
          : DateTime.parse(state['focusOpenedAt'] as String);
      _focusDeadline = state['focusDeadline'] == null
          ? null
          : DateTime.parse(state['focusDeadline'] as String);
      _focusOffset = state['focusOffset'] as int? ?? 0;
      _focusClockShift =
          Duration(milliseconds: state['focusClockShiftMs'] as int? ?? 0);
      if (_isRunning && !state.containsKey('focusIntervals')) {
        // Old snapshots have no timing evidence; retain their total as estimated.
        if (_mode == TimerMode.normal ||
            _pomodoroPhase == PomodoroPhase.focus) {
          _focusOpenedAt = _now().toUtc();
          _focusOffset = _now().timeZoneOffset.inMinutes;
          _focusDeadline = _mode == TimerMode.pomodoro
              ? _now().toUtc().add(_pomodoroRemaining)
              : null;
        }
      }
      if (_isRunning) {
        // Match the periodic tick: an expired phase advances to the next
        // phase and stops, waiting for the user to start it.
        if (_mode == TimerMode.pomodoro && pomodoroRemainingSeconds <= 0) {
          _switchPomodoroPhase();
        }
        if (_isRunning) _startUiTimer();
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to restore timer state: $e');
      return false;
    }
  }

  void _persistState() {
    if (_recoveryBlocked) return;
    // Snapshot before awaiting so subsequent changes cannot alter this write.
    _queuePersistence(jsonEncode({
      'finalizing': _finalizing,
      'focusIntervals': _focusIntervals.map((i) => i.toMap()).toList(),
      'focusOpenedAt': _focusOpenedAt?.toIso8601String(),
      'focusDeadline': _focusDeadline?.toIso8601String(),
      'focusOffset': _focusOffset,
      'focusClockShiftMs': _focusClockShift.inMilliseconds,
      'unallocatedSeconds': _unallocatedSeconds,
      'sessionId': _sessionId,
      'mode': _mode.index,
      'isRunning': _isRunning,
      'startedAt': _startedAt?.millisecondsSinceEpoch,
      'pausedDurationMs': _pausedDuration.inMilliseconds,
      'pomodoroPhase': _pomodoroPhase.index,
      'pomodoroCompletedCycles': _pomodoroCompletedCycles,
      'pomodoroPhaseStartedAt': _pomodoroPhaseStartedAt?.millisecondsSinceEpoch,
      'pomodoroElapsedBeforePause': _pomodoroElapsedBeforePause.inSeconds,
      'pomodoroElapsedBeforePauseMs': _pomodoroElapsedBeforePause.inMilliseconds,
    }));
  }

  void _queuePersistence(String? state) {
    // Keep saves and reset's removal in order, including rapid start/pause/reset.
    _pendingPersistence = _pendingPersistence.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final active = prefs.getString(StudyPersistenceKeys.activeSession);
        final activeId = active == null
            ? prefs.getString(StudyPersistenceKeys.legacySessionId)
            : (jsonDecode(active) as Map<String, dynamic>)['sessionId']
                as String?;
        if (activeId != null) {
          // Also protect the window before owner-aware recovery has run, and
          // never let a stale queued removal erase an active session's journal.
          if (state == null) return;
          final timerId =
              (jsonDecode(state) as Map<String, dynamic>)['sessionId'];
          if (timerId != activeId) {
            throw StateError('Another active session owns the timer journal');
          }
        }
        if (state == null) {
          if (!await prefs.remove(_keyTimerState)) {
            throw StateError('Timer removal failed');
          }
        } else {
          if (!await prefs.setString(_keyTimerState, state)) {
            throw StateError('Timer write failed');
          }
        }
        _persistenceError = null;
      } catch (e) {
        _persistenceError = e;
        debugPrint('Failed to persist timer state: $e');
      }
    });
  }

  /// Remove any saved timer state (e.g. when the seat session is cleared).
  static Future<void> clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_keyTimerState)) {
      throw StateError('Timer cleanup failed');
    }
  }

  /// Handle when the user manually exits lock task mode.
  void _handleLockTaskExited() {
    _isScreenLocked = false;
    _lockTaskService.setKeepScreenOn(false);
    // Notify UI to show a message, but DON'T stop the timer
    onLockTaskExited?.call();
    notifyListeners();
  }

  /// Get total study time (for both modes).
  int get totalStudySeconds =>
      _unallocatedSeconds +
      focusIntervals.fold<int>(0, (sum, i) => sum + i.milliseconds) ~/ 1000;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _releaseLockTask();
    _lockTaskExitedSubscription?.cancel();
    _lockTaskService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
