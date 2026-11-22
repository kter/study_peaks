import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/seat.dart';
import 'package:study_peaks/providers/room_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/widgets/seat_grid.dart';

import '../helpers/test_helpers.dart';

void main() {
  testWidgets('seat grid expands from four to eight columns at wider widths',
      (tester) async {
    const roomId = 'denali';
    final api = MockApiService();
    when(() => api.getRoomSeats(roomId)).thenAnswer(
      (_) async => List.generate(40, (index) => Seat.empty(index + 1)),
    );
    final rooms = RoomProvider(apiService: api);
    final session = SessionProvider(apiService: api);
    addTearDown(rooms.dispose);
    addTearDown(session.dispose);
    await rooms.fetchSeats(roomId);

    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(380, 800));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: rooms),
        ChangeNotifierProvider.value(value: session),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SeatGrid(
            roomId: roomId,
            onAlreadySeated: () {},
            onEmptySeatTap: (_) {},
            onOccupiedSeatTap: (_) {},
          ),
        ),
      ),
    ));

    final grid = find.byType(GridView);
    expect(
        tester.widget<GridView>(grid).gridDelegate,
        isA<SliverGridDelegateWithFixedCrossAxisCount>()
            .having((delegate) => delegate.crossAxisCount, 'column count', 4));

    await tester.binding.setSurfaceSize(const Size(900, 380));
    await tester.pumpAndSettle();
    expect(
        tester.widget<GridView>(grid).gridDelegate,
        isA<SliverGridDelegateWithFixedCrossAxisCount>()
            .having((delegate) => delegate.crossAxisCount, 'column count', 8));
  });
}
