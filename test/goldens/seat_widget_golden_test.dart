import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:study_peaks/models/models.dart';
import 'package:study_peaks/widgets/seat_widget.dart';

import '../helpers/mock_data.dart';

class _OccupiedSeat extends Seat {
  const _OccupiedSeat({
    required super.seatId,
    required super.seatNumber,
    required this.elapsed,
  }) : super(isOccupied: true, user: mockUser);

  final Duration elapsed;

  // Fix the session duration displayed in the golden regardless of wall time.
  @override
  Duration elapsedAt(DateTime now) => elapsed;
}

const _occupiedSeat = _OccupiedSeat(
  seatId: 'seat-001',
  seatNumber: 1,
  elapsed: Duration(hours: 1),
);

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
              seat: _occupiedSeat,
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
      const shortSessionSeat = _OccupiedSeat(
        seatId: 'seat-short',
        seatNumber: 3,
        elapsed: Duration(minutes: 10),
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

    testGoldens('empty and occupied seats side by side', (tester) async {
      final builder = GoldenBuilder.grid(
        columns: 2,
        widthToHeightRatio: 0.8,
      )
        ..addScenario(
          'Empty',
          SizedBox(
            width: 110,
            height: 160,
            child: SeatWidget(seat: mockEmptySeat, size: 50),
          ),
        )
        ..addScenario(
          'Occupied',
          const SizedBox(
            width: 110,
            height: 180,
            child: SeatWidget(seat: _occupiedSeat, size: 50),
          ),
        );

      await tester.pumpWidgetBuilder(
        builder.build(),
        surfaceSize: const Size(400, 300),
      );

      await screenMatchesGolden(tester, 'seat_widget_comparison');
    });
  });
}
