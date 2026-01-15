import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
    notifyListeners();
  }

  /// Start the timer.
  void start() {
    if (_isRunning) return;

    _isRunning = true;
    
    if (_mode == TimerMode.normal) {
      _startedAt = DateTime.now();
    } else {
      _pomodoroPhaseStartedAt = DateTime.now();
    }

    // Timer for UI updates only (the actual time is calculated from timestamps)
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_mode == TimerMode.pomodoro && pomodoroRemainingSeconds <= 0) {
        _switchPomodoroPhase();
      }
      notifyListeners();
    });
    notifyListeners();
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
    
    notifyListeners();
  }

  /// Reset the timer.
  void reset() {
    _timer?.cancel();
    _isRunning = false;
    
    // Reset normal mode
    _startedAt = null;
    _pausedDuration = Duration.zero;
    
    // Reset pomodoro mode
    _pomodoroPhase = PomodoroPhase.focus;
    _pomodoroPhaseStartedAt = null;
    _pomodoroElapsedBeforePause = 0;
    
    notifyListeners();
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
  }

  /// Get total study time (for both modes).
  int get totalStudySeconds {
    if (_mode == TimerMode.normal) {
      return elapsedSeconds;
    } else {
      // Calculate total focus time in Pomodoro mode
      final completedFocusTime = _pomodoroCompletedCycles * pomodoroFocusDuration;
      final currentFocusTime = _pomodoroPhase == PomodoroPhase.focus
          ? pomodoroFocusDuration - pomodoroRemainingSeconds
          : 0;
      return completedFocusTime + currentFocusTime;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
