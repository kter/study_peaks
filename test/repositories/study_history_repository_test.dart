import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' hide equals;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';

void main() {
  late StudyHistoryRepository repository;

  setUpAll(() {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'study_history.db');
    await deleteDatabase(path);
    
    repository = StudyHistoryRepository();
  });

  test('Save session and retrieve daily total', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Save a session for today
    final session1 = StudySession(
      roomId: 'test_room',
      startTime: now.subtract(const Duration(minutes: 30)),
      durationSeconds: 1800, // 30 mins
    );
    await repository.saveSession(session1);

    // Save another session for today
    final session2 = StudySession(
      roomId: 'test_room',
      startTime: now.subtract(const Duration(minutes: 10)),
      durationSeconds: 600, // 10 mins
    );
    await repository.saveSession(session2);
    
    // Get daily totals
    final dailyTotals = await repository.getDailyStudyTime(days: 7);
    
    // Check if today has correct total (1800 + 600 = 2400)
    expect(dailyTotals[today], equals(2400));
    
    // Get total study time
    final totalTime = await repository.getTotalStudyTime();
    expect(totalTime, equals(2400));
  });
}
