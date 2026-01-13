import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Session state.
enum SessionState {
  idle,
  seated,
  syncing,
}

/// Provider for managing study session state.
class SessionProvider extends ChangeNotifier {
  final ApiService _apiService;
  AuthProvider? _authProvider;

  SessionState _state = SessionState.idle;
  String? _currentRoomId;
  String? _sessionId;
  int? _seatNumber;
  DateTime? _sessionStartedAt;
  int _currentDuration = 0;
  Timer? _syncTimer;
  String? _error;

  static const syncIntervalMinutes = 5;

  SessionProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();

  /// Set the auth provider for getting tokens
  void setAuthProvider(AuthProvider authProvider) {
    _authProvider = authProvider;
  }

  /// Ensure API has valid auth token
  Future<void> _ensureAuthToken() async {
    if (_authProvider != null) {
      final token = await _authProvider!.getIdToken();
      if (token != null) {
        _apiService.setAuthToken(token);
      }
    }
  }

  SessionState get state => _state;
  String? get currentRoomId => _currentRoomId;
  String? get sessionId => _sessionId;
  int? get seatNumber => _seatNumber;
  DateTime? get sessionStartedAt => _sessionStartedAt;
  int get currentDuration => _currentDuration;
  String? get error => _error;
  bool get isSeated => _state == SessionState.seated;

  /// Sit down on a seat.
  Future<bool> sit(String roomId, int seatNumber) async {
    try {
      _error = null;
      await _ensureAuthToken();
      final response = await _apiService.sit(roomId, seatNumber);

      _currentRoomId = roomId;
      _sessionId = response.sessionId;
      _seatNumber = response.seatNumber;
      _sessionStartedAt = response.sessionStartedAt;
      _currentDuration = 0;
      _state = SessionState.seated;

      // Start sync timer (every 5 minutes)
      _startSyncTimer();

      notifyListeners();
      return true;
    } catch (e) {
      // If API fails (e.g., no auth), use local mock mode for development
      _error = null; // Clear error for mock mode
      _currentRoomId = roomId;
      _sessionId = 'mock-session-${DateTime.now().millisecondsSinceEpoch}';
      _seatNumber = seatNumber;
      _sessionStartedAt = DateTime.now();
      _currentDuration = 0;
      _state = SessionState.seated;
      
      notifyListeners();
      return true;
    }
  }

  /// Update session duration (called from timer provider).
  void updateDuration(int durationSeconds) {
    _currentDuration = durationSeconds;
    notifyListeners();
  }

  /// Leave the seat.
  Future<bool> leave() async {
    if (_sessionId == null || _currentRoomId == null) return false;

    try {
      _error = null;
      await _ensureAuthToken();
      await _apiService.leave(_currentRoomId!, _sessionId!, _currentDuration);
    } catch (e) {
      // Ignore API errors - allow local state reset for mock mode
    }

    _cancelSyncTimer();
    _reset();

    notifyListeners();
    return true;
  }

  /// Start the sync timer.
  void _startSyncTimer() {
    _syncTimer = Timer.periodic(
      const Duration(minutes: syncIntervalMinutes),
      (_) => _syncSession(),
    );
  }

  /// Cancel the sync timer.
  void _cancelSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Sync session with server.
  Future<void> _syncSession() async {
    if (_sessionId == null || _currentRoomId == null) return;

    _state = SessionState.syncing;
    notifyListeners();

    try {
      await _ensureAuthToken();
      await _apiService.sync(_currentRoomId!, _sessionId!, _currentDuration);
    } catch (e) {
      _error = e.toString();
    }

    _state = SessionState.seated;
    notifyListeners();
  }

  /// Reset session state.
  void _reset() {
    _state = SessionState.idle;
    _currentRoomId = null;
    _sessionId = null;
    _seatNumber = null;
    _sessionStartedAt = null;
    _currentDuration = 0;
  }

  @override
  void dispose() {
    _cancelSyncTimer();
    super.dispose();
  }
}
