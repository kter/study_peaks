import 'study_history.dart';

/// Goal changes take effect for a whole civil week and carry forward.
class WeeklyStudyGoals {
  WeeklyStudyGoals(Map<DateTime, int?> goals)
      : _weeks = goals.entries.toList()..sort((a, b) => b.key.compareTo(a.key));

  static const minMinutes = 15;
  static const stepMinutes = 15;
  static const maxMinutes = 7 * 24 * 60;

  /// Newest first, keyed by Monday date labels. Null is an unset goal.
  final List<MapEntry<DateTime, int?>> _weeks;

  DateTime? get latestObservedWeek => _weeks.firstOrNull?.key;

  // UTC-12 to UTC+14 is the largest civil clock shift from changing zones.
  static bool canCorrectDate(DateTime now, DateTime latestWeek) {
    final civilTime = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
    return latestWeek.difference(civilTime) > const Duration(hours: 26);
  }

  static bool isValidMinutes(int minutes) =>
      minutes >= minMinutes &&
      minutes <= maxMinutes &&
      minutes % stepMinutes == 0;

  int? minutesInWeek(DateTime containing) {
    final week = StudyHistoryPeriod.week.start(containing);
    for (final entry in _weeks) {
      if (!entry.key.isAfter(week)) return entry.value;
    }
    return null;
  }
}

class WeeklyGoalProgress {
  const WeeklyGoalProgress(this.goalMinutes, this.actualSeconds);

  final int? goalMinutes;
  final int actualSeconds;

  int get targetSeconds => (goalMinutes ?? 0) * 60;
  bool get hasGoal => targetSeconds > 0;

  int get percent => hasGoal ? actualSeconds * 100 ~/ targetSeconds : 0;
  int get remainingSeconds =>
      hasGoal ? (targetSeconds - actualSeconds).clamp(0, targetSeconds) : 0;
  double get fraction =>
      hasGoal ? (actualSeconds / targetSeconds).clamp(0.0, 1.0) : 0.0;
}
