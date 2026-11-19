import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/services/lock_task_service.dart';
import 'package:study_peaks/services/notification_service.dart';

import '../helpers/test_helpers.dart';

class MockNotificationService extends Mock implements NotificationService {}

class MockLockTaskService extends Mock implements LockTaskService {}

/// Persistence of timer state across process restarts, bound to the seat
/// session (see TimerProvider.restoreState / endSession).
void main() {
  late TimerProvider provider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(TimerMode.normal);
    registerFallbackValue(PomodoroPhase.focus);
  });

  TimerProvider newProvider() {
    final notification = MockNotificationService();
    when(() => notification.isRunning()).thenAnswer((_) async => false);
    when(() => notification.showPhaseFinishedNotification(
          phase: any(named: 'phase'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        )).thenAnswer((_) async {});
    final lockTask = MockLockTaskService();
    when(() => lockTask.onLockTaskModeExited)
        .thenAnswer((_) => const Stream.empty());
    when(() => lockTask.dispose()).thenReturn(null);
    when(() => lockTask.stopLockTask()).thenAnswer((_) async => true);
    when(() => lockTask.setKeepScreenOn(any())).thenAnswer((_) async {});
    return TimerProvider(
      notificationService: notification,
      lockTaskService: lockTask,
    );
  }

  setUp(() async {
    await setupMockSharedPreferences();
    provider = newProvider();
  });

  tearDown(() {
    provider.dispose();
  });

  group('Persistence', () {
    Future<TimerProvider> restoreNewProvider() async {
      final restored = newProvider();
      addTearDown(restored.dispose);
      expect(await restored.restoreState(), true);
      return restored;
    }

    test('running normal timer survives recreation and keeps elapsed time',
        () async {
      provider.start();
      await Future<void>.delayed(const Duration(seconds: 1));
      final elapsed = provider.elapsedSeconds;
      expect(elapsed, greaterThanOrEqualTo(1));
      provider.dispose();
      await Future<void>.delayed(const Duration(seconds: 1));
      provider = newProvider();

      expect(await provider.restoreState(), true);
      expect(provider.isRunning, true);
      expect(provider.elapsedSeconds, greaterThanOrEqualTo(elapsed + 1));
      var notifications = 0;
      provider.addListener(() => notifications++);
      final before = provider.elapsedSeconds;
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(provider.elapsedSeconds, greaterThan(before));
      expect(notifications, greaterThan(0));
    });

    test('paused pomodoro retains phase, elapsed time and completed cycles',
        () async {
      await setupMockSharedPreferences({
        'persisted_timer_state': jsonEncode({
          'mode': TimerMode.pomodoro.index,
          'isRunning': true,
          'pausedDurationMs': 0,
          'pomodoroPhase': PomodoroPhase.shortBreak.index,
          'pomodoroCompletedCycles': 1,
          'pomodoroElapsedBeforePause': 0,
          'pomodoroPhaseStartedAt': DateTime.now()
              .subtract(const Duration(seconds: 20))
              .millisecondsSinceEpoch,
        }),
      });
      expect(await provider.restoreState(), true);
      provider.pause();
      final remaining = provider.pomodoroRemainingSeconds;
      expect(await provider.restoreState(), true);
      final restored = await restoreNewProvider();

      expect(restored.mode, TimerMode.pomodoro);
      expect(restored.isRunning, false);
      expect(restored.pomodoroPhase, PomodoroPhase.shortBreak);
      expect(remaining, lessThan(provider.pomodoroBreakDuration));
      expect(restored.pomodoroRemainingSeconds, remaining);
      expect(restored.pomodoroCompletedCycles, 1);
    });

    test('restoring expired focus moves to a stopped break and counts the cycle',
        () async {
      provider.setMode(TimerMode.pomodoro);
      provider.start();
      // Wait for the fire-and-forget writes before simulating time spent dead.
      final prefs = await SharedPreferences.getInstance();
      await provider.restoreState();
      final state = jsonDecode(prefs.getString('persisted_timer_state')!)
          as Map<String, dynamic>;
      state['pomodoroPhaseStartedAt'] = DateTime.now()
          .subtract(
              Duration(seconds: provider.pomodoroFocusDuration + 5))
          .millisecondsSinceEpoch;
      await prefs.setString('persisted_timer_state', jsonEncode(state));
      final restored = await restoreNewProvider();

      // Like the live tick, a finished phase waits for the user to start the
      // next one.
      expect(restored.isRunning, false);
      expect(restored.pomodoroPhase, PomodoroPhase.shortBreak);
      expect(restored.pomodoroCompletedCycles, 1);
      expect(restored.pomodoroRemainingSeconds, restored.pomodoroBreakDuration);
    });

    test('mode selection is saved before starting', () async {
      provider.setMode(TimerMode.pomodoro);
      expect(await provider.restoreState(), true);
      final restored = await restoreNewProvider();
      expect(restored.mode, TimerMode.pomodoro);
      expect(restored.isRunning, false);
      expect(restored.pomodoroRemainingSeconds,
          provider.pomodoroFocusDuration);
    });

    test('invalid saved data does not throw or change the timer', () async {
      await setupMockSharedPreferences({
        'persisted_timer_state': 'invalid json',
      });
      expect(await provider.restoreState(), false);
      expect(provider.mode, TimerMode.normal);
      expect(provider.isRunning, false);
    });

    test('endSession clears saved state even with pending writes',
        () async {
      provider.setMode(TimerMode.pomodoro);
      provider.start();
      provider.pause();
      provider.endSession();
      expect(await provider.restoreState(), false);
      final restored = newProvider();
      addTearDown(restored.dispose);
      expect(await restored.restoreState(), false);
    });

    test('reset during a session is restored as stopped, keeping the mode',
        () async {
      provider.setMode(TimerMode.pomodoro);
      provider.start(sessionId: 'session-A');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      provider.reset();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      provider.dispose();
      provider = newProvider();

      expect(await provider.restoreState(sessionId: 'session-A'), true);
      expect(provider.isRunning, false);
      expect(provider.mode, TimerMode.pomodoro);
      expect(provider.pomodoroRemainingSeconds,
          provider.pomodoroFocusDuration);
    });

    test('a timer started before sitting is bound to the new session',
        () async {
      provider.start();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      provider.start(sessionId: 'session-A');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final elapsed = provider.elapsedSeconds;
      provider.dispose();
      provider = newProvider();

      expect(await provider.restoreState(sessionId: 'session-A'), true);
      expect(provider.isRunning, true);
      expect(provider.elapsedSeconds, greaterThanOrEqualTo(elapsed));
    });

    test('restores only the state saved for the same session', () async {
      provider.start(sessionId: 'session-A');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      provider.dispose();
      provider = newProvider();

      expect(await provider.restoreState(sessionId: 'session-A'), true);
      expect(provider.isRunning, true);
    });

    test('discards state saved for a different session', () async {
      provider.start(sessionId: 'session-old');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      provider.dispose();
      provider = newProvider();

      expect(await provider.restoreState(sessionId: 'session-new'), false);
      expect(provider.isRunning, false);
      expect(provider.elapsedSeconds, 0);
      // The stale state is removed, so even the old session cannot restore it.
      expect(await provider.restoreState(sessionId: 'session-old'), false);
    });

    test('mode switch and reset keep the session binding', () async {
      provider.start(sessionId: 'session-A');
      provider.pause();
      provider.setMode(TimerMode.pomodoro);
      provider.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      provider.dispose();
      provider = newProvider();

      expect(await provider.restoreState(sessionId: 'session-A'), true);
      expect(provider.mode, TimerMode.pomodoro);
      expect(provider.isRunning, true);
    });

    test('endSession clears the binding and saved state', () async {
      provider.start(sessionId: 'session-A');
      provider.endSession();
      provider.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      provider.dispose();
      provider = newProvider();

      expect(await provider.restoreState(sessionId: 'session-A'), false);
    });

    test('clearPersistedState removes saved state', () async {
      provider.start(sessionId: 'session-A');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      provider.dispose();
      await TimerProvider.clearPersistedState();
      provider = newProvider();

      expect(await provider.restoreState(sessionId: 'session-A'), false);
    });
  });
}
