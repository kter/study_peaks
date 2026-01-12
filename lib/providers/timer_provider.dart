import 'dart:async';
import 'package:flutter/foundation.dart';

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
class TimerProvider extends ChangeNotifier {
  TimerMode _mode = TimerMode.normal;
  bool _isRunning = false;
  int _elapsedSeconds = 0;
  Timer? _timer;

  // Pomodoro settings
  static const int pomodoroFocusDuration = 25 * 60; // 25 minutes
  static const int pomodoroBreakDuration = 5 * 60; // 5 minutes
  PomodoroPhase _pomodoroPhase = PomodoroPhase.focus;
  int _pomodoroRemainingSeconds = pomodoroFocusDuration;
  int _pomodoroCompletedCycles = 0;

  TimerMode get mode => _mode;
  bool get isRunning => _isRunning;
  int get elapsedSeconds => _elapsedSeconds;
  PomodoroPhase get pomodoroPhase => _pomodoroPhase;
  int get pomodoroRemainingSeconds => _pomodoroRemainingSeconds;
  int get pomodoroCompletedCycles => _pomodoroCompletedCycles;

  /// Format duration as "HH:MM:SS" or "MM:SS".
  String get formattedTime {
    if (_mode == TimerMode.normal) {
      return _formatDuration(_elapsedSeconds);
    } else {
      return _formatDuration(_pomodoroRemainingSeconds);
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

  /// Toggle timer mode.
  void setMode(TimerMode mode) {
    if (_isRunning) return; // Can't change mode while running
    _mode = mode;
    reset();
    notifyListeners();
  }

  /// Start the timer.
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_mode == TimerMode.normal) {
        _elapsedSeconds++;
      } else {
        _pomodoroRemainingSeconds--;
        if (_pomodoroRemainingSeconds <= 0) {
          _switchPomodoroPhase();
        }
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Pause the timer.
  void pause() {
    _timer?.cancel();
    _isRunning = false;
    notifyListeners();
  }

  /// Reset the timer.
  void reset() {
    _timer?.cancel();
    _isRunning = false;
    _elapsedSeconds = 0;
    _pomodoroPhase = PomodoroPhase.focus;
    _pomodoroRemainingSeconds = pomodoroFocusDuration;
    notifyListeners();
  }

  /// Switch between focus and break phases in Pomodoro mode.
  void _switchPomodoroPhase() {
    if (_pomodoroPhase == PomodoroPhase.focus) {
      _pomodoroPhase = PomodoroPhase.shortBreak;
      _pomodoroRemainingSeconds = pomodoroBreakDuration;
      _pomodoroCompletedCycles++;
    } else {
      _pomodoroPhase = PomodoroPhase.focus;
      _pomodoroRemainingSeconds = pomodoroFocusDuration;
    }
  }

  /// Get total study time (for both modes).
  int get totalStudySeconds {
    if (_mode == TimerMode.normal) {
      return _elapsedSeconds;
    } else {
      // Calculate total focus time in Pomodoro mode
      final completedFocusTime = _pomodoroCompletedCycles * pomodoroFocusDuration;
      final currentFocusTime = _pomodoroPhase == PomodoroPhase.focus
          ? pomodoroFocusDuration - _pomodoroRemainingSeconds
          : 0;
      return completedFocusTime + currentFocusTime;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
