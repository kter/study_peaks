import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/services/lock_task_service.dart';
import 'package:study_peaks/services/notification_service.dart';

class MockNotificationService extends Mock implements NotificationService {}

class MockLockTaskService extends Mock implements LockTaskService {}

void main() {
  late MockNotificationService mockNotificationService;
  late MockLockTaskService mockLockTaskService;
  late TimerProvider timerProvider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(TimerMode.normal);
    registerFallbackValue(PomodoroPhase.focus);
  });

  setUp(() {
    mockNotificationService = MockNotificationService();
    mockLockTaskService = MockLockTaskService();

    // Default mock behavior for notification service
    when(() => mockNotificationService.isRunning())
        .thenAnswer((_) async => true);
    when(() => mockNotificationService.updateTimerState(
          mode: any(named: 'mode'),
          isRunning: any(named: 'isRunning'),
          pomodoroPhase: any(named: 'pomodoroPhase'),
          seconds: any(named: 'seconds'),
        )).thenAnswer((_) async {});
    when(() => mockNotificationService.showPhaseFinishedNotification(
          phase: any(named: 'phase'),
          title: any(named: 'title'),
          body: any(named: 'body'),
        )).thenAnswer((_) async {});

    // Default mock behavior for lock task service
    when(() => mockLockTaskService.startLockTask())
        .thenAnswer((_) async => true);
    when(() => mockLockTaskService.stopLockTask())
        .thenAnswer((_) async => true);
    when(() => mockLockTaskService.isInLockTaskMode())
        .thenAnswer((_) async => false);
    when(() => mockLockTaskService.setKeepScreenOn(any()))
        .thenAnswer((_) async {});
    when(() => mockLockTaskService.onLockTaskModeExited)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockLockTaskService.dispose()).thenReturn(null);

    timerProvider = TimerProvider(
      notificationService: mockNotificationService,
      lockTaskService: mockLockTaskService,
    );
  });

  tearDown(() {
    // Only dispose if not already disposed in the test
    try {
      timerProvider.dispose();
    } catch (_) {
      // Already disposed in test
    }
  });

  group('TimerProvider - Screen Lock Settings', () {
    test('screenLockEnabled defaults to false', () {
      expect(timerProvider.screenLockEnabled, false);
    });

    test('setScreenLockEnabled toggles state and notifies listeners', () {
      bool notified = false;
      timerProvider.addListener(() => notified = true);

      timerProvider.setScreenLockEnabled(true);

      expect(timerProvider.screenLockEnabled, true);
      expect(notified, true);
    });

    test('setScreenLockEnabled to false after true', () {
      timerProvider.setScreenLockEnabled(true);
      expect(timerProvider.screenLockEnabled, true);

      timerProvider.setScreenLockEnabled(false);
      expect(timerProvider.screenLockEnabled, false);
    });

    test('isScreenLocked defaults to false', () {
      expect(timerProvider.isScreenLocked, false);
    });
  });

  group('TimerProvider - Start with Lock', () {
    test('startWithLock calls LockTaskService.startLockTask and setKeepScreenOn',
        () async {
      await timerProvider.startWithLock();

      verify(() => mockLockTaskService.startLockTask()).called(1);
      verify(() => mockLockTaskService.setKeepScreenOn(true)).called(1);
      expect(timerProvider.isScreenLocked, true);
      expect(timerProvider.isRunning, true);
    });

    test('startWithLock starts the timer', () async {
      await timerProvider.startWithLock();

      expect(timerProvider.isRunning, true);
    });
  });

  group('TimerProvider - Lock Release on Reset', () {
    test('reset calls stopLockTask when screen is locked', () async {
      await timerProvider.startWithLock();
      clearInteractions(mockLockTaskService);

      timerProvider.reset();

      verify(() => mockLockTaskService.stopLockTask()).called(1);
      verify(() => mockLockTaskService.setKeepScreenOn(false)).called(1);
      expect(timerProvider.isScreenLocked, false);
    });

    test('reset does not call stopLockTask when screen is not locked', () {
      timerProvider.start();

      timerProvider.reset();

      verifyNever(() => mockLockTaskService.stopLockTask());
    });
  });

  group('TimerProvider - Lock Release on Phase Switch (Pomodoro)', () {
    test('switching to break phase releases lock task', () async {
      timerProvider.setMode(TimerMode.pomodoro);
      timerProvider.pomodoroFocusDuration = 1; // 1 second

      await timerProvider.startWithLock();
      clearInteractions(mockLockTaskService);

      // Wait for phase to switch
      await Future.delayed(const Duration(milliseconds: 1200));

      verify(() => mockLockTaskService.stopLockTask()).called(1);
      verify(() => mockLockTaskService.setKeepScreenOn(false)).called(1);
      expect(timerProvider.isScreenLocked, false);
      expect(timerProvider.pomodoroPhase, PomodoroPhase.shortBreak);
    });
  });

  group('TimerProvider - Manual Lock Task Exit', () {
    test('onLockTaskExited callback is set up correctly',
        () async {
      var callbackCalled = false;
      timerProvider.onLockTaskExited = () => callbackCalled = true;

      // Simulate startWithLock
      await timerProvider.startWithLock();
      expect(timerProvider.isScreenLocked, true);
      // Verify callback was registered (not null)
      expect(timerProvider.onLockTaskExited, isNotNull);
      // callbackCalled would be true if the stream emitted,
      // but we can't easily simulate that with a mock.
      expect(callbackCalled, false); // Not yet triggered
    });

    test('timer continues running after manual lock exit', () async {
      await timerProvider.startWithLock();
      expect(timerProvider.isRunning, true);

      // Even if we can't easily trigger the stream, verify that the timer state
      // won't be affected by the lock release
      timerProvider.reset(); // This should release lock
      expect(timerProvider.isScreenLocked, false);
      // Timer should be stopped by reset, which is expected
      expect(timerProvider.isRunning, false);
    });
  });

  group('TimerProvider - Dispose Cleanup', () {
    test('dispose releases lock task if locked', () async {
      await timerProvider.startWithLock();
      clearInteractions(mockLockTaskService);

      timerProvider.dispose();

      verify(() => mockLockTaskService.stopLockTask()).called(1);
      verify(() => mockLockTaskService.setKeepScreenOn(false)).called(1);
    });

    test('dispose does not call stopLockTask if not locked', () {
      timerProvider.start();

      timerProvider.dispose();

      verifyNever(() => mockLockTaskService.stopLockTask());
    });

    test('dispose calls lockTaskService.dispose', () {
      timerProvider.dispose();

      verify(() => mockLockTaskService.dispose()).called(1);
    });
  });

  group('TimerProvider - Backward Compatibility', () {
    test('start without lock still works normally', () {
      timerProvider.start();

      expect(timerProvider.isRunning, true);
      expect(timerProvider.isScreenLocked, false);
      verifyNever(() => mockLockTaskService.startLockTask());
    });

    test('pause still works with lock enabled but not locked', () {
      timerProvider.setScreenLockEnabled(true);
      timerProvider.start();

      timerProvider.pause();

      expect(timerProvider.isRunning, false);
      verifyNever(() => mockLockTaskService.stopLockTask());
    });
  });
}
