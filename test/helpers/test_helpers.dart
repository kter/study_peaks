import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/models/seat.dart';

/// Mock HTTP client for testing
class MockHttpClient extends Mock implements http.Client {}

/// Mock API service for provider testing
class MockApiService extends Mock implements ApiService {}

/// Register fallback values for mocktail
void registerMocktailFallbacks() {
  registerFallbackValue(Uri.parse('https://example.com'));
}

/// Create a mock SitResponse for testing
SitResponse createMockSitResponse({
  String sessionId = 'test-session-id',
  int seatNumber = 1,
  DateTime? sessionStartedAt,
}) {
  return SitResponse(
    sessionId: sessionId,
    seatNumber: seatNumber,
    sessionStartedAt: sessionStartedAt ?? DateTime.now(),
  );
}

/// Create a mock LeaveResponse for testing
LeaveResponse createMockLeaveResponse({
  int totalSessionDuration = 3600,
  DateTime? endedAt,
}) {
  return LeaveResponse(
    totalSessionDuration: totalSessionDuration,
    endedAt: endedAt ?? DateTime.now(),
  );
}
