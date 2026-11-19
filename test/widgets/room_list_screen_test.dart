import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/room_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/providers/user_settings_provider.dart';
import 'package:study_peaks/repositories/mock_data_repository.dart';
import 'package:study_peaks/screens/room_list_screen.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/network_exception.dart';
import 'package:study_peaks/widgets/room_card.dart';

import '../helpers/test_helpers.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

class _MockSessionProvider extends Mock implements SessionProvider {}

class _MockTimerProvider extends Mock implements TimerProvider {}

class _MockUserSettingsProvider extends Mock implements UserSettingsProvider {}

void stubLocalization(_MockTimerProvider timer) {
  when(() => timer.updateLocalization(
        focusFinishedTitle: any(named: 'focusFinishedTitle'),
        breakFinishedTitle: any(named: 'breakFinishedTitle'),
        focusFinishedBody: any(named: 'focusFinishedBody'),
        breakFinishedBody: any(named: 'breakFinishedBody'),
      )).thenReturn(null);
}

void main() {
  for (final timerRestored in [false, true]) {
    testWidgets('restored session: saved timer state is $timerRestored',
        (tester) async {
      final api = MockApiService();
      when(() => api.getRooms()).thenAnswer((_) async => []);
      final rooms = RoomProvider(apiService: api);
      addTearDown(rooms.dispose);
      final auth = _MockAuthProvider();
      when(() => auth.isSignedIn).thenReturn(false);
      final settings = _MockUserSettingsProvider();
      when(() => settings.iconSeed).thenReturn('test');
      final session = _MockSessionProvider();
      when(() => session.restoreSessionIfNeeded()).thenAnswer((_) async => true);
      when(() => session.currentRoomId).thenReturn(null);
      when(() => session.currentDuration).thenReturn(0);
      final timer = _MockTimerProvider();
      stubLocalization(timer);
      when(() => timer.restoreState()).thenAnswer((_) async => timerRestored);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<RoomProvider>.value(value: rooms),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<UserSettingsProvider>.value(value: settings),
            ChangeNotifierProvider<SessionProvider>.value(value: session),
            ChangeNotifierProvider<TimerProvider>.value(value: timer),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('en'),
            home: RoomListScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => timer.restoreState()).called(1);
      if (timerRestored) {
        verifyNever(() => timer.start());
      } else {
        verify(() => timer.start()).called(1);
      }
    });
  }

  for (final useMockRooms in [false, true]) {
    for (final networkError in [false, true]) {
      testWidgets(
        'shows error and retries (mock rooms: $useMockRooms, network: $networkError)',
        (tester) async {
          final api = MockApiService();
          when(() => api.getRooms()).thenThrow(
            networkError
                ? const NetworkException('offline')
                : ApiException('internal details', 500),
          );
          final rooms = RoomProvider(
            apiService: api,
            mockDataRepository: useMockRooms ? DevMockDataRepository() : null,
          );
          addTearDown(rooms.dispose);
          final auth = _MockAuthProvider();
          when(() => auth.isSignedIn).thenReturn(false);
          final settings = _MockUserSettingsProvider();
          when(() => settings.iconSeed).thenReturn('test');
          final session = _MockSessionProvider();
          when(() => session.restoreSessionIfNeeded())
              .thenAnswer((_) async => false);
          final timer = _MockTimerProvider();
          stubLocalization(timer);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<RoomProvider>.value(value: rooms),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<UserSettingsProvider>.value(
                    value: settings),
                ChangeNotifierProvider<SessionProvider>.value(value: session),
                ChangeNotifierProvider<TimerProvider>.value(value: timer),
              ],
              child: const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: Locale('en'),
                home: RoomListScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final l10n = AppLocalizations.of(
            tester.element(find.byType(RoomListScreen)),
          )!;
          final message =
              networkError ? l10n.networkError : l10n.loadRoomsFailed;
          expect(find.text(message), findsOneWidget);
          expect(find.text('internal details'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(RoomCard),
              useMockRooms ? findsWidgets : findsNothing);

          if (!useMockRooms) {
            // A short, empty list must still support pull-to-refresh.
            await tester.drag(
                find.byType(CustomScrollView), const Offset(0, 300));
            await tester.pumpAndSettle();
            verify(() => api.getRooms()).called(2);
          } else {
            verify(() => api.getRooms()).called(1);
          }

          when(() => api.getRooms()).thenAnswer((_) async => []);
          await tester.tap(find.text(l10n.retry));
          await tester.pumpAndSettle();

          verify(() => api.getRooms()).called(1);
          expect(find.text(message), findsNothing);
          expect(rooms.error, isNull);
          expect(rooms.roomsError, isNull);

          // A subsequent seat refresh failure must not show a room-list error.
          when(() => api.getRoomSeats('fuji'))
              .thenThrow(ApiException('seat refresh failed', 500));
          await rooms.fetchSeats('fuji');
          await tester.pumpAndSettle();
          expect(rooms.error, isNotNull);
          expect(rooms.roomsError, isNull);
          expect(find.text(l10n.loadRoomsFailed), findsNothing);
          expect(find.text(l10n.networkError), findsNothing);
        },
      );
    }
  }
}
