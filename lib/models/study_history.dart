import 'study_session.dart';

/// A civil date label, independent of the viewer's offset.
DateTime civilDate(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

enum StudyHistoryPeriod {
  week,
  month;

  DateTime start(DateTime containing) => switch (this) {
        week => civilDate(containing)
            .subtract(Duration(days: containing.weekday - 1)),
        month => DateTime.utc(containing.year, containing.month),
      };

  DateTime shift(DateTime containing, int periods) {
    final first = start(containing);
    return switch (this) {
      week => first.add(Duration(days: 7 * periods)),
      month => DateTime.utc(first.year, first.month + periods),
    };
  }
}

/// Completed records for one owner, aggregated from a single database read.
class StudyHistory {
  StudyHistory(List<StudySession> sessions) : hasRecords = sessions.isNotEmpty {
    for (final session in sessions) {
      for (final entry in session.dailySeconds.entries) {
        _dailySeconds.update(entry.key, (seconds) => seconds + entry.value,
            ifAbsent: () => entry.value);
      }
    }
  }

  final bool hasRecords;
  final _dailySeconds = <DateTime, int>{};

  int get totalSeconds =>
      _dailySeconds.values.fold(0, (sum, seconds) => sum + seconds);

  int secondsOn(DateTime day) => _dailySeconds[civilDate(day)] ?? 0;

  /// Inclusive start, exclusive end. Includes zero days.
  Map<DateTime, int> daysBetween(DateTime start, DateTime end) {
    final first = civilDate(start);
    final last = civilDate(end);
    if (last.isBefore(first)) throw ArgumentError('Invalid date range');
    return {
      for (var day = first;
          day.isBefore(last);
          day = day.add(const Duration(days: 1)))
        day: _dailySeconds[day] ?? 0,
    };
  }

  int secondsIn(StudyHistoryPeriod period, DateTime containing) =>
      daysIn(period, containing)
          .values
          .fold(0, (sum, seconds) => sum + seconds);

  Map<DateTime, int> daysIn(StudyHistoryPeriod period, DateTime containing) =>
      daysBetween(period.start(containing), period.shift(containing, 1));
}
