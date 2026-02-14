
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/services/notification_service.dart';
// TimerMode is exported by TimerProvider

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  late MockNotificationService mockNotificationService;
  late TimerProvider timerProvider;
  
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Register fallback values if needed for any()
    registerFallbackValue(TimerMode.normal);
    registerFallbackValue(PomodoroPhase.focus);
  });

  setUp(() {
    mockNotificationService = MockNotificationService();
    
    // Default mock behavior
    when(() => mockNotificationService.isRunning()).thenAnswer((_) async => true);
    when(() => mockNotificationService.updateTimerState(
      mode: any(named: 'mode'),
      isRunning: any(named: 'isRunning'),
      pomodoroPhase: any(named: 'pomodoroPhase'),
      seconds: any(named: 'seconds'),
    )).thenAnswer((_) async {});

    timerProvider = TimerProvider(notificationService: mockNotificationService);
  });
  
  tearDown(() {
    timerProvider.dispose();
  });

  group('TimerProvider - Normal Mode', () {
    test('Initial state should be correct', () {
      expect(timerProvider.mode, TimerMode.normal);
      expect(timerProvider.isRunning, false);
      expect(timerProvider.elapsedSeconds, 0);
    });

    test('Start should begin timer and update notification', () async {
      timerProvider.start();
      await Future.delayed(Duration.zero);
      
      expect(timerProvider.isRunning, true);
      // Verify notification update called
      verify(() => mockNotificationService.updateTimerState(
        mode: TimerMode.normal,
        isRunning: true,
        pomodoroPhase: null,
        seconds: 0,
      )).called(1);
    });
    
    test('Pause should stop timer and save elapsed time', () async {
      timerProvider.start();
      await Future.delayed(const Duration(milliseconds: 100));
      
      timerProvider.pause();
      await Future.delayed(Duration.zero);
      
      expect(timerProvider.isRunning, false);
      verify(() => mockNotificationService.updateTimerState(
        mode: TimerMode.normal,
        isRunning: false,
        pomodoroPhase: null, // explicit null
        seconds: any(named: 'seconds'),
      )).called(1);
    });

    test('setInitialDuration sets paused duration', () {
      const initial = Duration(minutes: 5);
      timerProvider.setInitialDuration(initial);
      
      expect(timerProvider.elapsedSeconds, initial.inSeconds);
      
      // Start and check it continues from there
      timerProvider.start();
      // Immediately after start, now - startedAt is approx 0.
      expect(timerProvider.elapsedSeconds, closeTo(initial.inSeconds, 1));
    });
  });

  group('TimerProvider - Pomodoro Mode', () {
    setUp(() {
      timerProvider.setMode(TimerMode.pomodoro);
      // setMode calls reset which calls updateTimerState
      // Clear interactions to test start/reset in isolation
      clearInteractions(mockNotificationService);
    });

    test('Initial pomodoro state should be Focus', () {
      expect(timerProvider.mode, TimerMode.pomodoro);
      expect(timerProvider.pomodoroPhase, PomodoroPhase.focus);
      expect(timerProvider.pomodoroRemainingSeconds, 25 * 60);
    });

    test('Start in Pomodoro should update notification with phase', () async {
      timerProvider.start();
      await Future.delayed(Duration.zero);
      
      expect(timerProvider.isRunning, true);
      verify(() => mockNotificationService.updateTimerState(
        mode: TimerMode.pomodoro,
        isRunning: true,
        pomodoroPhase: PomodoroPhase.focus,
        seconds: 25 * 60,
      )).called(1);
    });

    test('Reset should reset to initial Focus state', () async {
      timerProvider.start();
      await Future.delayed(Duration.zero);
      timerProvider.pause();
      await Future.delayed(Duration.zero);
      clearInteractions(mockNotificationService);
      
      timerProvider.reset();
      await Future.delayed(Duration.zero);
      
      expect(timerProvider.pomodoroPhase, PomodoroPhase.focus);
      expect(timerProvider.pomodoroRemainingSeconds, 25 * 60);
      expect(timerProvider.isRunning, false);
      
      verify(() => mockNotificationService.updateTimerState(
        mode: TimerMode.pomodoro,
        isRunning: false,
        pomodoroPhase: PomodoroPhase.focus,
        seconds: 25 * 60, // Reset duration
      )).called(1);
    });

  });
}
