import 'dart:async';
import 'package:mocktail/mocktail.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/models/seat.dart';

/// Mock HTTP client for testing
class MockHttpClient extends Mock implements http.Client {}

/// Mock API service for provider testing
class MockApiService extends Mock implements ApiService {}

/// Mock Firebase Auth for AuthProvider testing
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

/// Mock Google Sign In for AuthProvider testing
class MockGoogleSignIn extends Mock implements GoogleSignIn {}

/// Mock Google Sign In Account
class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

/// Mock Google Sign In Authentication
class MockGoogleSignInAuthentication extends Mock implements GoogleSignInAuthentication {}

/// Mock Firebase User
class MockUser extends Mock implements User {}

/// Mock User Credential
class MockUserCredential extends Mock implements UserCredential {}

/// Register fallback values for mocktail
void registerMocktailFallbacks() {
  registerFallbackValue(Uri.parse('https://example.com'));
}

/// Setup SharedPreferences for testing with initial values
Future<void> setupMockSharedPreferences([Map<String, Object>? values]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
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
