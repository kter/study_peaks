import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/models/seat.dart';
import 'package:study_peaks/widgets/seat_widget.dart';

import '../helpers/mock_data.dart';

void main() {
  group('SeatWidget - Empty Seat', () {
    testWidgets('displays seat number', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: mockEmptySeat,
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Empty seat shows seat number
      expect(find.text('#5'), findsOneWidget);
    });

    testWidgets('displays chair icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: mockEmptySeat,
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Empty seat shows chair icon
      expect(find.byIcon(Icons.event_seat_outlined), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: mockEmptySeat,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SeatWidget));
      expect(tapped, true);
    });
  });

  group('SeatWidget - Occupied Seat', () {
    testWidgets('displays user name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: mockOccupiedSeat,
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Shows username
      expect(find.text('Test User'), findsOneWidget);
    });

    testWidgets('displays duration badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: mockOccupiedSeat, // 3600 seconds = 1h 0m
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Shows duration text
      expect(find.text('1h0m'), findsOneWidget);
    });

    testWidgets('duration displays minutes only when under an hour', (tester) async {
      final shortSessionSeat = Seat(
        seatId: 'seat-short',
        seatNumber: 2,
        isOccupied: true,
        user: mockUser,
        sessionStartedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        currentSessionDuration: 1800, // legacy field
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: shortSessionSeat,
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Short duration shows minutes only
      expect(find.text('30m'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: mockOccupiedSeat,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SeatWidget));
      expect(tapped, true);
    });
  });
}
