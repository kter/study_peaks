import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/widgets/room_card.dart';
import 'package:study_peaks/services/api_service.dart';

void main() {
  group('RoomCard Widget', () {
    testWidgets('displays room name and occupancy', (tester) async {
      final room = Room(
        roomId: 'test-room',
        name: 'Test Room',
        capacity: 100,
        currentOccupancy: 42,
      );

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

      expect(find.text('Test Room'), findsOneWidget);
      expect(find.text('42/100'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      final room = Room(
        roomId: 'test-room',
        name: 'Test Room',
        capacity: 100,
        currentOccupancy: 42,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomCard(
              room: room,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(RoomCard));
      expect(tapped, true);
    });
  });
}
