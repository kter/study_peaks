import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/network_exception.dart';
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
  final bool useMockFallback;
  AuthProvider? _authProvider;

  SessionState _state = SessionState.idle;
  String? _currentRoomId;
  String? _sessionId;
  int? _seatNumber;
  DateTime? _sessionStartedAt;
  int _currentDuration = 0;
  Timer? _syncTimer;
  String? _error;

  static const syncIntervalMinutes = AppConfig.sessionSyncIntervalMinutes;

  /// Creates a SessionProvider.
  /// 
  /// [useMockFallback] controls whether API errors fall back to mock mode.
  /// Defaults to [kDebugMode], so production builds will show errors to users.
  SessionProvider({
    ApiService? apiService,
    bool? useMockFallback,
  })  : _apiService = apiService ?? ApiService(),
        useMockFallback = useMockFallback ?? kDebugMode;

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

  /// Clear the current error state.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Sit down on a seat.
  Future<bool> sit(String roomId, int seatNumber) async {
    try {
      _error = null;
      await _ensureAuthToken();
      final response = await _apiService.sit(
        roomId,
        seatNumber,
        displayName: _authProvider?.displayName,
        userId: _authProvider?.userId,
      );

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
      // 401 Retry Logic
      if (e is ApiException && e.statusCode == 401) {
        try {
          // Force token refresh
          if (_authProvider != null) {
            final newToken =
                await _authProvider!.getIdToken(forceRefresh: true);
            if (newToken != null) {
              _apiService.setAuthToken(newToken);
              // Retry the request once
              final response = await _apiService.sit(
                roomId,
                seatNumber,
                displayName: _authProvider?.displayName,
                userId: _authProvider?.userId,
              );

              _currentRoomId = roomId;
              _sessionId = response.sessionId;
              _seatNumber = response.seatNumber;
              _sessionStartedAt = response.sessionStartedAt;
              _currentDuration = 0;
              _state = SessionState.seated;
              _startSyncTimer();
              notifyListeners();
              return true;
            }
          }
        } catch (retryError) {
          // If retry fails, fall through to normal error handling
          debugPrint('Retry failed: $retryError');
        }
      }

      if (useMockFallback) {
        // Development mode: log and fall back to mock mode
        debugPrint('API error (mock fallback): $e');
        _error = null;
        _currentRoomId = roomId;
        _sessionId = 'mock-session-${DateTime.now().millisecondsSinceEpoch}';
        _seatNumber = seatNumber;
        _sessionStartedAt = DateTime.now();
        _currentDuration = 0;
        _state = SessionState.seated;
        notifyListeners();
        return true;
      } else {
        // Production mode: surface error to UI
        // Use localization key for network errors
        if (isNetworkError(e)) {
          _error = NetworkErrorKey.networkError;
        } else {
          _error = 'Failed to sit: ${e.toString()}';
        }
        notifyListeners();
        return false;
      }
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
      bool retrySuccess = false;
      // 401 Retry Logic
      if (e is ApiException && e.statusCode == 401) {
        try {
          if (_authProvider != null) {
            final newToken =
                await _authProvider!.getIdToken(forceRefresh: true);
            if (newToken != null) {
              _apiService.setAuthToken(newToken);
              await _apiService.leave(
                  _currentRoomId!, _sessionId!, _currentDuration);
              retrySuccess = true;
            }
          }
        } catch (retryError) {
           debugPrint('Retry failed: $retryError');
        }
      }

      if (!retrySuccess) {
        if (useMockFallback) {
          // Development mode: log but allow state reset
          debugPrint('API error (mock fallback): $e');
        } else {
          // Production mode: set error but still reset local state
          // Use localization key for network errors
          if (isNetworkError(e)) {
            _error = NetworkErrorKey.networkError;
          } else {
            _error = 'Failed to leave: ${e.toString()}';
          }
        }
      }
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
      bool retrySuccess = false;
         // 401 Retry Logic
      if (e is ApiException && e.statusCode == 401) {
        try {
          if (_authProvider != null) {
            final newToken =
                await _authProvider!.getIdToken(forceRefresh: true);
            if (newToken != null) {
              _apiService.setAuthToken(newToken);
              await _apiService.sync(
                  _currentRoomId!, _sessionId!, _currentDuration);
              retrySuccess = true;
            }
          }
        } catch (retryError) {
           debugPrint('Retry failed: $retryError');
        }
      }

      if (!retrySuccess) {
         // Use localization key for network errors
        if (isNetworkError(e)) {
          _error = NetworkErrorKey.networkError;
        } else {
          _error = e.toString();
        }
      }
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
