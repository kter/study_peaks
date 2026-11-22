import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/models.dart';
import 'package:study_peaks/widgets/seat_widget.dart';

import '../helpers/mock_data.dart';

void main() {
  for (final (locale, isOccupied, isCurrentUser, label) in [
    ('en', false, false, 'Seat 5, empty. Tap to sit down.'),
    ('en', true, false, 'Seat 5, Test User, Japan, 3m'),
    ('en', true, true, 'Seat 5, your seat, 3m'),
    ('ja', true, false, '座席5、Test User、日本、3m'),
  ]) {
    testWidgets('announces $label as a button', (tester) async {
      final now = DateTime.utc(2026, 1, 1);
      final seat = isOccupied
          ? Seat(
              seatId: 'seat-005',
              seatNumber: 5,
              isOccupied: true,
              user: mockUser,
              sessionStartedAt: now.subtract(const Duration(minutes: 3)),
            )
          : Seat.empty(5);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale(locale),
        home: Scaffold(
          body: SeatWidget(
            seat: seat,
            now: () => now,
            isCurrentUser: isCurrentUser,
            onTap: () {},
          ),
        ),
      ));

      final seatSemantics = find.bySemanticsLabel(label);
      expect(seatSemantics, findsOneWidget);
      expect(
        tester.getSemantics(seatSemantics),
        matchesSemantics(
          label: label,
          textDirection: TextDirection.ltr,
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel(isOccupied ? mockUser.displayName : '#5'),
          findsNothing);
    });
  }

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

    testWidgets('refreshes the badge and announcement at each elapsed minute',
        (tester) async {
      final now = tester.binding.clock.now;
      final seat = Seat(
        seatId: 'seat-timed',
        seatNumber: 1,
        isOccupied: true,
        user: mockUser,
        sessionStartedAt: now().subtract(const Duration(minutes: 4, seconds: 58)),
      );
      var parentBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (_) {
                parentBuilds++;
                return SeatWidget(seat: seat, now: now);
              },
            ),
          ),
        ),
      );
      final username = find.text(mockUser.displayName);
      final usernameWidget = tester.widget(username);
      final initialParentBuilds = parentBuilds;
      expect(find.text('4m'), findsOneWidget);
      expect(find.bySemanticsLabel('Seat 1, Test User, Japan, 4m'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('4m'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('5m'), findsOneWidget);
      expect(find.bySemanticsLabel('Seat 1, Test User, Japan, 5m'), findsOneWidget);

      await tester.pump(const Duration(minutes: 1));
      expect(find.text('6m'), findsOneWidget);
      expect(find.bySemanticsLabel('Seat 1, Test User, Japan, 6m'), findsOneWidget);
      expect(parentBuilds, initialParentBuilds);
      expect(tester.widget(username), same(usernameWidget));
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

    testWidgets('displays 0m for new session', (tester) async {
      final newSessionSeat = Seat(
        seatId: 'seat-new',
        seatNumber: 3,
        isOccupied: true,
        user: mockUser,
        sessionStartedAt: DateTime.now(), // Duration ~0
        currentSessionDuration: 0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SeatWidget(
              seat: newSessionSeat,
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: New session shows 0m
      expect(find.text('0m'), findsOneWidget);
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
