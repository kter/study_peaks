import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:study_peaks/models/study_history.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';

void main() {
  late Database db;
  late StudyHistoryRepository repository;
  const owner = StudySession.guestOwner;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    db = await StudyHistoryRepository.open(inMemoryDatabasePath);
    repository = StudyHistoryRepository.withDatabase(db);
  });
  tearDown(() => db.close());

  StudySession record(String id, String start, String end,
      {String user = owner, int offset = 0}) {
    final a = DateTime.parse(start), b = DateTime.parse(end);
    return StudySession(
        sessionId: id,
        ownerId: user,
        roomId: 'fuji',
        startTime: a,
        durationSeconds: b.difference(a).inSeconds,
        intervals: [FocusInterval(start: a, end: b, offsetMinutes: offset)]);
  }

  test(
      'same identity replaces instead of double counting; owners remain isolated',
      () async {
    final a = record('same', '2026-11-19T10:00:00Z', '2026-11-19T10:30:00Z');
    await repository.saveSession(a);
    await repository.saveSession(a);
    await repository.saveSession(record(
        'same', '2026-11-19T10:00:00Z', '2026-11-19T11:00:00Z',
        user: 'user:A'));
    await repository.saveSession(record(
        'same', '2026-11-19T10:00:00Z', '2026-11-19T12:00:00Z',
        user: 'user:B'));
    expect(await repository.getTotalStudyTime(ownerId: owner), 1800);
    expect(await repository.getTotalStudyTime(ownerId: 'user:A'), 3600);
    expect(await repository.getTotalStudyTime(ownerId: 'user:B'), 7200);
    expect(await repository.getTotalStudyTime(ownerId: 'user:C'), 0);
  });

  test('multiple sessions, midnight, year/month/week boundaries and zero days',
      () async {
    await repository.saveSession(
        record('a', '2026-12-31T23:50:00Z', '2027-01-01T00:10:00Z'));
    await repository.saveSession(
        record('b', '2027-01-01T10:00:00Z', '2027-01-01T10:20:00Z'));
    final week = await repository.getWeek(
        ownerId: owner, containing: DateTime(2027, 1, 1));
    expect(week.length, 7);
    expect(week.keys.first, DateTime.utc(2026, 12, 28));
    expect(week[DateTime.utc(2026, 12, 31)], 600);
    expect(week[DateTime.utc(2027, 1, 1)], 1800);
    expect(week[DateTime.utc(2027, 1, 2)], 0);
    final month = await repository.getMonth(
        ownerId: owner, containing: DateTime(2027, 1));
    expect(month.length, 31);
    expect(month.values.reduce((a, b) => a + b), 1800);
    expect(
        await repository.getTodayStudyTime(
            ownerId: owner, now: DateTime(2027, 1, 1)),
        1800);
    expect(await repository.getTotalStudyTime(ownerId: owner), 2400);
  });

  test('dashboard totals and graph match the shared queries', () async {
    await repository.saveSession(
        record('older', '2026-12-01T10:00:00Z', '2026-12-01T10:15:00Z'));
    await repository.saveSession(
        record('midnight', '2026-12-31T23:59:30Z', '2027-01-01T00:01:00Z'));
    await repository.saveSession(record(
        'other', '2027-01-01T00:00:00Z', '2027-01-01T01:00:00Z',
        user: 'user:someone-else'));

    final now = DateTime(2027, 1, 1);
    final history = await repository.getHistory(ownerId: owner);
    final currentWeek = history.daysIn(StudyHistoryPeriod.week, now);
    final december =
        history.daysIn(StudyHistoryPeriod.month, DateTime(2026, 12));

    expect(
        currentWeek, await repository.getWeek(ownerId: owner, containing: now));
    expect(
        december,
        await repository.getMonth(
            ownerId: owner, containing: DateTime(2026, 12)));
    expect(december.values.last, 30);
    expect(december.values.skip(1).first, 0);
    expect(history.secondsOn(now),
        await repository.getTodayStudyTime(ownerId: owner, now: now));
    expect(history.secondsOn(now), 60);
    expect(history.secondsIn(StudyHistoryPeriod.week, now), 90);
    expect(history.totalSeconds,
        await repository.getTotalStudyTime(ownerId: owner));
    expect(history.totalSeconds, 990);
    expect(history.hasRecords, isTrue);
  });

  test('pause crossing midnight and breaks contain no focus seconds', () async {
    final session = StudySession(
        sessionId: 'paused',
        roomId: 'fuji',
        startTime: DateTime.utc(2026, 11, 19, 23),
        durationSeconds: 1800,
        intervals: [
          FocusInterval(
              start: DateTime.utc(2026, 11, 19, 23, 40),
              end: DateTime.utc(2026, 11, 19, 23, 50),
              offsetMinutes: 0),
          FocusInterval(
              start: DateTime.utc(2026, 11, 20, 0, 20),
              end: DateTime.utc(2026, 11, 20, 0, 40),
              offsetMinutes: 0),
        ]);
    await repository.saveSession(session);
    final days = await repository.getDailyTotals(
        ownerId: owner,
        start: DateTime(2026, 11, 19),
        end: DateTime(2026, 11, 21));
    expect(days.values.toList(), [600, 1200]);
  });

  test('offset stays fixed and subsecond rounding conserves total', () {
    final a = DateTime.parse('2026-12-31T14:59:59.500Z');
    final session = StudySession(
        roomId: 'fuji',
        startTime: a,
        durationSeconds: 1,
        intervals: [
          FocusInterval(
              start: a,
              end: a.add(const Duration(milliseconds: 1500)),
              offsetMinutes: 540)
        ]);
    expect(session.dailySeconds,
        {DateTime.utc(2026, 12, 31): 0, DateTime.utc(2027, 1, 1): 1});
    expect(StudySession.fromMap(session.toMap()).dailySeconds,
        session.dailySeconds);
  });

  test('empty history returns complete leap month of zeros', () async {
    final days = await repository.getMonth(
        ownerId: owner, containing: DateTime(2028, 2));
    expect(days.length, 29);
    expect(days.values.toSet(), {0});
    expect(await repository.getTotalStudyTime(ownerId: owner), 0);
  });

  test('v1 migration retains rows, unknown ownership and start-day allocation',
      () async {
    await db.close();
    // Named temporary database ensures onUpgrade runs against a real v1 file.
    final path = '${await getDatabasesPath()}/issue3-migration.db';
    await deleteDatabase(path);
    final old = await openDatabase(path, version: 1, onCreate: (d, _) async {
      await d.execute(
          'CREATE TABLE study_sessions(id INTEGER PRIMARY KEY AUTOINCREMENT, room_id TEXT NOT NULL, start_time TEXT NOT NULL, duration_seconds INTEGER NOT NULL)');
    });
    await old.insert('study_sessions', {
      'room_id': 'fuji',
      'start_time': '2026-12-31T23:50:00',
      'duration_seconds': 1800
    });
    await old.close();
    db = await StudyHistoryRepository.open(path);
    repository = StudyHistoryRepository.withDatabase(db);
    expect(await repository.getTotalStudyTime(ownerId: owner), 0);
    final records =
        await repository.getSessions(ownerId: StudySession.legacyOwner);
    expect(records.single.sessionId, 'legacy-1');
    expect(records.single.intervals, isNull);
    expect(records.single.dailySeconds, {DateTime.utc(2026, 12, 31): 1800});
    await repository.saveSession(records.single);
    expect(
        await repository.getTotalStudyTime(ownerId: StudySession.legacyOwner),
        1800);
    addTearDown(() => deleteDatabase(path));
  });
}
