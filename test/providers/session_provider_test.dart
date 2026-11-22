import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/network_exception.dart';

import '../helpers/test_helpers.dart';

class MockAuthProvider extends Mock implements AuthProvider {}

void main() {
  late MockApiService mockApiService;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() async {
    await setupMockSharedPreferences();
    mockApiService = MockApiService();
  });

  group('SessionProvider', () {
    for (final hasAuthProvider in [true, false]) {
      test(
        'sit clears auth token before request when ${hasAuthProvider ? 'token is null' : 'auth provider is absent'}',
        () async {
          final provider = SessionProvider(
            apiService: mockApiService,
            useMockFallback: false,
          );
          addTearDown(provider.dispose);
          await setupMockSharedPreferences();
          if (hasAuthProvider) {
            final authProvider = MockAuthProvider();
            when(() => authProvider.getIdToken()).thenAnswer((_) async => null);
            when(() => authProvider.displayName).thenReturn('Anonymous');
            when(() => authProvider.userId).thenReturn('');
            when(() => authProvider.historyOwnerId)
                .thenReturn(StudySession.guestOwner);
            provider.setAuthProvider(authProvider);
          }
          when(() => mockApiService.sit(
                'room-1',
                5,
                displayName: hasAuthProvider ? 'Anonymous' : null,
                userId: hasAuthProvider ? '' : null,
              )).thenAnswer((_) async => createMockSitResponse(seatNumber: 5));

          expect(await provider.sit('room-1', 5), true);

          verifyInOrder([
            () => mockApiService.clearAuthToken(),
            () => mockApiService.sit(
                  'room-1',
                  5,
                  displayName: hasAuthProvider ? 'Anonymous' : null,
                  userId: hasAuthProvider ? '' : null,
                ),
          ]);
          verifyNever(() => mockApiService.setAuthToken(any()));
        },
      );
    }

    test('initial state is idle', () {
      final provider = SessionProvider(apiService: mockApiService);
      expect(provider.state, SessionState.idle);
      expect(provider.currentRoomId, isNull);
      expect(provider.sessionId, isNull);
      expect(provider.seatNumber, isNull);
      expect(provider.isSeated, false);
      provider.dispose();
    });

    test('sit updates state on success', () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: false, // Disable fallback to test real mock API
      );
      final mockResponse = createMockSitResponse(
        sessionId: 'session-123',
        seatNumber: 5,
      );

      when(() => mockApiService.sit('room-1', 5)).thenAnswer(
        (_) async => mockResponse,
      );

      final result = await provider.sit('room-1', 5);

      expect(result, true);
      expect(provider.state, SessionState.seated);
      expect(provider.sessionId, 'session-123');
      expect(provider.seatNumber, 5);
      expect(provider.currentRoomId, 'room-1');
      expect(provider.isSeated, true);
      expect(await provider.sit('room-1', 6), isFalse);
      expect(provider.error, SessionProvider.sitFailedErrorKey);
      provider.dispose();
    });

    test('the persisted seat timer runs while notification permission is pending',
        () async {
      final permissionRequested = Completer<bool>();
      final permissionAnswered = Completer<void>();
      final notifications = mockStudyNotifications();
      when(() => notifications.ensureStudySession(
            sessionId: 'test-session-id',
            roomName: 'room-1',
            locale: 'en',
            requestPermissionIfNeeded: true,
            isCurrentSession: any(named: 'isCurrentSession'),
            mode: TimerMode.normal,
            pomodoroPhase: any(named: 'pomodoroPhase'),
            isRunning: any(named: 'isRunning'),
            waitingToStart: any(named: 'waitingToStart'),
            seconds: 0,
          )).thenAnswer((invocation) {
        permissionRequested.complete(
          invocation.namedArguments[#isRunning] as bool,
        );
        return permissionAnswered.future;
      });
      final provider = SessionProvider(
        apiService: mockApiService,
        notificationService: notifications,
        useMockFallback: false,
      );
      var now = DateTime.utc(2026, 11, 22);
      final timer = TimerProvider(
        now: () => now,
        notificationService: notifications,
      );
      provider.setTimerProvider(timer);
      addTearDown(() {
        provider.dispose();
        timer.dispose();
      });
      when(() => mockApiService.sit('room-1', 5)).thenAnswer(
        (_) async => createMockSitResponse(seatNumber: 5, sessionStartedAt: now),
      );

      final sit = provider.sit('room-1', 5);
      try {
        expect(
          await Future.any([permissionRequested.future, sit.then((_) => false)]),
          isTrue,
        );
        expect(permissionAnswered.isCompleted, isFalse);
        expect(timer.sessionId, provider.sessionId);
        expect(timer.isRunning, isTrue);
        now = now.add(const Duration(minutes: 2));
        expect(timer.totalStudySeconds, 120);
      } finally {
        permissionAnswered.complete();
        await sit;
      }
      expect(await sit, isTrue);
    });

    test('sit falls back to mock mode on a network error', () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: true, // Explicitly enable mock fallback
      );
      when(() => mockApiService.sit('room-1', 5)).thenThrow(
        const NetworkException('Offline'),
      );

      final result = await provider.sit('room-1', 5);

      expect(result, true);
      expect(provider.state, SessionState.seated);
      expect(provider.sessionId, isNotNull); // Mock session ID
      expect(provider.error, isNull); // No error in mock mode
      provider.dispose();
    });

    test('sit reports an occupied seat with mock fallback enabled', () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: true,
      );
      addTearDown(provider.dispose);
      when(() => mockApiService.sit('room-1', 5))
          .thenThrow(ApiException('SEAT_OCCUPIED', 409));

      expect(await provider.sit('room-1', 5), false);
      expect(provider.sessionId, isNull);
      expect(provider.state, SessionState.idle);
      expect(provider.error, SessionProvider.seatTakenErrorKey);
    });

    test('sit returns false and sets error in production mode', () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: false, // Production mode
      );
      when(() => mockApiService.sit('room-1', 5)).thenThrow(
        Exception('Server error'),
      );

      final result = await provider.sit('room-1', 5);

      // Production mode: failure with error message
      expect(result, false);
      expect(provider.state, SessionState.idle);
      expect(provider.isSeated, false);
      expect(provider.error, SessionProvider.sitFailedErrorKey);
      provider.dispose();
    });

    test('leave resets state on success', () async {
      final provider = SessionProvider(apiService: mockApiService);
      // First sit down
      final mockSitResponse = createMockSitResponse(
        sessionId: 'session-123',
        seatNumber: 5,
      );
      when(() => mockApiService.sit('room-1', 5)).thenAnswer(
        (_) async => mockSitResponse,
      );
      await provider.sit('room-1', 5);

      // Then leave
      final mockLeaveResponse = createMockLeaveResponse();
      when(() => mockApiService.leave('room-1', 'session-123', any()))
          .thenAnswer((_) async => mockLeaveResponse);

      final result = await provider.leave();

      expect((result as LeaveCompleted).record.durationSeconds, 0);
      expect(provider.state, SessionState.idle);
      expect(provider.sessionId, isNull);
      expect(provider.seatNumber, isNull);
      expect(provider.currentRoomId, isNull);
      provider.dispose();
    });

    test('leave also clears the saved timer state', () async {
      await setupMockSharedPreferences({'persisted_timer_state': '{}'});
      final provider = SessionProvider(apiService: mockApiService);
      when(() => mockApiService.sit('room-1', 5)).thenAnswer(
        (_) async => createMockSitResponse(
          sessionId: 'session-123',
          seatNumber: 5,
        ),
      );
      await provider.sit('room-1', 5);
      when(() => mockApiService.leave('room-1', 'session-123', any()))
          .thenAnswer((_) async => createMockLeaveResponse());

      expect(await provider.leave(), isA<LeaveCompleted>());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('persisted_timer_state'), false);
      provider.dispose();
    });

    test('leave reports a request failure with mock fallback enabled',
        () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: true,
      );
      addTearDown(provider.dispose);
      when(() => mockApiService.sit('room-1', 5))
          .thenAnswer((_) async => createMockSitResponse());
      expect(await provider.sit('room-1', 5), true);
      when(() => mockApiService.leave('room-1', 'test-session-id', 0))
          .thenThrow(ApiException('Forbidden', 403));

      final result = await provider.leave() as LeaveCompleted;

      expect(result.serverFailure, LeaveServerFailure.request);
      expect(provider.isFinalizing, false);
      expect(await provider.sit('room-1', 5), true);
    });

    test('leave reports unavailable when not seated', () async {
      final provider = SessionProvider(apiService: mockApiService);
      final result = await provider.leave();
      expect(result, LeaveFailure.unavailable);
      provider.dispose();
    });

    test('updateDuration updates current duration', () {
      final provider = SessionProvider(apiService: mockApiService);
      provider.updateDuration(300);
      expect(provider.currentDuration, 300);
      provider.dispose();
    });

    test('an offline mock seat can be left without contacting the server',
        () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: true,
      );
      addTearDown(provider.dispose);
      when(() => mockApiService.sit('room-1', 5))
          .thenThrow(const NetworkException('Offline'));
      expect(await provider.sit('room-1', 5), true);
      final result = await provider.leave() as LeaveCompleted;

      expect(result.serverFailure, isNull);
      expect(result.record.sessionId, startsWith('mock-session-'));
      expect(provider.state, SessionState.idle);
      verifyNever(() => mockApiService.leave(any(), any(), any()));
    });

    test('clearError clears the error state', () async {
      // Create a provider with production mode (will set error on failure)
      final prodProvider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: false,
      );
      when(() => mockApiService.sit('room-1', 5)).thenThrow(
        Exception('Server error'),
      );

      await prodProvider.sit('room-1', 5);
      expect(prodProvider.error, isNotNull);

      prodProvider.clearError();
      expect(prodProvider.error, isNull);

      prodProvider.dispose();
    });
  });
}
