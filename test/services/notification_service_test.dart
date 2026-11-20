import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/models/timer_mode.dart';
import 'package:study_peaks/services/notification_service.dart';
import 'package:study_peaks/services/study_persistence_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final reportedAt = DateTime.utc(2026, 11, 19);

  test('stopping clears saved notification state despite a late timer update',
      () async {
    const key = StudyPersistenceKeys.notificationState;
    SharedPreferences.setMockInitialValues({key: '{"seconds":30}'});
    final prefs = await SharedPreferences.getInstance();
    final notifications = NotificationService();

    await notifications.stopStudySession();
    expect(prefs.containsKey(key), isFalse);

    await notifications.updateTimerState(
      mode: TimerMode.normal,
      isRunning: false,
      seconds: 30,
    );
    expect(prefs.containsKey(key), isFalse);
  });

  test('notification copy uses seconds, locale, and the stopped state', () {
    final state = <String, dynamic>{
      'roomName': 'Mt. Fuji',
      'locale': 'ja',
      'mode': TimerMode.pomodoro.index,
      'phase': PomodoroPhase.focus.index,
      'isRunning': true,
      'seconds': 30,
      'timestamp': reportedAt.millisecondsSinceEpoch,
    };
    final later = reportedAt.add(const Duration(seconds: 12));

    expect(studyNotificationCopy(state, later).body, '集中: 残り18秒');
    state['isRunning'] = false;
    expect(studyNotificationCopy(state, later).body, '一時停止中（30秒）');
    state['waitingToStart'] = true;
    state['phase'] = PomodoroPhase.shortBreak.index;
    state['locale'] = 'en';
    state['seconds'] = 300;
    expect(studyNotificationCopy(state, later).body, 'Ready for a break · 5m');
  });

  test('elapsed notification time includes time between delayed events', () {
    final startedAt = reportedAt.subtract(const Duration(seconds: 12));

    expect(
      notificationElapsedSeconds(
        now: reportedAt,
        startedAt: startedAt,
        pausedSeconds: 12,
      ),
      12,
    );
    expect(
      notificationElapsedSeconds(
        now: reportedAt.add(const Duration(seconds: 75)),
        startedAt: startedAt,
        pausedSeconds: 12,
      ),
      87,
    );
  });

  test('elapsed notification time stays at the reported value when paused', () {
    expect(
      notificationElapsedSeconds(
        now: reportedAt.add(const Duration(minutes: 5)),
        startedAt: null,
        pausedSeconds: 12,
      ),
      12,
    );
  });
}
