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
      // Wait a bit
      provider.pause();
      provider.reset();
      expect(provider.elapsedSeconds, 0);
      expect(provider.isRunning, false);
    });

    test('switch to pomodoro mode', () {
      provider.setMode(TimerMode.pomodoro);
      expect(provider.mode, TimerMode.pomodoro);
      expect(provider.pomodoroPhase, PomodoroPhase.focus);
    });

    test('formatted time displays correctly', () {
      expect(provider.formattedTime, '00:00');
    });
  });
}
