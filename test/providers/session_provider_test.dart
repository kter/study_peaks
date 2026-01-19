import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/providers/session_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockApiService mockApiService;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    mockApiService = MockApiService();
  });

  group('SessionProvider', () {
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
      provider.dispose();
    });

    test('sit falls back to mock mode on API error (dev mode)', () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: true, // Explicitly enable mock fallback
      );
      when(() => mockApiService.sit('room-1', 5)).thenThrow(
        Exception('Server error'),
      );

      final result = await provider.sit('room-1', 5);

      // Mock mode: success even with API error
      expect(result, true);
      expect(provider.state, SessionState.seated);
      expect(provider.sessionId, isNotNull); // Mock session ID
      expect(provider.error, isNull); // No error in mock mode
      provider.dispose();
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
      expect(provider.error, contains('Failed to sit'));
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

      expect(result, true);
      expect(provider.state, SessionState.idle);
      expect(provider.sessionId, isNull);
      expect(provider.seatNumber, isNull);
      expect(provider.currentRoomId, isNull);
      provider.dispose();
    });

    test('leave returns false when not seated', () async {
      final provider = SessionProvider(apiService: mockApiService);
      final result = await provider.leave();
      expect(result, false);
      provider.dispose();
    });

    test('updateDuration updates current duration', () {
      final provider = SessionProvider(apiService: mockApiService);
      provider.updateDuration(300);
      expect(provider.currentDuration, 300);
      provider.dispose();
    });

    test('leave succeeds even on API error in dev mode', () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: true, // Development mode
      );
      // First sit down
      final mockSitResponse = createMockSitResponse(
        sessionId: 'session-123',
        seatNumber: 5,
      );
      when(() => mockApiService.sit('room-1', 5)).thenAnswer(
        (_) async => mockSitResponse,
      );
      await provider.sit('room-1', 5);

      // Attempt to leave with API error
      when(() => mockApiService.leave('room-1', 'session-123', any()))
          .thenThrow(Exception('Network error'));

      final result = await provider.leave();

      // Dev mode: success even with API error
      expect(result, true);
      expect(provider.state, SessionState.idle); // State reset
      expect(provider.error, isNull); // No error in dev mode
      provider.dispose();
    });

    test('leave sets error but still resets state in production mode', () async {
      final provider = SessionProvider(
        apiService: mockApiService,
        useMockFallback: false, // Production mode
      );
      // First sit down
      final mockSitResponse = createMockSitResponse(
        sessionId: 'session-123',
        seatNumber: 5,
      );
      when(() => mockApiService.sit('room-1', 5)).thenAnswer(
        (_) async => mockSitResponse,
      );
      await provider.sit('room-1', 5);

      // Attempt to leave with API error
      when(() => mockApiService.leave('room-1', 'session-123', any()))
          .thenThrow(Exception('Network error'));

      final result = await provider.leave();

      // Production mode: success but with error set
      expect(result, true);
      expect(provider.state, SessionState.idle); // State still reset
      expect(provider.error, contains('Failed to leave'));
      provider.dispose();
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

