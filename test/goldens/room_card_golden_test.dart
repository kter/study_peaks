import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:study_peaks/widgets/room_card.dart';

import '../helpers/mock_data.dart';

void main() {
  group('RoomCard Golden Tests', () {
    setUpAll(() async {
      await loadAppFonts();
    });

    testGoldens('low occupancy room (green)', (tester) async {
      await tester.pumpWidgetBuilder(
        Center(
          child: SizedBox(
            width: 200,
            height: 220,
            child: RoomCard(
              room: lowOccupancyRoom,
              onTap: () {},
            ),
          ),
        ),
        surfaceSize: const Size(250, 270),
      );

      await screenMatchesGolden(tester, 'room_card_low_occupancy');
    });

    testGoldens('medium occupancy room (orange)', (tester) async {
      await tester.pumpWidgetBuilder(
        Center(
          child: SizedBox(
            width: 200,
            height: 220,
            child: RoomCard(
              room: mediumOccupancyRoom,
              onTap: () {},
            ),
          ),
        ),
        surfaceSize: const Size(250, 270),
      );

      await screenMatchesGolden(tester, 'room_card_medium_occupancy');
    });

    testGoldens('high occupancy room (red)', (tester) async {
      await tester.pumpWidgetBuilder(
        Center(
          child: SizedBox(
            width: 200,
            height: 220,
            child: RoomCard(
              room: highOccupancyRoom,
              onTap: () {},
            ),
          ),
        ),
        surfaceSize: const Size(250, 270),
      );

      await screenMatchesGolden(tester, 'room_card_high_occupancy');
    });

    testGoldens('all occupancy levels', (tester) async {
      final builder = GoldenBuilder.column(
        wrap: (widget) => SizedBox(width: 200, height: 220, child: widget),
      )
        ..addScenario(
          'Low (30%)',
          RoomCard(room: lowOccupancyRoom, onTap: () {}),
        )
        ..addScenario(
          'Medium (65%)',
          RoomCard(room: mediumOccupancyRoom, onTap: () {}),
        )
        ..addScenario(
          'High (90%)',
          RoomCard(room: highOccupancyRoom, onTap: () {}),
        );

      await tester.pumpWidgetBuilder(
        builder.build(),
        surfaceSize: const Size(250, 840),
      );

      await screenMatchesGolden(tester, 'room_card_all_occupancy_levels');
    });
  });
}
