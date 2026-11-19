import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/providers/user_settings_provider.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/network_exception.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';

import '../helpers/test_helpers.dart';

class MockHistory extends Mock implements StudyHistoryRepository {}

class MockAuthProvider extends Mock implements AuthProvider {}

class MockUserSettingsProvider extends Mock implements UserSettingsProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(StudySession(
        roomId: 'room', startTime: DateTime(2026), durationSeconds: 0));
  });
  late MockApiService mockApiService;
  late MockAuthProvider mockAuthProvider;
  late SessionProvider provider;

  setUp(() async {
    await setupMockSharedPreferences();
    mockApiService = MockApiService();
    mockAuthProvider = MockAuthProvider();
    final history = MockHistory();
    when(() => history.saveSession(any())).thenAnswer((_) async {});
    provider = SessionProvider(
      historyRepository: history,
      apiService: mockApiService,
      useMockFallback: false, // Ensure we test production logic
    );
    provider.setAuthProvider(mockAuthProvider);

    // Default stubs to prevent null pointer exceptions on Futures
    when(() => mockAuthProvider.getIdToken(
            forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => 'token');
    when(() => mockAuthProvider.displayName).thenReturn('Test User');
    when(() => mockAuthProvider.userId).thenReturn('test-uid');
    when(() => mockAuthProvider.historyOwnerId).thenReturn('user:test-uid');
  });

  tearDown(() {
    provider.dispose();
  });

  group('SessionProvider 401 Retry Logic', () {
    test('sit retries on 401 error and succeeds', () async {
      final mockResponse = createMockSitResponse(
        sessionId: 'session-retry',
        seatNumber: 10,
      );

      // First call throws 401
      // We need to order the answers for getIdToken to simulate refresh
      // var tokenCallCount = 0; // Removed unused variable
      when(() => mockAuthProvider.getIdToken(
              forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((invocation) async {
        final forceRefresh =
            invocation.namedArguments[#forceRefresh] as bool? ?? false;
        if (forceRefresh) return 'new-token';
        return 'old-token';
      });

      var callCount = 0;
      when(() => mockApiService.sit(
            'room-1',
            10,
            displayName: any(named: 'displayName'),
            userId: any(named: 'userId'),
            countryCode: any(named: 'countryCode'),
          )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw ApiException('Unauthorized', 401);
        }
        return mockResponse;
      });

      // Act
      final result = await provider.sit('room-1', 10);

      // Assert
      expect(result, true);
      expect(provider.state, SessionState.seated);
      expect(provider.sessionId, 'session-retry');

      // Verify token refresh was called
      verify(() => mockAuthProvider.getIdToken(forceRefresh: true)).called(1);
      // Verify setAuthToken was called with new token (we can't easily verify exact sequence without more complex mocks, but this is good enough)
      verify(() => mockApiService.setAuthToken('new-token')).called(1);
      // Verify sit was called twice
      verify(() => mockApiService.sit(
            'room-1',
            10,
            displayName: any(named: 'displayName'),
            userId: any(named: 'userId'),
            countryCode: any(named: 'countryCode'),
          )).called(2);
    });

    test('sit fails if retry also fails', () async {
      // Both calls throw 401 (or retry throws something else)
      when(() => mockApiService.sit(
            'room-1',
            10,
            displayName: any(named: 'displayName'),
            userId: any(named: 'userId'),
            countryCode: any(named: 'countryCode'),
          )).thenThrow(
        ApiException('Unauthorized', 401),
      );

      when(() => mockAuthProvider.getIdToken(forceRefresh: true))
          .thenAnswer((_) async => 'new-token');

      // Act
      final result = await provider.sit('room-1', 10);

      // Assert
      expect(result, false);
      expect(provider.state, SessionState.idle);
      expect(provider.error, isNotNull);

      verify(() => mockAuthProvider.getIdToken(forceRefresh: true)).called(1);
      verify(() => mockApiService.sit(
            'room-1',
            10,
            displayName: any(named: 'displayName'),
            userId: any(named: 'userId'),
            countryCode: any(named: 'countryCode'),
          )).called(2); // Initial + Retry
    });

    test('leave retries on 401 error and succeeds', () async {
      // Setup: sit first
      when(() => mockAuthProvider.getIdToken(
              forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => 'token');

      when(() => mockApiService.sit(
            'room-1',
            10,
            displayName: any(named: 'displayName'),
            userId: any(named: 'userId'),
            countryCode: any(named: 'countryCode'),
          )).thenAnswer(
        (_) async => createMockSitResponse(sessionId: 'session-123'),
      );
      final sitResult = await provider.sit('room-1', 10);
      expect(sitResult, true, reason: 'Setup sit failed');

      provider.updateDuration(100);
      clearInteractions(mockApiService); // Reset sit calls
      clearInteractions(mockAuthProvider);

      // Prepare leave failure then success
      var callCount = 0;
      when(() => mockApiService.leave(any(), any(), any()))
          .thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw ApiException('Unauthorized', 401);
        }
        return createMockLeaveResponse();
      });

      when(() => mockAuthProvider.getIdToken(forceRefresh: true))
          .thenAnswer((_) async => 'new-token');

      // Act
      final result = await provider.leave();

      // Assert
      expect((result as LeaveCompleted).record.durationSeconds, 100);
      verify(() => mockAuthProvider.getIdToken(forceRefresh: true)).called(1);
      verify(() => mockApiService.leave(any(), any(), any())).called(2);
    });

    test('sync retries with the same duration and profile fields', () async {
      const photoUrl = 'https://example.com/avatar.png';
      final settings = MockUserSettingsProvider();
      when(() => settings.displayName).thenReturn('Sync user');
      when(() => settings.countryCode).thenReturn('JP');
      when(() => settings.iconSeed).thenReturn('icon-seed');
      when(() => settings.useGoogleAvatar).thenReturn(true);
      when(() => mockAuthProvider.isSignedIn).thenReturn(true);
      when(() => mockAuthProvider.photoUrl).thenReturn(photoUrl);
      provider.setUserSettingsProvider(settings);
      when(() => mockApiService.sit(
            'room-1',
            10,
            displayName: 'Test User',
            userId: 'test-uid',
          )).thenAnswer((_) async => createMockSitResponse());
      expect(await provider.sit('room-1', 10), true);
      provider.updateDuration(100);

      when(() => mockAuthProvider.getIdToken(forceRefresh: true))
          .thenAnswer((_) async {
        provider.updateDuration(101);
        return 'new-token';
      });
      var calls = 0;
      when(() => mockApiService.sync(
            'room-1',
            'test-session-id',
            100,
            displayName: 'Sync user',
            countryCode: 'JP',
            iconSeed: 'icon-seed',
            photoUrl: photoUrl,
          )).thenAnswer((_) async {
        if (++calls == 1) throw ApiException('Unauthorized', 401);
      });

      await provider.forceSync();

      expect(calls, 2);
      expect(provider.error, isNull);
      verify(() => mockApiService.setAuthToken('new-token')).called(1);
    });
  });

  test('sync distinguishes API responses from transport failures', () async {
    when(() => mockApiService.sit(
          'room-1',
          10,
          displayName: 'Test User',
          userId: 'test-uid',
        )).thenAnswer((_) async => createMockSitResponse());
    expect(await provider.sit('room-1', 10), isTrue);

    final apiError = ApiException('Connection refused', 503);
    when(() => mockApiService.sync(any(), any(), any())).thenThrow(apiError);
    await provider.forceSync();
    expect(provider.error, apiError.toString());

    when(() => mockApiService.sync(any(), any(), any()))
        .thenThrow(const NetworkException('offline'));
    await provider.forceSync();
    expect(provider.error, NetworkErrorKey.networkError);
  });
}
