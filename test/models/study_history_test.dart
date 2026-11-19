import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/models/study_history.dart';
import 'package:study_peaks/models/study_session.dart';

void main() {
  StudySession record(String id, String start, String end) {
    final startTime = DateTime.parse(start);
    final endTime = DateTime.parse(end);
    return StudySession(
      sessionId: id,
      roomId: 'fuji',
      startTime: startTime,
      durationSeconds: endTime.difference(startTime).inSeconds,
      intervals: [
        FocusInterval(start: startTime, end: endTime, offsetMinutes: 0),
      ],
    );
  }

  test('navigation ceiling is the later of today and the last study day', () {
    final studyDay = DateTime.utc(2027, 1, 5);
    final history = StudyHistory([
      record('later', '2027-01-05T10:00:00Z', '2027-01-05T10:00:01Z'),
    ]);
    expect(history.lastNavigableDay(DateTime(2027, 1, 4, 12)), studyDay);
    expect(history.lastNavigableDay(DateTime(2027, 1, 6, 12)),
        DateTime.utc(2027, 1, 6));
    expect(StudyHistory([]).lastNavigableDay(DateTime(2027, 1, 4, 12)),
        DateTime.utc(2027, 1, 4));
  });

  test('clamps only anchors in a period beyond the navigation ceiling', () {
    const week = StudyHistoryPeriod.week;
    const month = StudyHistoryPeriod.month;
    final ceiling = DateTime.utc(2027, 1, 5);
    final past = DateTime.utc(2026, 12, 28);
    expect(StudyHistory.clampAnchor(week, past, ceiling), past);
    expect(StudyHistory.clampAnchor(week, DateTime(2027, 1, 10), ceiling),
        DateTime.utc(2027, 1, 10));
    expect(StudyHistory.clampAnchor(week, DateTime(2027, 1, 11), ceiling),
        ceiling);
    expect(StudyHistory.clampAnchor(month, DateTime(2027, 1, 31), ceiling),
        DateTime.utc(2027, 1, 31));
    expect(StudyHistory.clampAnchor(month, DateTime(2027, 2), ceiling), ceiling);
  });

  test('counts each positive study day once within the civil month', () {
    final history = StudyHistory([
      record('leap', '2028-02-29T10:00:00Z', '2028-02-29T10:00:01Z'),
      record('same-day', '2028-02-29T12:00:00Z', '2028-02-29T12:00:01Z'),
      record('zero', '2028-02-01T10:00:00Z', '2028-02-01T10:00:00Z'),
      record('next', '2028-03-01T10:00:00Z', '2028-03-01T10:00:01Z'),
    ]);
    expect(history.studyDaysIn(DateTime(2028, 2, 15)), 1);
    expect(history.studyDaysIn(DateTime(2028, 1)), 0);
  });

  test('period emptiness depends on seconds in the requested period', () {
    const week = StudyHistoryPeriod.week;
    const month = StudyHistoryPeriod.month;
    final history = StudyHistory([
      record('positive', '2027-01-04T10:00:00Z', '2027-01-04T10:00:01Z'),
      record('zero', '2027-02-01T10:00:00Z', '2027-02-01T10:00:00Z'),
    ]);
    expect(history.isPeriodEmpty(week, DateTime(2027, 1, 10)), isFalse);
    expect(history.isPeriodEmpty(week, DateTime(2027, 1, 11)), isTrue);
    expect(history.isPeriodEmpty(month, DateTime(2027, 1, 11)), isFalse);
    expect(history.isPeriodEmpty(month, DateTime(2027, 2)), isTrue);
  });
}
