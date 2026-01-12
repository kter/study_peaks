import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

/// Session state.
enum SessionState {
  idle,
  seated,
  syncing,
}

/// Provider for managing study session state.
class SessionProvider extends ChangeNotifier {
  final ApiService _apiService;

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
      _error = e.toString();
      notifyListeners();
      return false;
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
      await _apiService.leave(_currentRoomId!, _sessionId!, _currentDuration);

      _cancelSyncTimer();
      _reset();

      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
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
