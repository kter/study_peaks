import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/models/room.dart';
import 'package:study_peaks/widgets/room_card.dart';

import '../helpers/mock_data.dart';

void main() {
  group('RoomCard Widget', () {
    testWidgets('displays room name and occupancy', (tester) async {
      final room = mockRooms[0]; // Mt. Everest

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(
              room: room,
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Room name is visible
      expect(find.text('Mt. Everest'), findsOneWidget);
      // Core behavior: Occupancy text shows current/capacity
      expect(find.text('42 / 100 studying'), findsOneWidget);
    });

    testWidgets('displays occupancy percentage', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(
              room: lowOccupancyRoom,
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Shows percentage occupied
      expect(find.text('30% occupied'), findsOneWidget);
    });

    for (final (occupancy, capacity, percent) in [
      (29, 50, 58),
      (3, 40, 8),
      (29, 100, 29),
      (57, 100, 57),
      (58, 100, 58),
      (0, 0, 0),
      (-1, 50, 0),
      (51, 50, 100),
    ]) {
      testWidgets('$occupancy/$capacity displays and announces $percent%',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: RoomCard(
              room: Room(
                roomId: 'test-room',
                name: 'Test Room',
                capacity: capacity,
                currentOccupancy: occupancy,
              ),
            ),
          ),
        ));

        expect(find.text('$percent% occupied'), findsOneWidget);
        final indicator = find.byType(LinearProgressIndicator);
        final progress = tester.widget<LinearProgressIndicator>(indicator);
        expect(progress.semanticsValue, '$percent%');
        expect(tester.getSemantics(indicator).value, '$percent%');
        expect(progress.value, inInclusiveRange(0.0, 1.0));
      });
    }

    testWidgets('displays Join button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(
              room: mockRooms[0],
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Join button is visible
      expect(find.text('Join'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(
              room: mockRooms[0],
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      // Core behavior: Tap callback fires
      await tester.tap(find.byType(RoomCard));
      expect(tapped, true);
    });

    testWidgets('displays mountain icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(
              room: mockRooms[0],
              onTap: () {},
            ),
          ),
        ),
      );

      // Core behavior: Visual identity - mountain icon present
      expect(find.byIcon(Icons.terrain), findsOneWidget);
    });

    testWidgets('shows correct occupancy for different levels', (tester) async {
      // Low occupancy (30%)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(room: lowOccupancyRoom, onTap: () {}),
          ),
        ),
      );
      expect(find.text('30% occupied'), findsOneWidget);

      // Medium occupancy (65%)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(room: mediumOccupancyRoom, onTap: () {}),
          ),
        ),
      );
      expect(find.text('65% occupied'), findsOneWidget);

      // High occupancy (90%)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(room: highOccupancyRoom, onTap: () {}),
          ),
        ),
      );
      expect(find.text('90% occupied'), findsOneWidget);
    });
  });
}
