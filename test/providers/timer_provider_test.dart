import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/providers/timer_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('TimerProvider', () {
    late TimerProvider provider;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await setupMockSharedPreferences();
      provider = TimerProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    group('Normal Mode', () {
      test('initial state is correct', () {
        expect(provider.isRunning, false);
        expect(provider.elapsedSeconds, 0);
        expect(provider.mode, TimerMode.normal);
      });

      test('start timer updates isRunning', () {
        provider.start();
        expect(provider.isRunning, true);
      });

      test('pause timer updates isRunning', () {
        provider.start();
        provider.pause();
        expect(provider.isRunning, false);
      });

      test('reset timer clears elapsed time', () {
        provider.start();
        provider.pause();
        provider.reset();
        expect(provider.elapsedSeconds, 0);
        expect(provider.isRunning, false);
      });

      test('formatted time displays correctly', () {
        expect(provider.formattedTime, '00:00');
      });

      test('double start does not cause issues', () {
        provider.start();
        provider.start(); // Should be ignored
        expect(provider.isRunning, true);
      });

      test('totalStudySeconds equals elapsedSeconds in normal mode', () {
        expect(provider.totalStudySeconds, provider.elapsedSeconds);
      });
    });

    group('Pomodoro Mode', () {
      test('switch to pomodoro mode', () {
        provider.setMode(TimerMode.pomodoro);
        expect(provider.mode, TimerMode.pomodoro);
        expect(provider.pomodoroPhase, PomodoroPhase.focus);
      });

      test('pomodoro initial time is 25 minutes', () {
        provider.setMode(TimerMode.pomodoro);
        expect(provider.pomodoroRemainingSeconds, 25 * 60);
        expect(provider.formattedTime, '25:00');
      });

      test('cannot change mode while timer is running', () {
        provider.start();
        provider.setMode(TimerMode.pomodoro);
        expect(provider.mode, TimerMode.normal); // Should not change
      });

      test('pomodoroCompletedCycles starts at 0', () {
        provider.setMode(TimerMode.pomodoro);
        expect(provider.pomodoroCompletedCycles, 0);
      });

      test('reset in pomodoro mode resets to focus phase', () {
        provider.setMode(TimerMode.pomodoro);
        provider.start();
        provider.pause();
        provider.reset();

        expect(provider.pomodoroPhase, PomodoroPhase.focus);
        expect(provider.pomodoroRemainingSeconds, 25 * 60);
        expect(provider.isRunning, false);
      });
    });

    group('Persistence', () {
      Future<TimerProvider> restoreNewProvider() async {
        final restored = TimerProvider();
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
        provider = TimerProvider();

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
        expect(remaining, lessThan(TimerProvider.pomodoroBreakDuration));
        expect(restored.pomodoroRemainingSeconds, remaining);
        expect(restored.pomodoroCompletedCycles, 1);
      });

      test('restoring expired focus switches phase and counts the cycle',
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
                Duration(seconds: TimerProvider.pomodoroFocusDuration + 5))
            .millisecondsSinceEpoch;
        await prefs.setString('persisted_timer_state', jsonEncode(state));
        final restored = await restoreNewProvider();

        expect(restored.isRunning, true);
        expect(restored.pomodoroPhase, PomodoroPhase.shortBreak);
        expect(restored.pomodoroCompletedCycles, 1);
        expect(restored.pomodoroRemainingSeconds, greaterThan(0));
      });

      test('mode selection is saved before starting', () async {
        provider.setMode(TimerMode.pomodoro);
        expect(await provider.restoreState(), true);
        final restored = await restoreNewProvider();
        expect(restored.mode, TimerMode.pomodoro);
        expect(restored.isRunning, false);
        expect(restored.pomodoroRemainingSeconds,
            TimerProvider.pomodoroFocusDuration);
      });

      test('invalid saved data does not throw or change the timer', () async {
        await setupMockSharedPreferences({
          'persisted_timer_state': 'invalid json',
        });
        expect(await provider.restoreState(), false);
        expect(provider.mode, TimerMode.normal);
        expect(provider.isRunning, false);
      });

      test('reset clears saved state even with pending writes', () async {
        provider.setMode(TimerMode.pomodoro);
        provider.start();
        provider.pause();
        provider.reset();
        expect(await provider.restoreState(), false);
        final restored = TimerProvider();
        addTearDown(restored.dispose);
        expect(await restored.restoreState(), false);
      });

      test('restores only the state saved for the same session', () async {
        provider.start(sessionId: 'session-A');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        provider.dispose();
        provider = TimerProvider();

        expect(await provider.restoreState(sessionId: 'session-A'), true);
        expect(provider.isRunning, true);
      });

      test('discards state saved for a different session', () async {
        provider.start(sessionId: 'session-old');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        provider.dispose();
        provider = TimerProvider();

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
        provider = TimerProvider();

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
        provider = TimerProvider();

        expect(await provider.restoreState(sessionId: 'session-A'), false);
      });

      test('clearPersistedState removes saved state', () async {
        provider.start(sessionId: 'session-A');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        provider.dispose();
        await TimerProvider.clearPersistedState();
        provider = TimerProvider();

        expect(await provider.restoreState(sessionId: 'session-A'), false);
      });
    });

    group('Time Formatting', () {
      test('formats seconds correctly', () {
        expect(provider.formattedTime, '00:00');
      });

      test('formats minutes correctly in pomodoro', () {
        provider.setMode(TimerMode.pomodoro);
        expect(provider.formattedTime, '25:00');
      });
    });
  });
}
