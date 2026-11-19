import '../l10n/app_localizations.dart';

/// Helper for formatting durations and times.
class Formatters {
  Formatters._();

  /// Format duration into a human-readable string.
  ///
  /// Example:
  /// - 3600 -> "1h 0m"
  /// - 3660 -> "1h 1m"
  /// - 59   -> "0m"
  /// - 60   -> "1m"
  static String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Display completed seconds without rounding short sessions down to zero.
  static String formatStudyDuration(int seconds, AppLocalizations l10n) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final remainingSeconds = seconds.remainder(60);

    if (hours > 0) {
      return l10n.historyDurationHours(hours, minutes, remainingSeconds);
    }
    if (minutes > 0 && remainingSeconds > 0) {
      return l10n.historyDurationMinutes(minutes, remainingSeconds);
    }
    return minutes > 0
        ? l10n.historyMinutes(minutes)
        : l10n.historySeconds(remainingSeconds);
  }
}
