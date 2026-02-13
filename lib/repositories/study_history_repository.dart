import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/study_session.dart';

/// Repository for managing local study history data.
class StudyHistoryRepository {
  static final StudyHistoryRepository _instance = StudyHistoryRepository._internal();
  factory StudyHistoryRepository() => _instance;
  StudyHistoryRepository._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'study_history.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          '''
          CREATE TABLE study_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            room_id TEXT NOT NULL,
            start_time TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL
          )
          ''',
        );
      },
    );
  }

  /// Save a completed study session.
  Future<void> saveSession(StudySession session) async {
    final db = await database;
    await db.insert(
      'study_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get total study time (in seconds) for each day in the last [days] days.
  /// Returns a map where key is DateTime (normalized to start of day) and value is total seconds.
  Future<Map<DateTime, int>> getDailyStudyTime({int days = 7}) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = startDate.toIso8601String().split('T')[0]; // YYYY-MM-DD

    // Query sessions from start date onwards
    final List<Map<String, dynamic>> maps = await db.query(
      'study_sessions',
      where: 'start_time >= ?',
      whereArgs: [startDateStr],
    );

    final Map<DateTime, int> dailyTotals = {};

    // Initialize map with 0 for all days in range
    for (int i = 0; i < days; i++) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      dailyTotals[date] = 0;
    }

    // Aggregate durations
    for (final map in maps) {
      final session = StudySession.fromMap(map);
      // Normalize to start of day (local time)
      final date = DateTime(
        session.startTime.year,
        session.startTime.month,
        session.startTime.day,
      );

      if (dailyTotals.containsKey(date)) {
        dailyTotals[date] = (dailyTotals[date] ?? 0) + session.durationSeconds;
      }
    }

    return dailyTotals;
  }
  
  /// Get total accumulated study time (all time).
  Future<int> getTotalStudyTime() async {
    final db = await database;
    final result = await db.rawQuery('SELECT SUM(duration_seconds) as total FROM study_sessions');
    if (result.isNotEmpty && result.first['total'] != null) {
      return result.first['total'] as int;
    }
    return 0;
  }
}
