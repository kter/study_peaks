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
}
