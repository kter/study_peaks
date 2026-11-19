import 'package:flutter/services.dart' show appFlavor;

/// Centralized application configuration.
///
/// Contains all magic numbers and strings that were previously scattered
/// throughout the codebase, making configuration changes easier.
abstract final class AppConfig {
  // Authentication Configuration
  static const Duration signInTimeout = Duration(seconds: 30);

  // API設定
  static const Duration apiRequestTimeout = Duration(seconds: 8);
  static const Duration apiMutationTimeout = Duration(seconds: 15);
  static const int apiMaxAttempts = 3;
  static const List<Duration> apiRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  static String get apiBaseUrl => apiBaseUrlForFlavor(appFlavor);

  static String apiBaseUrlForFlavor(String? flavor) => flavor == 'dev'
      ? 'https://study-peaks-api-dev-opjqzrfbbq-an.a.run.app/v1'
      : 'https://study-peaks-api-prd-ozokydui6a-an.a.run.app/v1';

  // タイマー設定
  static const int pomodoroFocusDurationMinutes = 25;
  static const int pomodoroBreakDurationMinutes = 5;

  // セッション同期
  static const int sessionSyncIntervalMinutes = 5;

  // 席データ更新間隔（他ユーザーの変更を反映するため）
  static const int seatRefreshIntervalSeconds = 60;

  // Notification Configuration
  static const String notificationChannelId = 'study_peaks_session';
  static const String notificationChannelName = 'Study Session';
  static const String notificationChannelDescription = 'Shows your current study session';
  static const String notificationIconRes = '@drawable/ic_notification_silhouette';
  static const String notificationIconMetaDataName = 
      'com.pravera.flutter_foreground_task.notification.common.icon';

  // Retry Configuration
  static const int maxRetries = 5;
  static const List<Duration> retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];
}
