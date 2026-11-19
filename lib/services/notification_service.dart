import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/app_config.dart';
import '../utils/formatters.dart';
import '../models/timer_mode.dart';

/// Service for managing foreground notifications during study sessions.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  @visibleForTesting
  set localNotifications(FlutterLocalNotificationsPlugin plugin) {
    _localNotifications = plugin;
  }

  bool _isInitialized = false;

  /// Initialize the notification service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _setupLocalNotifications();
    _setupForegroundTask();

    _isInitialized = true;
    debugPrint('📢 NotificationService initialized');
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(AppConfig.notificationIconRes);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(initSettings);
  }

  void _setupForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: AppConfig.notificationChannelId,
        channelName: AppConfig.notificationChannelName,
        channelDescription: AppConfig.notificationChannelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000), // Update every second
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Request notification permission (required for Android 13+).
  Future<bool> requestPermission() async {
    try {
      final notificationPermission = 
          await FlutterForegroundTask.checkNotificationPermission();
      if (notificationPermission != NotificationPermission.granted) {
        debugPrint('📢 Requesting notification permission...');
        final result = await FlutterForegroundTask.requestNotificationPermission();
        debugPrint('📢 Notification permission result: $result');
        return result == NotificationPermission.granted;
      }
      debugPrint('📢 Notification permission already granted');
      return true;
    } catch (e) {
      // Handle MissingPluginException in test environment
      debugPrint('📢 Permission check failed (likely in test): $e');
      return false;
    }
  }

  /// Start the foreground service for a study session.
  /// 
  /// [notificationTitle] - Localized title, e.g. "Studying at Denali"
  /// [notificationText] - Localized text, e.g. "Session started - 0m"

  /// Start the foreground service for a study session.
  /// 
  /// [notificationTitle] - Localized title, e.g. "Studying at Denali"
  /// [notificationText] - Localized text, e.g. "Session started - 0m"
  Future<void> startStudySession({
    required String notificationTitle,
    required String notificationText,
    TimerMode mode = TimerMode.normal,
    PomodoroPhase? pomodoroPhase,
    int? remainingSeconds,
  }) async {
    debugPrint('📢 Starting foreground service: $notificationTitle');
    
    // Request permission first (Android 13+)
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      debugPrint('📢 Notification permission denied, cannot start foreground service');
      return;
    }
    
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          notificationIcon: const NotificationIcon(
            metaDataName: AppConfig.notificationIconMetaDataName,
          ),
          callback: _startCallback,
        );
      }
      
      // Send initial state to the task
      await updateTimerState(
        mode: mode,
        pomodoroPhase: pomodoroPhase,
        seconds: remainingSeconds ?? 0,
        isRunning: true,
      );

    } catch (e) {
      debugPrint('📢 Error starting foreground service: $e');
    }
  }

  /// Update the timer state in the background task.
  Future<void> updateTimerState({
    required TimerMode mode,
    required bool isRunning,
    PomodoroPhase? pomodoroPhase,
    required int seconds, // Elapsed for Normal, Remaining for Pomodoro
  }) async {
    FlutterForegroundTask.sendDataToTask({
      'mode': mode.index,
      'phase': pomodoroPhase?.index,
      'seconds': seconds,
      'isRunning': isRunning,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Update the localized strings for Pomodoro mode.
  Future<void> updatePomodoroLocalization({
    required String focusRemainingFormat,
    required String breakRemainingFormat,
    required String focusFinishedText,
    required String breakFinishedText,
  }) async {
    FlutterForegroundTask.sendDataToTask({
      'focusRemainingFormat': focusRemainingFormat,
      'breakRemainingFormat': breakRemainingFormat,
      'focusFinishedText': focusFinishedText,
      'breakFinishedText': breakFinishedText,
    });
  }

  /// Stop the foreground service.
  Future<void> stopStudySession() async {
    await FlutterForegroundTask.stopService();
  }

  /// Check if the foreground service is running.
  Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }

  /// Show a high-priority notification when a timer phase finishes.
  Future<void> showPhaseFinishedNotification({
    required PomodoroPhase phase,
    required String title,
    required String body,
  }) async {
    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'timer_finished_channel',
      'Timer Finished',
      channelDescription: 'Notifications for when the timer finishes',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iOSPlatformChannelSpecifics = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default', 
    );

    const platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _localNotifications.show(
      0, // Notification ID
      title,
      body,
      platformChannelSpecifics,
    );
  }
}

// Top-level callback for foreground task
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_StudySessionHandler());
}

/// Task handler for the foreground service.
class _StudySessionHandler extends TaskHandler {
  TimerMode _mode = TimerMode.normal;
  PomodoroPhase _phase = PomodoroPhase.focus;
  
  // For Normal mode: elapsed seconds
  int _elapsedSeconds = 0;
  
  // For Pomodoro mode: target end time
  DateTime? _pomodoroEndTime;
  int _remainingSeconds = 0;
  
  bool _isRunning = false;
  
  // Localized strings
  String _focusRemainingFormat = 'Focus: {duration} remaining';
  String _breakRemainingFormat = 'Break: {duration} remaining';
  String _focusFinishedText = 'Focus Finished!';
  String _breakFinishedText = 'Break Finished!';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _elapsedSeconds = 0;
    _mode = TimerMode.normal;
    _phase = PomodoroPhase.focus;
    _isRunning = true;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (!_isRunning) return;

    String notificationText;

    if (_mode == TimerMode.normal) {
      _elapsedSeconds += 1; 
      final durationText = Formatters.formatDuration(_elapsedSeconds);
      notificationText = 'Studying - $durationText';
      
    } else {
      // Pomodoro
      if (_pomodoroEndTime != null) {
        final now = DateTime.now();
        final difference = _pomodoroEndTime!.difference(now).inSeconds;
        _remainingSeconds = difference > 0 ? difference : 0;
      } else {
         _remainingSeconds -= 1; 
         if (_remainingSeconds < 0) _remainingSeconds = 0;
      }
      
      final durationText = Formatters.formatDuration(_remainingSeconds);
      
      if (_remainingSeconds <= 0) {
        notificationText = _phase == PomodoroPhase.focus 
            ? _focusFinishedText 
            : _breakFinishedText;
      } else {
        final format = _phase == PomodoroPhase.focus 
            ? _focusRemainingFormat 
            : _breakRemainingFormat;
        notificationText = format.replaceAll('{duration}', durationText);
      }
    }

    FlutterForegroundTask.updateService(
      notificationText: notificationText,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Cleanup if needed
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey('mode')) {
        _mode = TimerMode.values[data['mode'] as int];
      }
      
      if (data.containsKey('phase')) {
        final phaseIndex = data['phase'] as int?;
        if (phaseIndex != null) {
          _phase = PomodoroPhase.values[phaseIndex];
        }
      }
      
      if (data.containsKey('isRunning')) {
        _isRunning = data['isRunning'] as bool;
      }

      if (data.containsKey('seconds')) {
        final seconds = data['seconds'] as int;
        if (_mode == TimerMode.normal) {
          _elapsedSeconds = seconds;
        } else {
          _remainingSeconds = seconds;
          // Calculate end time based on remaining seconds
          _pomodoroEndTime = DateTime.now().add(Duration(seconds: seconds));
        }
      }
      
      // Update localization strings
      if (data.containsKey('focusRemainingFormat')) {
        _focusRemainingFormat = data['focusRemainingFormat'] as String;
      }
      if (data.containsKey('breakRemainingFormat')) {
        _breakRemainingFormat = data['breakRemainingFormat'] as String;
      }
      if (data.containsKey('focusFinishedText')) {
        _focusFinishedText = data['focusFinishedText'] as String;
      }
      if (data.containsKey('breakFinishedText')) {
        _breakFinishedText = data['breakFinishedText'] as String;
      }
      
      // Immediately update notification on state change
      onRepeatEvent(DateTime.now());
    }
  }
}
