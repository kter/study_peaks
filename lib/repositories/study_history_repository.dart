import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/study_history.dart';
import '../models/study_session.dart';
import '../models/weekly_study_goals.dart';

class StudyHistoryRepository {
  static final StudyHistoryRepository _instance =
      StudyHistoryRepository._internal();
  factory StudyHistoryRepository() => _instance;
  StudyHistoryRepository._internal();

  /// Tests use an isolated database, including real v1 upgrade tests.
  StudyHistoryRepository.withDatabase(Database database)
      : _databaseFuture = Future.value(database);
  Future<Database>? _databaseFuture;
  Future<Database> get database =>
      _databaseFuture ??= _open().catchError((Object error) {
        _databaseFuture = null;
        throw error;
      });

  static Future<Database> open(String path) =>
      openDatabase(path, version: 3, onCreate: (db, _) async {
        await db.execute('''CREATE TABLE study_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT, room_id TEXT NOT NULL,
        start_time TEXT NOT NULL, duration_seconds INTEGER NOT NULL,
        session_id TEXT NOT NULL, owner_id TEXT NOT NULL, focus_intervals TEXT,
        UNIQUE(owner_id, session_id))''');
        await _createWeeklyGoals(db);
      }, onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db
              .execute('ALTER TABLE study_sessions ADD COLUMN session_id TEXT');
          await db.execute(
              "ALTER TABLE study_sessions ADD COLUMN owner_id TEXT NOT NULL DEFAULT 'legacy:unknown'");
          await db.execute(
              'ALTER TABLE study_sessions ADD COLUMN focus_intervals TEXT');
          await db.execute(
              "UPDATE study_sessions SET session_id = 'legacy-' || id");
          await db.execute(
              'CREATE UNIQUE INDEX session_identity ON study_sessions(owner_id, session_id)');
        }
        if (oldVersion < 3) await _createWeeklyGoals(db);
      });

  static Future<void> _createWeeklyGoals(Database db) =>
      db.execute('''CREATE TABLE weekly_study_goals(
        owner_id TEXT NOT NULL,
        week_start INTEGER NOT NULL,
        goal_minutes INTEGER CHECK (goal_minutes > 0),
        PRIMARY KEY (owner_id, week_start))''');

  Future<Database> _open() async =>
      open(join(await getDatabasesPath(), 'study_history.db'));

  Future<void> saveSession(StudySession session) async {
    final db = await database;
    await db.insert('study_sessions', session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<StudySession>> getSessions({required String ownerId}) async {
    final db = await database;
    return (await db.query('study_sessions',
            where: 'owner_id = ?', whereArgs: [ownerId]))
        .map(StudySession.fromMap)
        .toList();
  }

  Future<StudyHistory> getHistory({required String ownerId}) async =>
      StudyHistory(await getSessions(ownerId: ownerId));

  /// Records the newest week seen by this owner with its inherited goal.
  Future<WeeklyStudyGoals> observeWeeklyGoals({
    required String ownerId,
    required DateTime today,
  }) async {
    _validateGoalOwner(ownerId);
    final week = StudyHistoryPeriod.week.start(today);
    final db = await database;
    return db.transaction((txn) async {
      final rows = await _weeklyGoalRows(txn, ownerId);
      final latest = rows.firstOrNull;
      final newWeek = latest == null ||
          week.millisecondsSinceEpoch > (latest['week_start'] as int);
      final inherited = latest?['goal_minutes'] as int?;
      if (newWeek) await _writeWeeklyGoal(txn, ownerId, week, inherited);

      return WeeklyStudyGoals({
        if (newWeek) week: inherited,
        for (final row in rows)
          DateTime.fromMillisecondsSinceEpoch(row['week_start'] as int,
              isUtc: true): row['goal_minutes'] as int?,
      });
    });
  }

  /// Removes future rows for a confirmed clock correction outside timezone range.
  Future<bool> correctWeeklyGoalDate({
    required String ownerId,
    required DateTime today,
    required DateTime expectedLatestWeek,
  }) async {
    _validateGoalOwner(ownerId);
    final week = StudyHistoryPeriod.week.start(today);
    if (!WeeklyStudyGoals.canCorrectDate(today, expectedLatestWeek)) {
      return false;
    }
    final db = await database;
    return db.transaction((txn) async {
      final rows = await _weeklyGoalRows(txn, ownerId, limit: 1);
      if (rows.firstOrNull?['week_start'] !=
          expectedLatestWeek.millisecondsSinceEpoch) {
        return false;
      }
      await txn.delete(
        'weekly_study_goals',
        where: 'owner_id = ? AND week_start > ?',
        whereArgs: [ownerId, week.millisecondsSinceEpoch],
      );
      return true;
    });
  }

  /// Null clears the goal. Returns false if a later week has already been seen.
  Future<bool> saveWeeklyGoal({
    required String ownerId,
    required DateTime today,
    required int? minutes,
  }) async {
    _validateGoalOwner(ownerId);
    if (minutes != null && !WeeklyStudyGoals.isValidMinutes(minutes)) {
      throw ArgumentError.value(minutes, 'minutes');
    }
    final weekStart = StudyHistoryPeriod.week.start(today);
    final db = await database;
    return db.transaction((txn) async {
      final rows = await _weeklyGoalRows(txn, ownerId, limit: 1);
      if (rows.isNotEmpty &&
          weekStart.millisecondsSinceEpoch <
              (rows.single['week_start'] as int)) {
        return false;
      }
      await _writeWeeklyGoal(txn, ownerId, weekStart, minutes);
      return true;
    });
  }

  void _validateGoalOwner(String ownerId) {
    if (ownerId == StudySession.legacyOwner) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
  }

  Future<List<Map<String, Object?>>> _weeklyGoalRows(
    Transaction txn,
    String ownerId, {
    int? limit,
  }) =>
      txn.query(
        'weekly_study_goals',
        columns: ['week_start', 'goal_minutes'],
        where: 'owner_id = ?',
        whereArgs: [ownerId],
        orderBy: 'week_start DESC',
        limit: limit,
      );

  Future<void> _writeWeeklyGoal(
    Transaction txn,
    String ownerId,
    DateTime weekStart,
    int? minutes,
  ) async {
    await txn.insert(
      'weekly_study_goals',
      {
        'owner_id': ownerId,
        'week_start': weekStart.millisecondsSinceEpoch,
        'goal_minutes': minutes,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Inclusive start, exclusive end. Includes zero days; only completed records.
  Future<Map<DateTime, int>> getDailyTotals(
          {required String ownerId,
          required DateTime start,
          required DateTime end}) async =>
      (await getHistory(ownerId: ownerId)).daysBetween(start, end);

  Future<int> getTodayStudyTime(
      {required String ownerId, DateTime? now}) async {
    final today = now ?? DateTime.now();
    return (await getHistory(ownerId: ownerId)).secondsOn(today);
  }

  Future<Map<DateTime, int>> getWeek(
          {required String ownerId, required DateTime containing}) =>
      _getPeriod(ownerId, StudyHistoryPeriod.week, containing);

  Future<Map<DateTime, int>> getMonth(
          {required String ownerId, required DateTime containing}) =>
      _getPeriod(ownerId, StudyHistoryPeriod.month, containing);

  Future<Map<DateTime, int>> _getPeriod(String ownerId,
          StudyHistoryPeriod period, DateTime containing) async =>
      (await getHistory(ownerId: ownerId)).daysIn(period, containing);

  Future<int> getTotalStudyTime({required String ownerId}) async =>
      (await getHistory(ownerId: ownerId)).totalSeconds;
}
