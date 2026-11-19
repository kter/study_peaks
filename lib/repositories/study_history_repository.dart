import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/study_session.dart';

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
      openDatabase(path, version: 2, onCreate: (db, _) async {
        await db.execute('''CREATE TABLE study_sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT, room_id TEXT NOT NULL,
        start_time TEXT NOT NULL, duration_seconds INTEGER NOT NULL,
        session_id TEXT NOT NULL, owner_id TEXT NOT NULL, focus_intervals TEXT,
        UNIQUE(owner_id, session_id))''');
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
      });

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

  static DateTime date(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  /// Inclusive start, exclusive end. Includes zero days; only completed records.
  Future<Map<DateTime, int>> getDailyTotals(
      {required String ownerId,
      required DateTime start,
      required DateTime end}) async {
    final first = date(start), last = date(end);
    if (last.isBefore(first)) throw ArgumentError('Invalid date range');
    final totals = <DateTime, int>{};
    for (var day = first;
        day.isBefore(last);
        day = day.add(const Duration(days: 1))) {
      totals[day] = 0;
    }
    for (final session in await getSessions(ownerId: ownerId)) {
      for (final entry in session.dailySeconds.entries) {
        if (totals.containsKey(entry.key)) {
          totals[entry.key] = totals[entry.key]! + entry.value;
        }
      }
    }
    return totals;
  }

  Future<Map<DateTime, int>> getDailyStudyTime(
      {required String ownerId, int days = 7, DateTime? now}) {
    if (days < 1) throw ArgumentError('days must be positive');
    final today = date(now ?? DateTime.now());
    return getDailyTotals(
        ownerId: ownerId,
        start: today.subtract(Duration(days: days - 1)),
        end: today.add(const Duration(days: 1)));
  }

  Future<int> getTodayStudyTime(
          {required String ownerId, DateTime? now}) async =>
      (await getDailyStudyTime(ownerId: ownerId, days: 1, now: now))
          .values
          .single;
  Future<Map<DateTime, int>> getWeek(
      {required String ownerId, required DateTime containing}) {
    final monday =
        date(containing).subtract(Duration(days: containing.weekday - 1));
    return getDailyTotals(
        ownerId: ownerId,
        start: monday,
        end: monday.add(const Duration(days: 7)));
  }

  Future<Map<DateTime, int>> getMonth(
          {required String ownerId, required DateTime containing}) =>
      getDailyTotals(
          ownerId: ownerId,
          start: DateTime.utc(containing.year, containing.month),
          end: DateTime.utc(containing.year, containing.month + 1));
  Future<int> getTotalStudyTime({required String ownerId}) async =>
      (await getSessions(ownerId: ownerId))
          .fold<int>(0, (sum, session) => sum + session.durationSeconds);
}
