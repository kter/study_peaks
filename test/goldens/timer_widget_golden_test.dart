import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/services/notification_service.dart';
import 'package:study_peaks/widgets/timer_widget.dart';

class MockNotificationService extends Mock implements NotificationService {}

const _expandedSurface = Size(500, 550);

void main() {
  group('TimerWidget Golden Tests', () {
    late TimerProvider timerProvider;

    setUpAll(() async {
      registerFallbackValue(TimerMode.normal);
      registerFallbackValue(PomodoroPhase.focus);
      await loadAppFonts();
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});

      final notifications = MockNotificationService();
      when(() => notifications.isRunning()).thenAnswer((_) async => true);
      when(() => notifications.updateTimerState(
            sessionId: any(named: 'sessionId'),
            waitingToStart: any(named: 'waitingToStart'),
            mode: any(named: 'mode'),
            isRunning: any(named: 'isRunning'),
            pomodoroPhase: any(named: 'pomodoroPhase'),
            seconds: any(named: 'seconds'),
          )).thenAnswer((_) async {});
      when(() => notifications.showPhaseFinishedNotification(
            phase: any(named: 'phase'),
            title: any(named: 'title'),
            body: any(named: 'body'),
          )).thenAnswer((_) async {});
      final testTime = DateTime.utc(2026);
      timerProvider = TimerProvider(
        notificationService: notifications,
        now: () => testTime,
      );
      addTearDown(timerProvider.dispose);
    });

    /// Build a timer widget with the given provider configuration.
    Widget buildTimerWidget({
      bool isCollapsed = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ChangeNotifierProvider<TimerProvider>.value(
                value: timerProvider,
                child: TimerWidget(
                  isCollapsed: isCollapsed,
                  onToggleCollapsed: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testGoldens('initial state - collapsed', (tester) async {
      await tester.pumpWidgetBuilder(
        buildTimerWidget(isCollapsed: true),
        surfaceSize: const Size(400, 200),
      );

      await screenMatchesGolden(tester, 'timer_widget_collapsed');
    });

    testGoldens('initial state - expanded normal mode', (tester) async {
      await tester.pumpWidgetBuilder(
        buildTimerWidget(isCollapsed: false),
        surfaceSize: _expandedSurface,
      );

      await screenMatchesGolden(tester, 'timer_widget_expanded_normal');
    });

    testGoldens('pomodoro mode - focus phase', (tester) async {
      timerProvider.setMode(TimerMode.pomodoro);

      await tester.pumpWidgetBuilder(
        buildTimerWidget(isCollapsed: false),
        surfaceSize: _expandedSurface,
      );

      await screenMatchesGolden(tester, 'timer_widget_pomodoro_focus');
    });

    testGoldens('timer running state', (tester) async {
      timerProvider.start();

      try {
        await tester.pumpWidgetBuilder(
          buildTimerWidget(isCollapsed: false),
          surfaceSize: _expandedSurface,
        );
        await screenMatchesGolden(tester, 'timer_widget_running');
      } finally {
        timerProvider.pause();
      }
    });

    testGoldens('pomodoro mode - running', (tester) async {
      timerProvider.setMode(TimerMode.pomodoro);
      timerProvider.start();

      try {
        await tester.pumpWidgetBuilder(
          buildTimerWidget(isCollapsed: false),
          surfaceSize: _expandedSurface,
        );
        await screenMatchesGolden(tester, 'timer_widget_pomodoro_running');
      } finally {
        timerProvider.pause();
      }
    });
  });
}
