import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/config/app_config.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/models.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/room_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/providers/study_bgm_controller.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/providers/user_settings_provider.dart';
import 'package:study_peaks/screens/room_detail_screen.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/network_exception.dart';
import 'package:study_peaks/widgets/seat_widget.dart';

import '../helpers/test_helpers.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

const _room =
    Room(roomId: 'fuji', name: 'Mt. Fuji', capacity: 2, currentOccupancy: 0);
const _guest = SeatUser(
  userId: 'other-user',
  displayName: 'Other user',
  countryCode: 'JP',
  iconSeed: 'other',
  statusMessage: '',
);
final _startedAt = DateTime.utc(2026, 11, 22);

Seat _occupiedSeat(int number, [DateTime? startedAt]) => Seat(
      seatId: 'seat-$number',
      seatNumber: number,
      isOccupied: true,
      user: _guest,
      sessionStartedAt: startedAt,
    );

Finder _seat(int number) => find.byWidgetPredicate(
      (widget) => widget is SeatWidget && widget.seat.seatNumber == number,
    );

void main() {
  late MockApiService api;
  late RoomProvider rooms;
  late SessionProvider session;
  late TimerProvider timer;

  setUp(() async {
    await setupMockSharedPreferences();
    api = MockApiService();
    rooms = RoomProvider(apiService: api);
  });

  Future<AppLocalizations> pumpRoom(WidgetTester tester,
      {Locale? locale}) async {
    final auth = _MockAuthProvider();
    when(() => auth.isSignedIn).thenReturn(false);
    final notifications = mockStudyNotifications();
    session = SessionProvider(
      apiService: api,
      notificationService: notifications,
      useMockFallback: false,
    );
    timer = TimerProvider(
        now: () => _startedAt, notificationService: notifications);
    session.setTimerProvider(timer);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => rooms),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider(create: (_) => UserSettingsProvider()),
        ChangeNotifierProvider(create: (_) => timer),
        ChangeNotifierProvider(create: (_) => session),
        ChangeNotifierProvider(create: (_) => StudyBgmController(timer)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale ?? const Locale('en'),
        home: const RoomDetailScreen(room: _room),
      ),
    ));
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(RoomDetailScreen)))!;
  }

  Future<void> sitInRoom(WidgetTester tester) async {
    when(() => api.sit(_room.roomId, 1)).thenAnswer(
      (_) async => createMockSitResponse(sessionStartedAt: _startedAt),
    );
    final sit = session.sit(_room.roomId, 1);
    await tester.pump();
    expect(await sit, isTrue);
  }

  for (final status in [409, 500, null]) {
    testWidgets('failed sit shows one localized snackbar (status: $status)',
        (tester) async {
      var fetches = 0;
      when(() => api.getRoomSeats(_room.roomId)).thenAnswer((_) async {
        return [++fetches == 3 ? _occupiedSeat(1) : Seat.empty(1)];
      });
      when(() => api.sit(
                _room.roomId,
                1,
                displayName: any(named: 'displayName'),
                countryCode: any(named: 'countryCode'),
                iconSeed: any(named: 'iconSeed'),
              ))
          .thenThrow(status == null
              ? const NetworkException('offline')
              : ApiException('internal details', status));
      final l10n = await pumpRoom(tester, locale: const Locale('ja'));
      await tester.tap(_seat(1));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text(l10n.sitDown));
      await tester.pumpAndSettle();

      final message = switch (status) {
        409 => l10n.seatTaken,
        null => l10n.networkError,
        _ => l10n.sitFailed,
      };
      expect(find.text(message), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);
      expect(find.textContaining('internal details'), findsNothing);
      expect(fetches, status == 409 ? 3 : 2);
      expect(rooms.getSeats(_room.roomId).single.isOccupied, status == 409);
      expect(
          find.text(l10n.studyingCount(status == 409 ? 1 : 0)), findsOneWidget);

      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('occupied seat taps are ignored during a delayed sit flow',
      (tester) async {
    final seats = [Seat.empty(1), _occupiedSeat(2)];
    when(() => api.getRoomSeats(_room.roomId)).thenAnswer((_) async => seats);
    final l10n = await pumpRoom(tester);
    final delayedSeats = Completer<List<Seat>>();
    when(() => api.getRoomSeats(_room.roomId))
        .thenAnswer((_) => delayedSeats.future);

    await tester.tap(_seat(1));
    await tester.pump();
    await tester.tap(_seat(2));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    delayedSeats.complete(seats);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.seatTitle(1)), findsOneWidget);
    expect(find.byType(BottomSheet, skipOffstage: false), findsNothing);
    final cancel =
        MaterialLocalizations.of(tester.element(find.byType(AlertDialog)))
            .cancelButtonLabel;
    await tester.tap(find.text(cancel));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    await tester.tap(_seat(2));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final seats in [
    [Seat.empty(2)],
    [Seat.empty(1)],
    [_occupiedSeat(1, _startedAt.add(const Duration(seconds: 1)))],
  ]) {
    final replacement = seats.single;
    testWidgets(
        'refresh verifies a missing or replaced seat (${replacement.seatNumber}, '
        'occupied: ${replacement.isOccupied})', (tester) async {
      when(() => api.getRoomSeats(_room.roomId))
          .thenAnswer((_) async => [Seat.empty(1)]);
      final l10n = await pumpRoom(tester);
      await sitInRoom(tester);
      when(() => api.getRoomSeats(_room.roomId)).thenAnswer((_) async => seats);
      final sync = Completer<void>();
      when(() => api.sync(_room.roomId, 'test-session-id', 0))
          .thenAnswer((_) => sync.future);

      await tester
          .pump(const Duration(seconds: AppConfig.seatRefreshIntervalSeconds));
      expect(session.state, SessionState.syncing);
      expect(rooms.getSeats(_room.roomId).single, same(replacement));
      expect(
          tester
              .widget<SeatWidget>(_seat(replacement.seatNumber))
              .isCurrentUser,
          isFalse);

      await tester
          .pump(const Duration(minutes: AppConfig.sessionSyncIntervalMinutes));
      verify(() => api.sync(_room.roomId, 'test-session-id', 0)).called(1);
      sync.completeError(ApiException('session missing', 404));
      await tester.pumpAndSettle();

      expect(session.state, SessionState.idle);
      expect(session.sessionId, isNull);
      expect(timer.isRunning, isFalse);
      expect(
          tester
              .widget<SeatWidget>(_seat(replacement.seatNumber))
              .isCurrentUser,
          isFalse);
      expect(find.text(l10n.sessionSeatReleased), findsOneWidget);
      expect(rooms.getSeats(_room.roomId).single, same(replacement));
      verifyNever(() => api.sync(any(), any(), any()));
      verifyNever(() => api.leave(any(), any(), any()));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'refresh keeps the session for matching or unknown timestamps and fetch errors',
      (tester) async {
    when(() => api.getRoomSeats(_room.roomId))
        .thenAnswer((_) async => [Seat.empty(1)]);
    await pumpRoom(tester);
    await sitInRoom(tester);
    when(() => api.getRoomSeats(_room.roomId))
        .thenThrow(ApiException('seat fetch failed', 500));
    const refreshInterval =
        Duration(seconds: AppConfig.seatRefreshIntervalSeconds);
    await tester.pump(refreshInterval);
    expect(rooms.seatError(_room.roomId), isNotNull);
    expect(rooms.getSeats(_room.roomId).single.isOccupied, isFalse);

    for (final startedAt in [_startedAt.toLocal(), null]) {
      when(() => api.getRoomSeats(_room.roomId))
          .thenAnswer((_) async => [_occupiedSeat(1, startedAt)]);
      await tester.pump(refreshInterval);
      final seat = rooms.getSeats(_room.roomId).single;
      expect(seat.user?.userId, session.sessionId);
      expect(seat.sessionStartedAt, _startedAt);
    }
    expect(session.isSeated, isTrue);
    verifyNever(() => api.sync(any(), any(), any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('sync errors use localized feedback', (tester) async {
    when(() => api.getRoomSeats(_room.roomId))
        .thenAnswer((_) async => [Seat.empty(1)]);
    final l10n = await pumpRoom(tester, locale: const Locale('ja'));
    await sitInRoom(tester);
    when(() => api.sync(_room.roomId, 'test-session-id', 0))
        .thenThrow(ApiException('internal details', 500));

    await session.forceSync();
    await tester.pumpAndSettle();

    expect(find.text(l10n.sessionSyncFailed), findsOneWidget);
    expect(find.textContaining('internal details'), findsNothing);
    expect(session.isSeated, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
