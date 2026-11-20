import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
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
  Future<void> _pendingOperation = Future.value();
  final _sessionTaps = StreamController<void>.broadcast();

  Stream<void> get sessionTaps => _sessionTaps.stream;

  Future<void> _serialize(Future<void> Function() run) {
    _pendingOperation =
        _pendingOperation.then((_) => run()).catchError((Object error) {
      debugPrint(
          'Could not update the study notification: ${error.runtimeType}');
    });
    return _pendingOperation;
  }

  /// Initialize the notification service.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _setupLocalNotifications();
    _setupForegroundTask();
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback((data) {
      if (data == _openStudySession) _sessionTaps.add(null);
    });

    _isInitialized = true;
    debugPrint('📢 NotificationService initialized');
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings(AppConfig.notificationIconRes);
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
        eventAction:
            ForegroundTaskEventAction.repeat(1000), // Update every second
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
        final result =
            await FlutterForegroundTask.requestNotificationPermission();
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

  /// Starts or refreshes the notification for the active seat session.
  /// Resuming the app never prompts again for permission.
  Future<void> ensureStudySession({
    required String sessionId,
    required String roomName,
    required String locale,
    required bool requestPermissionIfNeeded,
    required bool Function() isCurrentSession,
    required TimerMode mode,
    required PomodoroPhase? pomodoroPhase,
    required bool isRunning,
    required bool waitingToStart,
    required int seconds,
  }) {
    final capturedAt = DateTime.now();
    return _serialize(() async {
      if (!_isInitialized || !isCurrentSession()) return;
      final granted = requestPermissionIfNeeded
          ? await requestPermission()
          : await FlutterForegroundTask.checkNotificationPermission() ==
              NotificationPermission.granted;
      if (!granted || !isCurrentSession()) return;

      final data = <String, Object?>{
        'sessionId': sessionId,
        'roomName': roomName,
        'locale': locale,
        ..._timerStateData(
          mode: mode,
          pomodoroPhase: pomodoroPhase,
          isRunning: isRunning,
          waitingToStart: waitingToStart,
          seconds: seconds,
          capturedAt: capturedAt,
        ),
      };
      final prefs = await SharedPreferences.getInstance();
      if (!isCurrentSession()) return;
      await prefs.setString(
          StudyPersistenceKeys.notificationState, jsonEncode(data));
      if (!isCurrentSession()) return;

      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.sendDataToTask(data);
      } else {
        final copy = studyNotificationCopy(data, DateTime.now());
        await FlutterForegroundTask.startService(
          notificationTitle: copy.title!,
          notificationText: copy.body,
          notificationIcon: const NotificationIcon(
            metaDataName: AppConfig.notificationIconMetaDataName,
          ),
          callback: _startCallback,
        );
      }
    });
  }

  /// Updates the snapshot consumed by the service's background isolate.
  Future<void> updateTimerState({
    String? sessionId,
    required TimerMode mode,
    required bool isRunning,
    bool waitingToStart = false,
    PomodoroPhase? pomodoroPhase,
    required int seconds,
  }) {
    final capturedAt = DateTime.now();
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(StudyPersistenceKeys.notificationState);
      if (saved == null) return;
      final state = jsonDecode(saved) as Map<String, dynamic>;
      if (state['sessionId'] != sessionId) return;
      final data = {
        ...state,
        ..._timerStateData(
          mode: mode,
          pomodoroPhase: pomodoroPhase,
          isRunning: isRunning,
          waitingToStart: waitingToStart,
          seconds: seconds,
          capturedAt: capturedAt,
        ),
      };
      await prefs.setString(
          StudyPersistenceKeys.notificationState, jsonEncode(data));
      FlutterForegroundTask.sendDataToTask(data);
    });
  }

  Map<String, Object?> _timerStateData({
    required TimerMode mode,
    required PomodoroPhase? pomodoroPhase,
    required bool isRunning,
    required bool waitingToStart,
    required int seconds,
    required DateTime capturedAt,
  }) =>
      {
        'mode': mode.index,
        'phase': pomodoroPhase?.index,
        'seconds': seconds,
        'isRunning': isRunning,
        'waitingToStart': waitingToStart,
        'timestamp': capturedAt.millisecondsSinceEpoch,
      };

  Future<void> stopStudySession() => _serialize(() async {
        try {
          await FlutterForegroundTask.stopService();
        } finally {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(StudyPersistenceKeys.notificationState);
        }
      });

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

const _openStudySession = 'openStudySession';

@visibleForTesting
({String? title, String body}) studyNotificationCopy(
    Map<String, dynamic> state, DateTime now) {
  final locale =
      state['locale'] == 'ja' ? const Locale('ja') : const Locale('en');
  final l10n = lookupAppLocalizations(locale);
  final mode = TimerMode.values[state['mode'] as int];
  final phase = PomodoroPhase.values[state['phase'] as int? ?? 0];
  final isRunning = state['isRunning'] as bool;
  final waitingToStart = state['waitingToStart'] == true;
  final roomName = state['roomName'] as String?;
  final seconds = state['seconds'] as int;
  final timestamp =
      DateTime.fromMillisecondsSinceEpoch(state['timestamp'] as int);
  final onBreak =
      mode == TimerMode.pomodoro && phase == PomodoroPhase.shortBreak;
  final title = roomName == null
      ? null
      : isRunning && !onBreak
          ? l10n.notificationStudyingAt(roomName)
          : l10n.notificationSessionAt(roomName);
  final elapsed = now.difference(timestamp);
  final int shownSeconds;
  if (!isRunning) {
    shownSeconds = seconds;
  } else if (mode == TimerMode.normal) {
    shownSeconds = notificationElapsedSeconds(
      now: now,
      startedAt: timestamp.subtract(Duration(seconds: seconds)),
      pausedSeconds: seconds,
    );
  } else {
    shownSeconds = (seconds - elapsed.inSeconds).clamp(0, seconds);
  }
  final duration = Formatters.formatStudyDuration(shownSeconds, l10n);
  final body = switch ((mode, isRunning, waitingToStart, onBreak)) {
    (_, false, false, _) => l10n.notificationPaused(duration),
    (TimerMode.normal, false, true, _) => l10n.notificationTimerReady,
    (TimerMode.normal, _, _, _) => l10n.notificationStudying(duration),
    (_, false, true, true) => l10n.notificationBreakReady(duration),
    (_, false, true, false) => l10n.notificationFocusReady(duration),
    (_, true, _, true) => shownSeconds == 0
        ? l10n.notificationBreakFinished
        : l10n.notificationBreakRemaining(duration),
    (_, true, _, false) => shownSeconds == 0
        ? l10n.notificationFocusFinished
        : l10n.notificationFocusRemaining(duration),
  };
  return (title: title, body: body);
}

/// Task handler for the foreground service.
class _StudySessionHandler extends TaskHandler {
  Map<String, dynamic>? _state;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(StudyPersistenceKeys.notificationState);
    if (saved != null && _state == null) {
      _state = jsonDecode(saved) as Map<String, dynamic>;
      _updateNotification(DateTime.now());
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_state?['isRunning'] == true) _updateNotification(timestamp);
  }

  void _updateNotification(DateTime now) {
    final state = _state;
    if (state == null) return;
    final copy = studyNotificationCopy(state, now);
    FlutterForegroundTask.updateService(
      notificationTitle: copy.title,
      notificationText: copy.body,
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! Map<String, dynamic> || !data.containsKey('mode')) return;
    _state = data;
    _updateNotification(DateTime.now());
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
    FlutterForegroundTask.sendDataToMain(_openStudySession);
  }
}
