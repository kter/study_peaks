import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/formatters.dart';
import '../models/timer_mode.dart';
import 'study_persistence_keys.dart';

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
  Future<void> startStudySession({
    required String notificationTitle,
    required String notificationText,
    required String studyingFormat,
    required bool isRunning,
    TimerMode mode = TimerMode.normal,
    PomodoroPhase? pomodoroPhase,
    int? remainingSeconds,
    String? focusRemainingFormat,
    String? breakRemainingFormat,
    String? focusFinishedText,
    String? breakFinishedText,
  }) async {
    debugPrint('📢 Starting foreground service: $notificationTitle');
    
    // Request permission first (Android 13+)
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      debugPrint('📢 Notification permission denied, cannot start foreground service');
      return;
    }
    
    try {
      // The task runs in a separate isolate. Save its state before starting it
      // so it can initialize even if it isn't ready to receive messages yet.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StudyPersistenceKeys.notificationState,
        jsonEncode({
          ..._timerStateData(
            mode: mode,
            pomodoroPhase: pomodoroPhase,
            seconds: remainingSeconds ?? 0,
            isRunning: isRunning,
          ),
          'studyingFormat': studyingFormat,
          'focusRemainingFormat': focusRemainingFormat,
          'breakRemainingFormat': breakRemainingFormat,
          'focusFinishedText': focusFinishedText,
          'breakFinishedText': breakFinishedText,
        }),
      );

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
    final data = _timerStateData(
      mode: mode,
      isRunning: isRunning,
      pomodoroPhase: pomodoroPhase,
      seconds: seconds,
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(StudyPersistenceKeys.notificationState);
    // An update already in flight when the session stops can arrive late.
    if (saved == null) return;
    final state = jsonDecode(saved) as Map<String, dynamic>;
    final saving = prefs.setString(
      StudyPersistenceKeys.notificationState,
      jsonEncode({...state, ...data}),
    );
    FlutterForegroundTask.sendDataToTask(data);
    await saving;
  }

  Map<String, Object?> _timerStateData({
    required TimerMode mode,
    required bool isRunning,
    required PomodoroPhase? pomodoroPhase,
    required int seconds,
  }) =>
      {
        'mode': mode.index,
        'phase': pomodoroPhase?.index,
        'seconds': seconds,
        'isRunning': isRunning,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

  /// Stop the foreground service.
  Future<void> stopStudySession() async {
    try {
      await FlutterForegroundTask.stopService();
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StudyPersistenceKeys.notificationState);
    }
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

@visibleForTesting
int notificationElapsedSeconds({
  required DateTime now,
  required DateTime? startedAt,
  required int pausedSeconds,
}) {
  if (startedAt == null) return pausedSeconds;
  final elapsed = now.difference(startedAt).inSeconds;
  return elapsed < 0 ? 0 : elapsed;
}

/// Task handler for the foreground service.
class _StudySessionHandler extends TaskHandler {
  TimerMode _mode = TimerMode.normal;
  PomodoroPhase _phase = PomodoroPhase.focus;

  DateTime? _normalStartedAt;
  int _pausedSeconds = 0;
  late DateTime _pomodoroEndTime;

  bool _isRunning = false;
  bool _initialized = false;
  bool _receivedTimerState = false;

  String _studyingFormat = 'Studying - {duration}';
  String _focusRemainingFormat = 'Focus: {duration} remaining';
  String _breakRemainingFormat = 'Break: {duration} remaining';
  String _focusFinishedText = 'Focus Finished!';
  String _breakFinishedText = 'Break Finished!';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(StudyPersistenceKeys.notificationState);
    if (saved != null) {
      final state = jsonDecode(saved) as Map<String, dynamic>;
      _studyingFormat = state['studyingFormat'] as String? ?? _studyingFormat;
      _focusRemainingFormat =
          state['focusRemainingFormat'] as String? ?? _focusRemainingFormat;
      _breakRemainingFormat =
          state['breakRemainingFormat'] as String? ?? _breakRemainingFormat;
      _focusFinishedText =
          state['focusFinishedText'] as String? ?? _focusFinishedText;
      _breakFinishedText =
          state['breakFinishedText'] as String? ?? _breakFinishedText;

      // A live update may have arrived while the saved state was loading.
      if (!_receivedTimerState) _applyTimerState(state);
    }
    _initialized = true;
    if ((saved != null || _receivedTimerState) &&
        (_mode == TimerMode.normal || _isRunning)) {
      _updateNotification(DateTime.now());
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_isRunning) _updateNotification(timestamp);
  }

  void _updateNotification(DateTime now) {
    String notificationText;
    if (_mode == TimerMode.normal) {
      final seconds = notificationElapsedSeconds(
        now: now,
        startedAt: _normalStartedAt,
        pausedSeconds: _pausedSeconds,
      );
      final durationText = Formatters.formatDuration(seconds);
      notificationText = _studyingFormat.replaceAll('{duration}', durationText);
    } else {
      final remainingSeconds = _pomodoroEndTime.difference(now).inSeconds;
      if (remainingSeconds <= 0) {
        notificationText = _phase == PomodoroPhase.focus
            ? _focusFinishedText
            : _breakFinishedText;
      } else {
        final durationText = Formatters.formatDuration(remainingSeconds);
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
    if (data is! Map<String, dynamic> || !data.containsKey('mode')) return;
    _receivedTimerState = true;
    _applyTimerState(data);
    if (_initialized && (_mode == TimerMode.normal || _isRunning)) {
      _updateNotification(DateTime.now());
    }
  }

  void _applyTimerState(Map<String, dynamic> data) {
    _mode = TimerMode.values[data['mode'] as int];
    final phaseIndex = data['phase'] as int?;
    _phase = phaseIndex == null
        ? PomodoroPhase.focus
        : PomodoroPhase.values[phaseIndex];
    _isRunning = data['isRunning'] as bool;
    final duration = Duration(seconds: data['seconds'] as int);
    final reportedAt =
        DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
    if (_mode == TimerMode.normal) {
      _pausedSeconds = duration.inSeconds;
      _normalStartedAt = _isRunning ? reportedAt.subtract(duration) : null;
    } else {
      _pomodoroEndTime = reportedAt.add(duration);
    }
  }
}
