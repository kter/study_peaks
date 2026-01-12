import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:study_peaks/models/seat.dart';
import 'package:study_peaks/widgets/seat_widget.dart';

import '../helpers/mock_data.dart';

void main() {
  group('SeatWidget Golden Tests', () {
    setUpAll(() async {
      await loadAppFonts();
    });

    testGoldens('empty seat', (tester) async {
      await tester.pumpWidgetBuilder(
        Center(
          child: SizedBox(
            width: 120,
            height: 160,
            child: SeatWidget(
              seat: mockEmptySeat,
              size: 50,
              onTap: () {},
            ),
          ),
        ),
        surfaceSize: const Size(180, 220),
      );

      await screenMatchesGolden(tester, 'seat_widget_empty');
    });

    testGoldens('occupied seat with user', (tester) async {
      await tester.pumpWidgetBuilder(
        Center(
          child: SizedBox(
            width: 120,
            height: 180,
            child: SeatWidget(
              seat: mockOccupiedSeat,
              size: 50,
              onTap: () {},
            ),
          ),
        ),
        surfaceSize: const Size(180, 240),
      );

      await screenMatchesGolden(tester, 'seat_widget_occupied');
    });

    testGoldens('seat with short session duration', (tester) async {
      final shortSessionSeat = Seat(
        seatId: 'seat-short',
        seatNumber: 3,
        isOccupied: true,
        user: mockUser,
        currentSessionDuration: 600, // 10 minutes
      );

      await tester.pumpWidgetBuilder(
        Center(
          child: SizedBox(
            width: 120,
            height: 180,
            child: SeatWidget(
              seat: shortSessionSeat,
              size: 50,
              onTap: () {},
            ),
          ),
        ),
        surfaceSize: const Size(180, 240),
      );

      await screenMatchesGolden(tester, 'seat_widget_short_session');
    });
  });
}
