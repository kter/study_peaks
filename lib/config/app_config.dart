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

  // Private constructor to prevent instantiation
  const AppConfig._();

  /// Factory for future environment variable support.
  ///
  /// Currently returns default values, but can be extended to read from
  /// environment variables or a configuration file.
  factory AppConfig.fromEnvironment() => const AppConfig._();
}
