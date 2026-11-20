import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:study_peaks/models/study_history.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/models/weekly_study_goals.dart';
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

  test('splitting a focus interval at midnight preserves its whole second', () {
    final session = record(
      'leap-day',
      '2028-02-29T23:59:59.999500Z',
      '2028-03-01T00:00:00.999900Z',
    );

    expect(session.durationSeconds, 1);
    expect(session.dailySeconds[DateTime.utc(2028, 3, 1)], 1);
    expect(StudyHistory([session]).totalSeconds, 1);
  });

  test('empty history returns complete leap month of zeros', () async {
    final days = await repository.getMonth(
        ownerId: owner, containing: DateTime(2028, 2));
    expect(days.length, 29);
    expect(days.values.toSet(), {0});
    expect(await repository.getTotalStudyTime(ownerId: owner), 0);
  });

  Future<WeeklyStudyGoals> loadGoals(DateTime today, [String user = owner]) =>
      repository.observeWeeklyGoals(ownerId: user, today: today);

  test('weekly goals carry forward, preserve earlier weeks and isolate owners',
      () async {
    final firstMonday = DateTime(2026, 12, 28);
    final thursday = DateTime(2026, 12, 31);
    final sunday = DateTime(2027, 1, 3);
    final nextMonday = DateTime(2027, 1, 4);
    final thirdMonday = DateTime(2027, 1, 11);
    final fourthMonday = DateTime(2027, 1, 18);
    final fifthMonday = DateTime(2027, 1, 25);
    final earlierSunday = DateTime(2026, 12, 27);

    expect((await loadGoals(thursday)).minutesInWeek(thursday), isNull);
    await repository.saveWeeklyGoal(
        ownerId: owner, today: thursday, minutes: 600);
    expect((await loadGoals(thursday)).minutesInWeek(firstMonday), 600);
    await repository.saveWeeklyGoal(
        ownerId: owner, today: sunday, minutes: 615);
    final goals = await loadGoals(nextMonday);
    expect(goals.minutesInWeek(earlierSunday), isNull);
    expect(goals.minutesInWeek(firstMonday), 615);
    expect(goals.minutesInWeek(nextMonday), 615);

    await repository.saveWeeklyGoal(
        ownerId: owner, today: thirdMonday, minutes: 300);
    await repository.saveWeeklyGoal(
        ownerId: owner, today: fourthMonday, minutes: null);
    await repository.saveWeeklyGoal(
        ownerId: 'user:A', today: thirdMonday, minutes: 60);
    await repository.saveWeeklyGoal(
        ownerId: 'user:B', today: thirdMonday, minutes: 120);
    final updated = await loadGoals(fourthMonday);
    expect(updated.minutesInWeek(sunday), 615);
    expect(updated.minutesInWeek(nextMonday), 615);
    expect(updated.minutesInWeek(thirdMonday), 300);
    expect(updated.minutesInWeek(fourthMonday), isNull);
    expect(updated.minutesInWeek(fifthMonday), isNull);
    expect((await loadGoals(thirdMonday, 'user:A')).minutesInWeek(thirdMonday),
        60);
    expect((await loadGoals(thirdMonday, 'user:B')).minutesInWeek(thirdMonday),
        120);
  });

  test('rejects invalid weekly goals without overwriting the saved goal',
      () async {
    final today = DateTime(2027, 1, 1);
    await repository.saveWeeklyGoal(
        ownerId: owner, today: today, minutes: 10080);
    for (final invalid in [-15, 0, 14, 16, 10095]) {
      await expectLater(
        repository.saveWeeklyGoal(
            ownerId: owner, today: today, minutes: invalid),
        throwsArgumentError,
      );
    }
    await expectLater(
      repository.saveWeeklyGoal(
          ownerId: StudySession.legacyOwner, today: today, minutes: 15),
      throwsArgumentError,
    );
    expect((await loadGoals(today)).minutesInWeek(today), 10080);
  });

  test('a week stays read-only after the device date moves backward', () async {
    final sunday = DateTime(2027, 1, 3);
    final monday = DateTime(2027, 1, 4);
    await repository.saveWeeklyGoal(
        ownerId: owner, today: sunday, minutes: 600);
    final nextWeek = await loadGoals(monday);
    expect(nextWeek.latestObservedWeek, civilDate(monday));
    expect(nextWeek.minutesInWeek(monday), 600);

    for (final minutes in [300, null]) {
      expect(
          await repository.saveWeeklyGoal(
              ownerId: owner, today: sunday, minutes: minutes),
          isFalse);
    }
    final rollback = await loadGoals(sunday);
    expect(rollback.latestObservedWeek, civilDate(monday));
    expect(rollback.minutesInWeek(sunday), 600);
    expect(rollback.minutesInWeek(monday), 600);
    expect(
        await repository.saveWeeklyGoal(
            ownerId: 'user:A', today: sunday, minutes: 300),
        isTrue);
    expect(
        await repository.saveWeeklyGoal(
            ownerId: owner, today: monday, minutes: null),
        isTrue);
    final corrected = await loadGoals(monday);
    expect(corrected.minutesInWeek(sunday), 600);
    expect(corrected.minutesInWeek(monday), isNull);
    expect(
        await repository.correctWeeklyGoalDate(
          ownerId: owner,
          today: sunday,
          expectedLatestWeek: civilDate(monday),
        ),
        isFalse);
  });

  test('clock correction removes only future goal settings for that owner',
      () async {
    final past = DateTime.utc(2026, 12, 21);
    final realToday = DateTime.utc(2026, 12, 30);
    final wrongDate = DateTime.utc(2027, 1, 4);
    await repository.saveWeeklyGoal(ownerId: owner, today: past, minutes: 600);
    await loadGoals(wrongDate);
    await repository.saveWeeklyGoal(
        ownerId: owner, today: wrongDate, minutes: 900);
    await repository.saveWeeklyGoal(
        ownerId: 'user:A', today: wrongDate, minutes: 300);
    expect(
        await repository.correctWeeklyGoalDate(
          ownerId: owner,
          today: realToday,
          expectedLatestWeek: DateTime.utc(2027, 1, 11),
        ),
        isFalse);
    expect(
        await repository.correctWeeklyGoalDate(
          ownerId: owner,
          today: realToday,
          expectedLatestWeek: wrongDate,
        ),
        isTrue);
    final corrected = await loadGoals(realToday);
    expect(corrected.latestObservedWeek, DateTime.utc(2026, 12, 28));
    expect(corrected.minutesInWeek(realToday), 600);
    expect(
        await repository.saveWeeklyGoal(
            ownerId: owner, today: realToday, minutes: 120),
        isTrue);
    final goals = await loadGoals(wrongDate);
    expect(goals.minutesInWeek(past), 600);
    expect(goals.minutesInWeek(wrongDate), 120);
    expect(
        (await loadGoals(wrongDate, 'user:A')).minutesInWeek(wrongDate), 300);
  });

  test('v2 upgrade preserves study records and goals survive reopening',
      () async {
    final path = '${await getDatabasesPath()}/weekly-goal-migration.db';
    await deleteDatabase(path);
    addTearDown(() => deleteDatabase(path));
    final old = await openDatabase(path, version: 2, onCreate: (d, _) async {
      await d.execute('''CREATE TABLE study_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT, room_id TEXT NOT NULL,
        start_time TEXT NOT NULL, duration_seconds INTEGER NOT NULL,
        session_id TEXT NOT NULL, owner_id TEXT NOT NULL, focus_intervals TEXT,
        UNIQUE(owner_id, session_id))''');
    });
    await old.insert(
        'study_sessions',
        record('existing', '2026-12-28T10:00:00Z', '2026-12-28T16:30:00Z')
            .toMap());
    await old.insert(
        'study_sessions',
        record('account-record', '2026-12-28T10:00:00Z',
                '2026-12-28T10:05:00Z',
                user: 'user:A')
            .toMap());
    await old.close();
    await db.close();

    db = await StudyHistoryRepository.open(path);
    repository = StudyHistoryRepository.withDatabase(db);
    final today = DateTime(2026, 12, 31);
    expect(await repository.getTotalStudyTime(ownerId: owner), 23400);
    final pending = await repository.pendingSyncSessions('user:A', limit: 20);
    expect(pending.single.sessionId, 'account-record');
    expect((await loadGoals(today)).minutesInWeek(today), isNull);
    await repository.saveWeeklyGoal(ownerId: owner, today: today, minutes: 600);
    await repository.saveWeeklyGoal(
        ownerId: owner, today: DateTime(2027, 1, 4), minutes: null);
    await db.close();

    db = await StudyHistoryRepository.open(path);
    repository = StudyHistoryRepository.withDatabase(db);
    final goals = await loadGoals(DateTime(2027, 1, 4));
    expect(goals.minutesInWeek(today), 600);
    expect(goals.minutesInWeek(DateTime(2027, 1, 4)), isNull);
    expect(await repository.getTotalStudyTime(ownerId: owner), 23400);
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
    final today = DateTime(2027, 1, 1);
    expect((await loadGoals(today)).minutesInWeek(today), isNull);
    expect(
        await repository.saveWeeklyGoal(
            ownerId: owner, today: today, minutes: 15),
        isTrue);
    expect((await loadGoals(today)).minutesInWeek(today), 15);
    addTearDown(() => deleteDatabase(path));
  });
}
