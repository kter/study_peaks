import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/providers/session_provider.dart';

import '../helpers/test_helpers.dart';

void main() {
  late SessionProvider provider;
  late MockApiService mockApiService;

  setUp(() {
    mockApiService = MockApiService();
    provider = SessionProvider(apiService: mockApiService);
  });

  tearDown(() {
    provider.dispose();
  });

  group('SessionProvider', () {
    test('initial state is idle', () {
      expect(provider.state, SessionState.idle);
      expect(provider.currentRoomId, isNull);
      expect(provider.sessionId, isNull);
      expect(provider.seatNumber, isNull);
      expect(provider.isSeated, false);
    });

    test('sit updates state on success', () async {
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
    });

    test('sit returns false on API error', () async {
      when(() => mockApiService.sit('room-1', 5)).thenThrow(
        Exception('Server error'),
      );

      final result = await provider.sit('room-1', 5);

      expect(result, false);
      expect(provider.state, SessionState.idle);
      expect(provider.error, isNotNull);
    });

    test('leave resets state on success', () async {
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
    });

    test('leave returns false when not seated', () async {
      final result = await provider.leave();
      expect(result, false);
    });

    test('updateDuration updates current duration', () {
      provider.updateDuration(300);
      expect(provider.currentDuration, 300);
    });

    test('leave returns false on API error', () async {
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

      expect(result, false);
      expect(provider.error, isNotNull);
    });
  });
}
