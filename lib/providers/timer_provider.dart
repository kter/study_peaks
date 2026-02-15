import 'dart:async';
import 'package:flutter/widgets.dart';
import '../config/app_config.dart';
import '../services/lock_task_service.dart';
import '../services/notification_service.dart';

import '../models/timer_mode.dart';
export '../models/timer_mode.dart'; // Export for other files using TimerProvider


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
  int pomodoroFocusDuration = AppConfig.pomodoroFocusDurationMinutes * 60;
  int pomodoroBreakDuration = AppConfig.pomodoroBreakDurationMinutes * 60;
  PomodoroPhase _pomodoroPhase = PomodoroPhase.focus;
  int _pomodoroCompletedCycles = 0;

  // Pomodoro timestamp tracking
  DateTime? _pomodoroPhaseStartedAt;
  int _pomodoroElapsedBeforePause = 0;

  final NotificationService _notificationService;

  // Lock task (screen pinning) state
  final LockTaskService _lockTaskService;
  bool _screenLockEnabled = false;
  bool _isScreenLocked = false;
  StreamSubscription<bool>? _lockTaskExitedSubscription;

  /// Callback invoked when lock task mode is exited by the user.
  /// The UI layer can set this to show a Toast/SnackBar.
  VoidCallback? onLockTaskExited;

  TimerProvider({
    NotificationService? notificationService,
    LockTaskService? lockTaskService,
  })  : _notificationService = notificationService ?? NotificationService(),
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
  bool get isRunning => _isRunning;
  PomodoroPhase get pomodoroPhase => _pomodoroPhase;
  int get pomodoroCompletedCycles => _pomodoroCompletedCycles;

  // Lock task getters
  bool get screenLockEnabled => _screenLockEnabled;
  bool get isScreenLocked => _isScreenLocked;

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

  /// Toggle screen lock preference (opt-in).
  void setScreenLockEnabled(bool enabled) {
    _screenLockEnabled = enabled;
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

    _updateNotification();

    // Timer for UI updates only (the actual time is calculated from timestamps)
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_mode == TimerMode.pomodoro && pomodoroRemainingSeconds <= 0) {
        _switchPomodoroPhase();
      }
      notifyListeners();
      // We don't need to update notification on every tick because background task handles it,
      // EXCEPT when phase changes (handled in _switchPomodoroPhase).
    });
    notifyListeners();
  }

  /// Start timer with screen lock (called from UI after dialog confirmation).
  Future<void> startWithLock() async {
    await _lockTaskService.startLockTask();
    await _lockTaskService.setKeepScreenOn(true);
    _isScreenLocked = true;
    start();
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
    
    _updateNotification();
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
    
    // Release lock task if active
    _releaseLockTask();
    
    _updateNotification();
    notifyListeners();
  }

  /// Set the initial duration (e.g. when restoring a session).
  void setInitialDuration(Duration duration) {
    if (_isRunning) return;
    _pausedDuration = duration;
    notifyListeners();
  }

  /// Switch between focus and break phases in Pomodoro mode.
  void _switchPomodoroPhase() {
    // Notify about the finished phase BEFORE switching
    // Determine the title/body based on what JUST finished
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
    _pomodoroElapsedBeforePause = 0;
    _pomodoroPhaseStartedAt = null;
    _isRunning = false;
    _timer?.cancel();
    
    _updateNotification();
    notifyListeners();
  }

  Future<void> _updateNotification() async {
    // Only update if service is running
    if (!await _notificationService.isRunning()) return;

    final seconds = _mode == TimerMode.normal 
        ? elapsedSeconds 
        : pomodoroRemainingSeconds;

    await _notificationService.updateTimerState(
      mode: _mode,
      isRunning: _isRunning,
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

  /// Handle when the user manually exits lock task mode.
  void _handleLockTaskExited() {
    _isScreenLocked = false;
    _lockTaskService.setKeepScreenOn(false);
    // Notify UI to show a message, but DON'T stop the timer
    onLockTaskExited?.call();
    notifyListeners();
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
    _releaseLockTask();
    _lockTaskExitedSubscription?.cancel();
    _lockTaskService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
