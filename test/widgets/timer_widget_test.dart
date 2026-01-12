import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/widgets/timer_widget.dart';

void main() {
  group('TimerWidget', () {
    /// Build a testable timer widget.
    Widget buildTimerWidget() {
      return MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<TimerProvider>(
            create: (_) => TimerProvider(),
            child: const TimerWidget(),
          ),
        ),
      );
    }

    /// Build a timer widget with an externally-managed provider
    Widget buildTimerWidgetWithProvider(TimerProvider provider) {
      return MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<TimerProvider>.value(
            value: provider,
            child: const TimerWidget(),
          ),
        ),
      );
    }

    testWidgets('displays initial time as 00:00', (tester) async {
      await tester.pumpWidget(buildTimerWidget());

      // Core behavior: Initial time display
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('displays Normal mode button', (tester) async {
      await tester.pumpWidget(buildTimerWidget());

      // Core behavior: Mode toggle buttons present
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Pomodoro'), findsOneWidget);
    });

    testWidgets('displays play button when not running', (tester) async {
      await tester.pumpWidget(buildTimerWidget());

      // Core behavior: Play button visible when paused
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('displays pause button when running', (tester) async {
      final provider = TimerProvider();
      provider.start();

      await tester.pumpWidget(buildTimerWidgetWithProvider(provider));
      await tester.pump();

      // Core behavior: Pause button visible when running
      expect(find.byIcon(Icons.pause), findsOneWidget);

      // Stop the timer before test ends to avoid pending timer error
      provider.pause();
      provider.dispose();
    });

    testWidgets('displays reset button', (tester) async {
      await tester.pumpWidget(buildTimerWidget());

      // Core behavior: Reset button always present
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('tapping play starts timer', (tester) async {
      await tester.pumpWidget(buildTimerWidget());

      // Tap play button
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      // Should now show pause button
      expect(find.byIcon(Icons.pause), findsOneWidget);

      // Pause timer to prevent pending timer error
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
    });

    testWidgets('tapping pause stops timer', (tester) async {
      final provider = TimerProvider();
      provider.start();

      await tester.pumpWidget(buildTimerWidgetWithProvider(provider));
      await tester.pump();

      // Tap pause button
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();

      // Should now show play button
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      provider.dispose();
    });

    testWidgets('Pomodoro mode shows focus indicator', (tester) async {
      final provider = TimerProvider();
      provider.setMode(TimerMode.pomodoro);

      await tester.pumpWidget(buildTimerWidgetWithProvider(provider));

      // Core behavior: Pomodoro shows phase indicator
      expect(find.text('🎯 Focus Time'), findsOneWidget);
      // Core behavior: Pomodoro shows cycle counter
      expect(find.text('0 cycles completed'), findsOneWidget);

      provider.dispose();
    });

    testWidgets('Pomodoro mode shows initial time of 25:00', (tester) async {
      final provider = TimerProvider();
      provider.setMode(TimerMode.pomodoro);

      await tester.pumpWidget(buildTimerWidgetWithProvider(provider));

      // Core behavior: Pomodoro starts with 25 minutes
      expect(find.text('25:00'), findsOneWidget);

      provider.dispose();
    });

    testWidgets('mode toggle changes between Normal and Pomodoro',
        (tester) async {
      await tester.pumpWidget(buildTimerWidget());

      // Initially in Normal mode (00:00)
      expect(find.text('00:00'), findsOneWidget);

      // Tap Pomodoro button
      await tester.tap(find.text('Pomodoro'));
      await tester.pump();

      // Should now show 25:00
      expect(find.text('25:00'), findsOneWidget);

      // Tap Normal button
      await tester.tap(find.text('Normal'));
      await tester.pump();

      // Should now show 00:00
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('cannot change mode while running', (tester) async {
      final provider = TimerProvider();
      provider.start();

      await tester.pumpWidget(buildTimerWidgetWithProvider(provider));
      await tester.pump();

      // Try to tap Pomodoro while running
      await tester.tap(find.text('Pomodoro'));
      await tester.pump();

      // Mode should not change (still in Normal mode with timer)
      expect(provider.mode, TimerMode.normal);

      // Stop timer before test ends
      provider.pause();
      provider.dispose();
    });
  });
}
