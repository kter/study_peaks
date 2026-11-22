import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/config/app_config.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/models.dart';
import 'package:study_peaks/models/study_history.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/room_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/providers/study_bgm_controller.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/providers/user_settings_provider.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';
import 'package:study_peaks/screens/room_detail_screen.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/lock_task_service.dart';
import 'package:study_peaks/services/network_exception.dart';
import 'package:study_peaks/widgets/dialogs/leave_summary_dialog.dart';
import 'package:study_peaks/widgets/seat_widget.dart';

import '../helpers/test_helpers.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

class _MockHistory extends Mock implements StudyHistoryRepository {}

class _MockLockTaskService extends Mock implements LockTaskService {}

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
      {Locale? locale,
      AuthProvider? auth,
      StudyHistoryRepository? history,
      DateTime Function()? now,
      MockNotificationService? notifications,
      LockTaskService? lockTaskService,
      bool asRoute = false}) async {
    final guestAuth = _MockAuthProvider();
    when(() => guestAuth.isSignedIn).thenReturn(false);
    notifications ??= mockStudyNotifications();
    session = SessionProvider(
      apiService: api,
      historyRepository: history,
      notificationService: notifications,
      useMockFallback: false,
    );
    timer = TimerProvider(
      now: now ?? () => _startedAt,
      notificationService: notifications,
      lockTaskService: lockTaskService,
    );
    session.setTimerProvider(timer);
    if (auth != null) session.setAuthProvider(auth);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => rooms),
        ChangeNotifierProvider<AuthProvider>.value(value: auth ?? guestAuth),
        if (history != null)
          Provider<StudyHistoryRepository>.value(value: history),
        ChangeNotifierProvider(create: (_) => UserSettingsProvider()),
        ChangeNotifierProvider(create: (_) => timer),
        ChangeNotifierProvider(create: (_) => session),
        ChangeNotifierProvider(create: (_) => StudyBgmController(timer)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale ?? const Locale('en'),
        home: asRoute ? const Scaffold() : const RoomDetailScreen(room: _room),
      ),
    ));
    if (asRoute) {
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.push<void>(MaterialPageRoute(
        builder: (_) => const RoomDetailScreen(room: _room),
      )));
    }
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

  testWidgets('covering the room keeps the free timer running until it is popped',
      (tester) async {
    when(() => api.getRoomSeats(_room.roomId))
        .thenAnswer((_) async => [Seat.empty(1)]);
    var now = _startedAt;
    await pumpRoom(tester, asRoute: true, now: () => now);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final bgm = tester.element(find.byType(RoomDetailScreen))
        .read<StudyBgmController>();
    timer.start();
    now = now.add(const Duration(seconds: 12));

    unawaited(navigator.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Another screen')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Another screen'), findsOneWidget);
    expect(timer.isRunning, isTrue);
    expect(bgm.timerAllowsPlayback, isTrue);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(timer.elapsedSeconds, 12);
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsNothing);
    expect(timer.isRunning, isFalse);
    expect(timer.elapsedSeconds, 0);
    expect(timer.focusIntervals, isEmpty);
    expect(bgm.timerAllowsPlayback, isFalse);
  });

  testWidgets('popping the room keeps a seated timer running', (tester) async {
    when(() => api.getRoomSeats(_room.roomId))
        .thenAnswer((_) async => [Seat.empty(1)]);
    await pumpRoom(tester, asRoute: true);
    await sitInRoom(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.byType(RoomDetailScreen), findsNothing);
    expect(session.isSeated, isTrue);
    expect(timer.isRunning, isTrue);
    expect(timer.sessionId, session.sessionId);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final pinned in [true, false]) {
    testWidgets('pin and sit waits for Android before starting (pinned: $pinned)',
        (tester) async {
      when(() => api.getRoomSeats(_room.roomId))
          .thenAnswer((_) async => [Seat.empty(1)]);
      when(() => api.sit(
            _room.roomId,
            1,
            displayName: any(named: 'displayName'),
            countryCode: any(named: 'countryCode'),
            iconSeed: any(named: 'iconSeed'),
          )).thenAnswer(
        (_) async => createMockSitResponse(sessionStartedAt: _startedAt),
      );
      final pinConfirmation = Completer<bool>();
      final lockTaskService = _MockLockTaskService();
      when(() => lockTaskService.onLockTaskModeExited)
          .thenAnswer((_) => const Stream.empty());
      when(() => lockTaskService.startLockTask())
          .thenAnswer((_) => pinConfirmation.future);
      when(() => lockTaskService.stopLockTask()).thenAnswer((_) async => true);
      when(() => lockTaskService.setKeepScreenOn(any()))
          .thenAnswer((_) async {});

      final permissionAnswered = Completer<void>();
      final notifications = mockStudyNotifications();
      var permissionRequests = 0;
      when(() => notifications.ensureStudySession(
            sessionId: 'test-session-id',
            roomName: _room.name,
            locale: 'en',
            requestPermissionIfNeeded: true,
            isCurrentSession: any(named: 'isCurrentSession'),
            mode: TimerMode.normal,
            pomodoroPhase: any(named: 'pomodoroPhase'),
            isRunning: any(named: 'isRunning'),
            waitingToStart: any(named: 'waitingToStart'),
            seconds: 0,
          )).thenAnswer((invocation) {
        permissionRequests++;
        expect(invocation.namedArguments[#isRunning], isTrue);
        expect(timer.sessionId, session.sessionId);
        return permissionAnswered.future;
      });

      final l10n = await pumpRoom(tester,
          notifications: notifications, lockTaskService: lockTaskService);
      timer.setScreenLockEnabled(true);
      if (pinned) timer.start();
      await tester.tap(_seat(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.sitAndPin));
      await tester.pumpAndSettle();

      verify(() => lockTaskService.startLockTask()).called(1);
      expect(session.isSeated, isTrue);
      expect(timer.isRunning, isFalse);
      expect(timer.focusIntervals, isEmpty);
      expect(permissionRequests, 0);

      pinConfirmation.complete(pinned);
      await tester.pumpAndSettle();

      expect(timer.isRunning, isTrue);
      expect(timer.sessionId, 'test-session-id');
      expect(timer.isScreenLocked, pinned);
      expect(permissionRequests, 1);
      verifyNever(() => lockTaskService.stopLockTask());

      permissionAnswered.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('leaving after guest sign-in shows guest history totals',
      (tester) async {
    const guestOwner = StudySession.guestOwner;
    final date = DateTime.now();
    final start = DateTime(date.year, date.month, date.day, 12);
    var now = start;
    final auth = _MockAuthProvider();
    when(() => auth.isSignedIn).thenReturn(false);
    when(() => auth.historyOwnerId).thenReturn(guestOwner);
    when(() => auth.displayName).thenReturn('Anonymous');
    when(() => auth.userId).thenReturn('');
    when(() => auth.getIdToken()).thenAnswer((_) async => 'guest-token');
    final earlierRecord = StudySession(
      roomId: _room.roomId,
      startTime: start.subtract(const Duration(hours: 1)),
      durationSeconds: 30,
    );
    final history = _MockHistory();
    registerFallbackValue(earlierRecord);
    final records = [earlierRecord];
    when(() => history.saveSession(any())).thenAnswer((invocation) async {
      records.add(invocation.positionalArguments.single as StudySession);
    });
    when(() => history.getHistory(ownerId: guestOwner))
        .thenAnswer((_) async => StudyHistory(records));
    when(() => api.getRoomSeats(_room.roomId))
        .thenAnswer((_) async => [Seat.empty(1)]);
    when(() => api.sit(_room.roomId, 1, displayName: 'Anonymous', userId: ''))
        .thenAnswer((_) async => createMockSitResponse(sessionStartedAt: start));
    when(() => api.sync(_room.roomId, 'test-session-id', 0))
        .thenAnswer((_) async {});
    when(() => api.leave(_room.roomId, 'test-session-id', 20))
        .thenAnswer((_) async => createMockLeaveResponse());

    final l10n =
        await pumpRoom(tester, auth: auth, history: history, now: () => now);
    expect(await session.sit(_room.roomId, 1), isTrue);
    await session.forceSync();
    now = start.add(const Duration(seconds: 20));
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.historyOwnerId).thenReturn('user:account');
    when(() => auth.userId).thenReturn('account');
    when(() => auth.getIdToken()).thenAnswer((_) async => 'account-token');
    expect(session.sessionOwnerId, guestOwner);
    await session.forceSync();
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.leaveSeat));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, l10n.leave));
    await tester.pumpAndSettle();

    final dialog = find.byType(LeaveSummaryDialog);
    Finder textInSummary(String label) =>
        find.descendant(of: dialog, matching: find.text(label));
    expect(textInSummary('Study time recorded'), findsOneWidget);
    expect(textInSummary('20s'), findsOneWidget);
    expect(textInSummary('50s'), findsNWidgets(2));
    expect(textInSummary('Saved to the guest history on this device.'), findsOneWidget);
    expect(textInSummary(l10n.studyHistory), findsNothing);
    expect(records.last.ownerId, guestOwner);
    verify(() => history.getHistory(ownerId: guestOwner)).called(1);
    verifyInOrder([
      () => api.setAuthToken('guest-token'),
      () => api.sit(_room.roomId, 1, displayName: 'Anonymous', userId: ''),
      () => api.setAuthToken('guest-token'),
      () => api.sync(_room.roomId, 'test-session-id', 0),
      () => api.setAuthToken('account-token'),
      () => api.leave(_room.roomId, 'test-session-id', 20),
    ]);
    verifyNever(() => api.sync(any(), any(), any()));
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
