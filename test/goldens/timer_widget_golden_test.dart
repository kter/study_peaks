import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/widgets/timer_widget.dart';

void main() {
  group('TimerWidget Golden Tests', () {
    setUpAll(() async {
      await loadAppFonts();
    });

    /// Build a timer widget with the given provider configuration.
    Widget buildTimerWidget({
      TimerProvider? provider,
      bool isCollapsed = false,
    }) {
      final timerProvider = provider ?? TimerProvider();
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
        surfaceSize: const Size(400, 400),
      );

      await screenMatchesGolden(tester, 'timer_widget_expanded_normal');
    });

    testGoldens('pomodoro mode - focus phase', (tester) async {
      final provider = TimerProvider();
      provider.setMode(TimerMode.pomodoro);

      await tester.pumpWidgetBuilder(
        buildTimerWidget(provider: provider, isCollapsed: false),
        surfaceSize: const Size(500, 500),
      );

      await screenMatchesGolden(tester, 'timer_widget_pomodoro_focus');

      provider.dispose();
    });

    testGoldens('timer running state', (tester) async {
      final provider = TimerProvider();
      provider.start();

      await tester.pumpWidgetBuilder(
        buildTimerWidget(provider: provider, isCollapsed: false),
        surfaceSize: const Size(400, 400),
      );

      await screenMatchesGolden(tester, 'timer_widget_running');

      provider.pause();
      provider.dispose();
    });

    testGoldens('pomodoro mode - running', (tester) async {
      final provider = TimerProvider();
      provider.setMode(TimerMode.pomodoro);
      provider.start();

      await tester.pumpWidgetBuilder(
        buildTimerWidget(provider: provider, isCollapsed: false),
        surfaceSize: const Size(500, 500),
      );

      await screenMatchesGolden(tester, 'timer_widget_pomodoro_running');

      provider.pause();
      provider.dispose();
    });
  });
}
