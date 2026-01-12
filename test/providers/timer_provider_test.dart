import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/providers/timer_provider.dart';

void main() {
  group('TimerProvider', () {
    late TimerProvider provider;

    setUp(() {
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
