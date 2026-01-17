import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/services/api_service.dart';

import '../helpers/test_helpers.dart';

class MockAuthProvider extends Mock implements AuthProvider {}

void main() {
  late MockApiService mockApiService;
  late MockAuthProvider mockAuthProvider;
  late SessionProvider provider;

  setUp(() {
    mockApiService = MockApiService();
    mockAuthProvider = MockAuthProvider();
    provider = SessionProvider(
      apiService: mockApiService,
      useMockFallback: false, // Ensure we test production logic
    );
    provider.setAuthProvider(mockAuthProvider);
    
    // Default stubs to prevent null pointer exceptions on Futures
    when(() => mockAuthProvider.getIdToken(forceRefresh: any(named: 'forceRefresh')))
        .thenAnswer((_) async => 'token');
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
      when(() => mockAuthProvider.getIdToken(forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((invocation) async {
            final forceRefresh = invocation.namedArguments[#forceRefresh] as bool? ?? false;
            if (forceRefresh) return 'new-token';
            return 'old-token';
          });

      var callCount = 0;
      when(() => mockApiService.sit('room-1', 10)).thenAnswer((_) async {
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
      verify(() => mockApiService.sit('room-1', 10)).called(2);
    });

    test('sit fails if retry also fails', () async {
      // Both calls throw 401 (or retry throws something else)
      when(() => mockApiService.sit('room-1', 10)).thenThrow(
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
      verify(() => mockApiService.sit('room-1', 10)).called(2); // Initial + Retry
    });

    test('leave retries on 401 error and succeeds', () async {
      // Setup: sit first
      when(() => mockAuthProvider.getIdToken(forceRefresh: any(named: 'forceRefresh')))
          .thenAnswer((_) async => 'token');
          
      when(() => mockApiService.sit('room-1', 10)).thenAnswer(
        (_) async => createMockSitResponse(sessionId: 'session-123'),
      );
      final sitResult = await provider.sit('room-1', 10);
      expect(sitResult, true, reason: 'Setup sit failed');

      provider.updateDuration(100);
      clearInteractions(mockApiService); // Reset sit calls
      clearInteractions(mockAuthProvider);

      // Prepare leave failure then success
      var callCount = 0;
      when(() => mockApiService.leave(any(), any(), any())).thenAnswer((_) async {
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
      expect(result, true);
      verify(() => mockAuthProvider.getIdToken(forceRefresh: true)).called(1);
      verify(() => mockApiService.leave(any(), any(), any())).called(2);
    });
  });
}
