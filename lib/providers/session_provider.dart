import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/network_exception.dart';
import '../services/notification_service.dart';
import '../models/study_session.dart';
import '../repositories/study_history_repository.dart';
import 'auth_provider.dart';
import 'user_settings_provider.dart';

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
  UserSettingsProvider? _userSettingsProvider;

  SessionState _state = SessionState.idle;
  String? _currentRoomId;
  String? _currentRoomName;
  String? _sessionId;
  int? _seatNumber;
  DateTime? _sessionStartedAt;
  int _currentDuration = 0;
  Timer? _syncTimer;
  String? _error;
  final NotificationService _notificationService = NotificationService();
  final StudyHistoryRepository _historyRepository = StudyHistoryRepository();
  
  // Stored localized notification strings
  String? _notificationTitle;
  String _studyingFormat = 'Studying - {duration}'; // Default fallback

  static const syncIntervalMinutes = AppConfig.sessionSyncIntervalMinutes;

  // SharedPreferences keys for session persistence
  static const _keySessionId = 'persisted_session_id';
  static const _keyRoomId = 'persisted_room_id';
  static const _keyRoomName = 'persisted_room_name';
  static const _keySeatNumber = 'persisted_seat_number';
  static const _keySessionStartedAt = 'persisted_session_started_at';

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

  /// Set the user settings provider for syncing profile data
  void setUserSettingsProvider(UserSettingsProvider userSettingsProvider) {
    _userSettingsProvider = userSettingsProvider;
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
  Future<bool> sit(
    String roomId,
    int seatNumber, {
    String? roomName,
    String? displayName,
    String? countryCode,
    String? iconSeed,
    String? photoUrl,
    String? notificationTitle,
    String? notificationSessionStarted,
    String? notificationStudyingFormat,
  }) async {
    try {
      _error = null;
      await _ensureAuthToken();
      final response = await _apiService.sit(
        roomId,
        seatNumber,
        displayName: displayName ?? _authProvider?.displayName,
        countryCode: countryCode,
        userId: _authProvider?.userId,
        iconSeed: iconSeed,
        photoUrl: photoUrl,
      );

      _currentRoomId = roomId;
      _currentRoomName = roomName;
      _sessionId = response.sessionId;
      _seatNumber = response.seatNumber;
      _sessionStartedAt = response.sessionStartedAt;
      _currentDuration = 0;
      _state = SessionState.seated;
      
      // Store notification strings for later updates
      _notificationTitle = notificationTitle ?? 'Studying at ${roomName ?? roomId}';
      _studyingFormat = notificationStudyingFormat ?? 'Studying - {duration}';

      // Start sync timer (every 5 minutes)
      _startSyncTimer();
      
      // Start foreground notification
      await _notificationService.startStudySession(
        notificationTitle: _notificationTitle!,
        notificationText: notificationSessionStarted ?? 'Session started - 0m',
      );
      
      // Persist session for recovery after app restart
      await _persistSession();

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
                displayName: displayName ?? _authProvider?.displayName,
                countryCode: countryCode,
                userId: _authProvider?.userId,
                iconSeed: iconSeed,
                photoUrl: photoUrl,
              );

              _currentRoomId = roomId;
              _currentRoomName = roomName;
              _sessionId = response.sessionId;
              _seatNumber = response.seatNumber;
              _sessionStartedAt = response.sessionStartedAt;
              _currentDuration = 0;
              _state = SessionState.seated;
              
              // Store notification strings for later updates
              _notificationTitle = notificationTitle ?? 'Studying at ${roomName ?? roomId}';
              _studyingFormat = notificationStudyingFormat ?? 'Studying - {duration}';
              
              _startSyncTimer();
              
              // Start foreground notification
              await _notificationService.startStudySession(
                notificationTitle: _notificationTitle!,
                notificationText: notificationSessionStarted ?? 'Session started - 0m',
              );
              
              // Persist session for recovery after app restart
              await _persistSession();
              
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
    
    // Update foreground notification with current duration
    if (isSeated) {
      final hours = durationSeconds ~/ 3600;
      final minutes = (durationSeconds % 3600) ~/ 60;
      
      String durationText;
      if (hours > 0) {
        durationText = '${hours}h ${minutes}m';
      } else {
        durationText = '${minutes}m';
      }
      
      final notificationText = _studyingFormat.replaceAll('{duration}', durationText);
      _notificationService.updateSessionDuration(notificationText);
    }
    
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
    
    // Stop foreground notification
    await _notificationService.stopStudySession();
    
    // Clear persisted session
    await _clearPersistedSession();

    // Save session to history
    if (_currentDuration > 0 && _currentRoomId != null) {
      try {
        await _historyRepository.saveSession(StudySession(
          roomId: _currentRoomId!,
          startTime: _sessionStartedAt ?? DateTime.now().subtract(Duration(seconds: _currentDuration)),
          durationSeconds: _currentDuration,
        ));
        debugPrint('📜 Session saved to history: $_currentDuration seconds');
      } catch (e) {
        debugPrint('📜 Failed to save session history: $e');
      }
    }
    
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

  /// Force an immediate sync (e.g., when user changes their icon).
  /// This allows icon changes to be reflected immediately for other users.
  Future<void> forceSync() async {
    if (!isSeated) return;
    await _syncSession();
  }

  /// Sync session with server.
  Future<void> _syncSession() async {
    if (_sessionId == null || _currentRoomId == null) return;

    _state = SessionState.syncing;
    notifyListeners();

    try {
      await _ensureAuthToken();
      
      // Get current user settings for sync
      String? displayName;
      String? countryCode;
      String? iconSeed;
      String? photoUrl;
      
      if (_userSettingsProvider != null) {
        displayName = _userSettingsProvider!.displayName;
        countryCode = _userSettingsProvider!.countryCode;
        iconSeed = _userSettingsProvider!.iconSeed;
        
        // Determine photoUrl based on settings and auth state
        if (_authProvider != null &&
            _authProvider!.isSignedIn &&
            _authProvider!.photoUrl != null &&
            _userSettingsProvider!.useGoogleAvatar) {
          photoUrl = _authProvider!.photoUrl;
        }
      }
      
      debugPrint('🔄 Sync: iconSeed=$iconSeed, photoUrl=$photoUrl, displayName=$displayName');
      
      await _apiService.sync(
        _currentRoomId!,
        _sessionId!,
        _currentDuration,
        displayName: displayName,
        countryCode: countryCode,
        iconSeed: iconSeed,
        photoUrl: photoUrl,
      );
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
    _currentRoomName = null;
    _sessionId = null;
    _seatNumber = null;
    _sessionStartedAt = null;
    _currentDuration = 0;
  }

  /// Persist session information to local storage.
  /// Called when a session is started to enable recovery after app restart.
  Future<void> _persistSession() async {
    if (_sessionId == null || _currentRoomId == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySessionId, _sessionId!);
      await prefs.setString(_keyRoomId, _currentRoomId!);
      await prefs.setString(_keyRoomName, _currentRoomName ?? '');
      await prefs.setInt(_keySeatNumber, _seatNumber ?? 0);
      await prefs.setString(_keySessionStartedAt, _sessionStartedAt?.toIso8601String() ?? '');
      debugPrint('📦 Session persisted: $_sessionId');
    } catch (e) {
      debugPrint('📦 Failed to persist session: $e');
    }
  }

  /// Clear persisted session from local storage.
  Future<void> _clearPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keySessionId);
      await prefs.remove(_keyRoomId);
      await prefs.remove(_keyRoomName);
      await prefs.remove(_keySeatNumber);
      await prefs.remove(_keySessionStartedAt);
      debugPrint('📦 Persisted session cleared');
    } catch (e) {
      debugPrint('📦 Failed to clear persisted session: $e');
    }
  }

  /// Restore session from seat map data when user's ID is found on a seat.
  /// Returns true if session was restored, false otherwise.
  /// 
  /// This should be called when the seat map is opened to handle the case where
  /// the app was killed but the user's session still exists on the server.
  /// 
  /// [roomId] - The room ID to check
  /// [seats] - The list of seats from the room
  /// [userId] - The current user's ID to search for
  Future<bool> restoreFromSeatData({
    required String roomId,
    required List<dynamic> seats,
    required String userId,
    String? roomName,
  }) async {
    // Already seated, no need to restore
    if (isSeated) return false;
    
    // Find seat occupied by this user
    dynamic userSeat;
    for (final seat in seats) {
      if (seat.isOccupied && seat.user?.userId == userId) {
        userSeat = seat;
        break;
      }
    }
    
    if (userSeat == null) return false;
    
    debugPrint('🔄 Found user session on seat map, attempting restore...');
    
    try {
      // Try to get session info from server
      await _ensureAuthToken();
      
      // Load persisted session data if available
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString(_keySessionId);
      
      if (sessionId != null) {
        // Validate session with server
        final sessionInfo = await _apiService.getSession(roomId, sessionId);
        
        if (sessionInfo != null) {
          // Restore from server data
          _sessionId = sessionInfo.sessionId;
          _currentRoomId = sessionInfo.roomId;
          _currentRoomName = sessionInfo.roomName;
          _seatNumber = sessionInfo.seatNumber;
          _sessionStartedAt = sessionInfo.sessionStartedAt;
          _currentDuration = sessionInfo.currentDuration;
          _state = SessionState.seated;
          
          _startSyncTimer();
          
          debugPrint('🔄 Session restored from server: $_sessionId in room $_currentRoomName');
          notifyListeners();
          return true;
        }
      }
      
      // Fallback: restore minimal state from seat data
      // This allows the UI to be consistent even if we can't get full session info
      _currentRoomId = roomId;
      _currentRoomName = roomName;
      _seatNumber = userSeat.seatNumber;
      _sessionStartedAt = userSeat.sessionStartedAt;
      _currentDuration = userSeat.currentSessionDuration;
      _state = SessionState.seated;
      
      // Try to get session ID from persisted data or generate placeholder
      _sessionId = sessionId ?? 'restored-${DateTime.now().millisecondsSinceEpoch}';
      
      _startSyncTimer();
      
      debugPrint('🔄 Session restored from seat data: seat $_seatNumber in room $roomId');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('🔄 Error during session restore from seat data: $e');
      return false;
    }
  }

  /// Restore session if there's an active foreground service and valid session.
  /// Returns true if session was restored, false otherwise.
  /// 
  /// This should be called when the app starts to handle the case where
  /// the app was killed but the foreground service continued running.
  Future<bool> restoreSessionIfNeeded() async {
    try {
      // Check if foreground service is running
      final isRunning = await _notificationService.isRunning();
      if (!isRunning) {
        debugPrint('🔄 No foreground service running, no restore needed');
        return false;
      }

      debugPrint('🔄 Foreground service running, attempting session restore...');

      // Load persisted session data
      final prefs = await SharedPreferences.getInstance();
      final sessionId = prefs.getString(_keySessionId);
      final roomId = prefs.getString(_keyRoomId);

      if (sessionId == null || roomId == null) {
        debugPrint('🔄 No persisted session data, stopping foreground service');
        await _notificationService.stopStudySession();
        return false;
      }

      // Validate session with server
      await _ensureAuthToken();
      final sessionInfo = await _apiService.getSession(roomId, sessionId);

      if (sessionInfo == null) {
        debugPrint('🔄 Session no longer valid on server, stopping foreground service');
        await _notificationService.stopStudySession();
        await _clearPersistedSession();
        return false;
      }

      // Restore session state
      _sessionId = sessionInfo.sessionId;
      _currentRoomId = sessionInfo.roomId;
      _currentRoomName = sessionInfo.roomName;
      _seatNumber = sessionInfo.seatNumber;
      _sessionStartedAt = sessionInfo.sessionStartedAt;
      _currentDuration = sessionInfo.currentDuration;
      _state = SessionState.seated;

      // Restart sync timer
      _startSyncTimer();

      debugPrint('🔄 Session restored: $_sessionId in room $_currentRoomName');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('🔄 Error during session restore: $e');
      // On error, stop the foreground service to avoid inconsistent state
      await _notificationService.stopStudySession();
      await _clearPersistedSession();
      return false;
    }
  }

  @override
  void dispose() {
    _cancelSyncTimer();
    super.dispose();
  }
}
