/// Centralized application configuration.
///
/// Contains all magic numbers and strings that were previously scattered
/// throughout the codebase, making configuration changes easier.
class AppConfig {
  // API設定
  static const String apiBaseUrl =
      'https://study-peaks-api-prd-ozokydui6a-an.a.run.app/v1';

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

  // Private constructor to prevent instantiation
  const AppConfig._();

  /// Factory for future environment variable support.
  ///
  /// Currently returns default values, but can be extended to read from
  /// environment variables or a configuration file.
  factory AppConfig.fromEnvironment() => const AppConfig._();
}
