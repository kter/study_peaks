import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/study_history.dart';
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

  Future<StudyHistory> getHistory({required String ownerId}) async =>
      StudyHistory(await getSessions(ownerId: ownerId));

  /// Inclusive start, exclusive end. Includes zero days; only completed records.
  Future<Map<DateTime, int>> getDailyTotals(
          {required String ownerId,
          required DateTime start,
          required DateTime end}) async =>
      (await getHistory(ownerId: ownerId)).daysBetween(start, end);

  Future<Map<DateTime, int>> getDailyStudyTime(
      {required String ownerId, int days = 7, DateTime? now}) {
    if (days < 1) throw ArgumentError('days must be positive');
    final today = civilDate(now ?? DateTime.now());
    return getDailyTotals(
        ownerId: ownerId,
        start: today.subtract(Duration(days: days - 1)),
        end: today.add(const Duration(days: 1)));
  }

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
