import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../config/app_config.dart';
import '../utils/formatters.dart';

/// Service for managing foreground notifications during study sessions.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

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
        eventAction: ForegroundTaskEventAction.repeat(60000), // Update every minute
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
  }) async {
    debugPrint('📢 Starting foreground service: $notificationTitle');
    
    // Request permission first (Android 13+)
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      debugPrint('📢 Notification permission denied, cannot start foreground service');
      return;
    }
    
    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        notificationIcon: const NotificationIcon(
          metaDataName: AppConfig.notificationIconMetaDataName,
        ),
        callback: _startCallback,
      );
      debugPrint('📢 Foreground service start result: $result');
    } catch (e) {
      debugPrint('📢 Error starting foreground service: $e');
    }
  }

  /// Update the notification with current duration.
  /// 
  /// [notificationText] - Localized text, e.g. "Studying - 5m"
  Future<void> updateSessionDuration(String notificationText) async {
    await FlutterForegroundTask.updateService(
      notificationText: notificationText,
    );
  }

  /// Stop the foreground service.
  Future<void> stopStudySession() async {
    await FlutterForegroundTask.stopService();
  }

  /// Check if the foreground service is running.
  Future<bool> isRunning() async {
    return await FlutterForegroundTask.isRunningService;
  }
}

// Top-level callback for foreground task
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_StudySessionHandler());
}

/// Task handler for the foreground service.
class _StudySessionHandler extends TaskHandler {
  int _elapsedSeconds = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _elapsedSeconds = 0;
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _elapsedSeconds += 60; // Add 1 minute

    final durationText = Formatters.formatDuration(_elapsedSeconds);

    FlutterForegroundTask.updateService(
      notificationText: 'Studying - $durationText',
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Cleanup if needed
  }

  @override
  void onReceiveData(Object data) {
    // Handle data from main isolate
  }
}
