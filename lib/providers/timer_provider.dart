import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// Timer mode for study sessions.
enum TimerMode {
  normal,
  pomodoro,
}

/// Pomodoro phase.
enum PomodoroPhase {
  focus,
  shortBreak,
}

/// Provider for managing timer state.
///
/// Uses timestamp-based calculation to ensure accurate time tracking
/// even when the app is in background or the screen is off.
class TimerProvider extends ChangeNotifier with WidgetsBindingObserver {
  TimerMode _mode = TimerMode.normal;
  bool _isRunning = false;
  Timer? _timer;
  bool _disposed = false;
  static const _keyTimerState = 'persisted_timer_state';

  // Seat session the running timer belongs to. Saved with the timer state so
  // a stale timer from an ended session is never restored onto another one.
  String? _sessionId;
  Future<void> _pendingPersistence = Future<void>.value();

  // Timestamp-based tracking for accurate elapsed time
  DateTime? _startedAt;
  Duration _pausedDuration = Duration.zero;

  // Pomodoro settings
  static final int pomodoroFocusDuration =
      AppConfig.pomodoroFocusDurationMinutes * 60;
  static final int pomodoroBreakDuration =
      AppConfig.pomodoroBreakDurationMinutes * 60;
  PomodoroPhase _pomodoroPhase = PomodoroPhase.focus;
  int _pomodoroCompletedCycles = 0;

  // Pomodoro timestamp tracking
  DateTime? _pomodoroPhaseStartedAt;
  int _pomodoroElapsedBeforePause = 0;

  TimerProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  TimerMode get mode => _mode;
  bool get isRunning => _isRunning;
  PomodoroPhase get pomodoroPhase => _pomodoroPhase;
  int get pomodoroCompletedCycles => _pomodoroCompletedCycles;

  /// Get elapsed seconds using timestamp-based calculation.
  /// This ensures accurate time even when the app is in background.
  int get elapsedSeconds {
    if (_startedAt == null) {
      return _pausedDuration.inSeconds;
    }
    return _pausedDuration.inSeconds +
        DateTime.now().difference(_startedAt!).inSeconds;
  }

  /// Get remaining seconds for pomodoro mode.
  int get pomodoroRemainingSeconds {
    final phaseDuration = _pomodoroPhase == PomodoroPhase.focus
        ? pomodoroFocusDuration
        : pomodoroBreakDuration;

    int elapsed;
    if (_pomodoroPhaseStartedAt == null) {
      elapsed = _pomodoroElapsedBeforePause;
    } else {
      elapsed = _pomodoroElapsedBeforePause +
          DateTime.now().difference(_pomodoroPhaseStartedAt!).inSeconds;
    }

    final remaining = phaseDuration - elapsed;
    return remaining > 0 ? remaining : 0;
  }

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
    if (_isRunning) return; // Can't change mode while running
    _mode = mode;
    reset();
    _persistState();
    notifyListeners();
  }

  /// Start the timer.
  ///
  /// [sessionId] ties the saved timer state to the current seat session.
  void start({String? sessionId}) {
    if (_isRunning) {
      // Already running (e.g. started before sitting down): bind it to the
      // new session so it can be restored.
      if (sessionId != null && sessionId != _sessionId) {
        _sessionId = sessionId;
        _persistState();
      }
      return;
    }

    if (sessionId != null) _sessionId = sessionId;
    _isRunning = true;

    if (_mode == TimerMode.normal) {
      _startedAt = DateTime.now();
    } else {
      _pomodoroPhaseStartedAt = DateTime.now();
    }

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
    });
  }

  /// Pause the timer.
  void pause() {
    if (!_isRunning) return;

    _timer?.cancel();
    _isRunning = false;

    if (_mode == TimerMode.normal) {
      // Save elapsed time when pausing
      if (_startedAt != null) {
        _pausedDuration += DateTime.now().difference(_startedAt!);
        _startedAt = null;
      }
    } else {
      // Save pomodoro elapsed time when pausing
      if (_pomodoroPhaseStartedAt != null) {
        _pomodoroElapsedBeforePause +=
            DateTime.now().difference(_pomodoroPhaseStartedAt!).inSeconds;
        _pomodoroPhaseStartedAt = null;
      }
    }

    _persistState();
    notifyListeners();
  }

  /// Reset the timer.
  ///
  /// The stopped, reset state is saved for the current session so that a
  /// restore keeps it stopped (and keeps the mode) instead of auto-starting.
  void reset() {
    _resetFields();
    _persistState();
    notifyListeners();
  }

  /// Reset the timer and forget its seat session. Call when leaving the seat;
  /// plain [reset] (reset button, mode switch) keeps the session binding.
  void endSession() {
    _sessionId = null;
    _resetFields();
    _queuePersistence(null);
    notifyListeners();
  }

  void _resetFields() {
    _timer?.cancel();
    _isRunning = false;

    // Reset normal mode
    _startedAt = null;
    _pausedDuration = Duration.zero;

    // Reset pomodoro mode
    _pomodoroPhase = PomodoroPhase.focus;
    _pomodoroPhaseStartedAt = null;
    _pomodoroElapsedBeforePause = 0;
  }

  /// Switch between focus and break phases in Pomodoro mode.
  void _switchPomodoroPhase() {
    if (_pomodoroPhase == PomodoroPhase.focus) {
      _pomodoroPhase = PomodoroPhase.shortBreak;
      _pomodoroCompletedCycles++;
    } else {
      _pomodoroPhase = PomodoroPhase.focus;
    }

    // Reset phase timer
    _pomodoroElapsedBeforePause = 0;
    if (_isRunning) {
      _pomodoroPhaseStartedAt = DateTime.now();
    }
    _persistState();
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
      final elapsedBeforePause = state['pomodoroElapsedBeforePause'] as int;
      final startedAtMs = state['startedAt'] as int?;
      final phaseStartedAtMs = state['pomodoroPhaseStartedAt'] as int?;
      if (cycles < 0 ||
          pausedDurationMs < 0 ||
          elapsedBeforePause < 0 ||
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
      _mode = mode;
      _isRunning = isRunning;
      _startedAt = isRunning ? startedAt : null;
      _pausedDuration = Duration(milliseconds: pausedDurationMs);
      _pomodoroPhase = phase;
      _pomodoroCompletedCycles = cycles;
      _pomodoroPhaseStartedAt = isRunning ? phaseStartedAt : null;
      _pomodoroElapsedBeforePause = elapsedBeforePause;
      _sessionId = sessionId;
      if (_isRunning) {
        // Match the periodic tick: an expired phase advances once and starts now.
        if (_mode == TimerMode.pomodoro && pomodoroRemainingSeconds <= 0) {
          _switchPomodoroPhase();
        }
        _startUiTimer();
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to restore timer state: $e');
      return false;
    }
  }

  void _persistState() {
    // Snapshot before awaiting so subsequent changes cannot alter this write.
    _queuePersistence(jsonEncode({
      'sessionId': _sessionId,
      'mode': _mode.index,
      'isRunning': _isRunning,
      'startedAt': _startedAt?.millisecondsSinceEpoch,
      'pausedDurationMs': _pausedDuration.inMilliseconds,
      'pomodoroPhase': _pomodoroPhase.index,
      'pomodoroCompletedCycles': _pomodoroCompletedCycles,
      'pomodoroPhaseStartedAt': _pomodoroPhaseStartedAt?.millisecondsSinceEpoch,
      'pomodoroElapsedBeforePause': _pomodoroElapsedBeforePause,
    }));
  }

  void _queuePersistence(String? state) {
    // Keep saves and reset's removal in order, including rapid start/pause/reset.
    _pendingPersistence = _pendingPersistence.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (state == null) {
          await prefs.remove(_keyTimerState);
        } else {
          await prefs.setString(_keyTimerState, state);
        }
      } catch (e) {
        debugPrint('Failed to persist timer state: $e');
      }
    });
  }

  /// Remove any saved timer state (e.g. when the seat session is cleared).
  static Future<void> clearPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyTimerState);
    } catch (e) {
      debugPrint('Failed to clear timer state: $e');
    }
  }

  /// Get total study time (for both modes).
  int get totalStudySeconds {
    if (_mode == TimerMode.normal) {
      return elapsedSeconds;
    } else {
      // Calculate total focus time in Pomodoro mode
      final completedFocusTime =
          _pomodoroCompletedCycles * pomodoroFocusDuration;
      final currentFocusTime = _pomodoroPhase == PomodoroPhase.focus
          ? pomodoroFocusDuration - pomodoroRemainingSeconds
          : 0;
      return completedFocusTime + currentFocusTime;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
