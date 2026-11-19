import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../services/network_exception.dart';
import '../services/notification_service.dart';
import '../models/study_session.dart';
import '../services/study_persistence_keys.dart';
import '../repositories/study_history_repository.dart';
import 'auth_provider.dart';
import 'timer_provider.dart';
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
  final StudyHistoryRepository _historyRepository;
  TimerProvider? _timerProvider;
  String? _ownerId;
  StudySession? _pendingRecord;
  bool _leaving = false;
  bool _disposed = false;
  Future<bool>? _restoreOperation;
  static const _keyActive = StudyPersistenceKeys.activeSession;
  String get historyOwnerId {
    final uid = _authProvider?.userId;
    return uid == null || uid.isEmpty ? StudySession.guestOwner : 'user:$uid';
  }

  void setTimerProvider(TimerProvider timer) {
    _timerProvider?.removeListener(_onTimerChanged);
    _timerProvider = timer;
    timer.addListener(_onTimerChanged);
  }

  void _onTimerChanged() {
    if (_timerProvider?.sessionId == _sessionId &&
        _sessionId != null &&
        _pendingRecord == null) {
      _currentDuration = _timerProvider!.totalStudySeconds;
    }
  }

  // Stored localized notification strings
  String? _notificationTitle;
  String _studyingFormat = 'Studying - {duration}'; // Default fallback

  static const syncIntervalMinutes = AppConfig.sessionSyncIntervalMinutes;

  // SharedPreferences keys for session persistence
  static const _keySessionId = StudyPersistenceKeys.legacySessionId;
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
    StudyHistoryRepository? historyRepository,
    bool? useMockFallback,
  })  : _historyRepository = historyRepository ?? StudyHistoryRepository(),
        _apiService = apiService ?? ApiService(),
        useMockFallback = useMockFallback ?? kDebugMode;

  /// Set the auth provider for getting tokens
  void setAuthProvider(AuthProvider authProvider) {
    if (identical(_authProvider, authProvider)) return;
    _authProvider?.removeListener(_onAuthChanged);
    _authProvider = authProvider;
    authProvider.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!_disposed && _sessionId == null) {
      unawaited(restoreSessionIfNeeded());
    }
  }

  /// Set the user settings provider for syncing profile data
  void setUserSettingsProvider(UserSettingsProvider userSettingsProvider) {
    _userSettingsProvider = userSettingsProvider;
  }

  /// Ensure API has valid auth token
  Future<void> _ensureAuthToken() async {
    final token = await _authProvider?.getIdToken();
    if (token != null) {
      _apiService.setAuthToken(token);
    } else {
      _apiService.clearAuthToken();
    }
  }

  SessionState get state => _state;
  String? get currentRoomId => _currentRoomId;
  String? get sessionId => _sessionId;
  int? get seatNumber => _seatNumber;
  DateTime? get sessionStartedAt => _sessionStartedAt;
  int get currentDuration => _currentDuration;
  String? get error => _error;
  bool get isFinalizing => _pendingRecord != null;
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
    String? notificationFocusRemaining,
    String? notificationBreakRemaining,
    String? notificationFocusFinished,
    String? notificationBreakFinished,
  }) async {
    if (_sessionId != null || _leaving) return false;
    final ownerAtStart = historyOwnerId;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_keyActive) != null) {
      _timerProvider?.setRecoveryBlocked(true);
      _error = 'historyOtherOwnerActive';
      notifyListeners();
      return false;
    }
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
      _ownerId = ownerAtStart;
      _state = SessionState.seated;
      await _persistSession();

      // Store notification strings for later updates
      _notificationTitle =
          notificationTitle ?? 'Studying at ${roomName ?? roomId}';
      _studyingFormat = notificationStudyingFormat ?? 'Studying - {duration}';

      // Start sync timer (every 5 minutes)
      _startSyncTimer();

      // Start foreground notification
      await _notificationService.startStudySession(
        notificationTitle: _notificationTitle!,
        notificationText: notificationSessionStarted ?? 'Session started - 0m',
      );

      // Update localization for Pomodoro mode if provided
      if (notificationFocusRemaining != null &&
          notificationBreakRemaining != null &&
          notificationFocusFinished != null &&
          notificationBreakFinished != null) {
        await _notificationService.updatePomodoroLocalization(
          focusRemainingFormat: notificationFocusRemaining,
          breakRemainingFormat: notificationBreakRemaining,
          focusFinishedText: notificationFocusFinished,
          breakFinishedText: notificationBreakFinished,
        );
      }

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
              _ownerId = ownerAtStart;
              _state = SessionState.seated;
              await _persistSession();

              // Store notification strings for later updates
              _notificationTitle =
                  notificationTitle ?? 'Studying at ${roomName ?? roomId}';
              _studyingFormat =
                  notificationStudyingFormat ?? 'Studying - {duration}';

              _startSyncTimer();

              // Start foreground notification
              await _notificationService.startStudySession(
                notificationTitle: _notificationTitle!,
                notificationText:
                    notificationSessionStarted ?? 'Session started - 0m',
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

      if (_sessionId != null && _ownerId != null) {
        _error = 'historySaveFailed';
        notifyListeners();
        return false;
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
        _ownerId = ownerAtStart;
        await _persistSession();
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
    if (_pendingRecord != null) return;
    _currentDuration = durationSeconds;

    notifyListeners();
  }

  /// Leave the seat.
  Future<bool> leave() async {
    if (_sessionId == null || _currentRoomId == null || _leaving) return false;
    _leaving = true;
    try {
      if (_pendingRecord == null) {
        final timer = _timerProvider;
        if (timer != null && timer.sessionId == _sessionId) {
          timer.freezeForFinalization();
          await timer.ensurePersisted();
          _currentDuration = timer.totalStudySeconds;
        }
        _pendingRecord = StudySession(
          sessionId: _sessionId!,
          ownerId: _ownerId ?? StudySession.legacyOwner,
          roomId: _currentRoomId!,
          startTime: _sessionStartedAt ?? DateTime.now(),
          durationSeconds: _currentDuration,
          intervals: timer != null &&
                  timer.sessionId == _sessionId &&
                  timer.hasExactIntervals
              ? timer.focusIntervals
              : null,
        );
      }
      // Freeze finalization before the network request: kill/retry cannot add time.
      await _persistSession();
    } catch (e) {
      _error = 'historySaveFailed';
      _leaving = false;
      notifyListeners();
      return false;
    }

    try {
      _error = null;
      await _ensureAuthToken();
      await _apiService.leave(_currentRoomId!, _sessionId!, _currentDuration);
    } catch (e) {
      bool retrySuccess = e is ApiException && e.statusCode == 404;
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

    try {
      if (_pendingRecord != null && _pendingRecord!.durationSeconds > 0) {
        await _historyRepository.saveSession(_pendingRecord!);
      }
      await _clearPersistedSession();
    } catch (e) {
      _error = 'historySaveFailed';
      _leaving = false;
      notifyListeners();
      return false;
    }
    _cancelSyncTimer();
    await _notificationService.stopStudySession();
    _timerProvider?.endSession();
    _reset();
    _leaving = false;
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
    if (!isSeated || _pendingRecord != null) {
      return;
    }
    await _syncSession();
  }

  /// Sync session with server.
  Future<void> _syncSession() async {
    if (_sessionId == null ||
        _currentRoomId == null ||
        _pendingRecord != null ||
        _ownerId != historyOwnerId) {
      return;
    }

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

      debugPrint(
          '🔄 Sync: iconSeed=$iconSeed, photoUrl=$photoUrl, displayName=$displayName');

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
    _pendingRecord = null;
    _ownerId = null;
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

    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
        _keyActive,
        jsonEncode({
          'sessionId': _sessionId,
          'roomId': _currentRoomId,
          'roomName': _currentRoomName,
          'seatNumber': _seatNumber,
          'startedAt': _sessionStartedAt?.toIso8601String(),
          'ownerId': _ownerId,
          'pending': _pendingRecord?.toMap(),
        }));
    if (!saved) throw StateError('Session write failed');
    // Compatibility keys for notifications and diagnostics.
    await prefs.setString(_keySessionId, _sessionId!);
    await prefs.setString(_keyRoomId, _currentRoomId!);
  }

  Future<void> _clearPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    // Authoritative recovery record is removed last.
    await TimerProvider.clearPersistedState();
    for (final key in [
      _keySessionId,
      _keyRoomId,
      _keyRoomName,
      _keySeatNumber,
      _keySessionStartedAt,
      _keyActive
    ]) {
      if (!await prefs.remove(key)) throw StateError('Session cleanup failed');
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
    if (isSeated) return false;
    return restoreSessionIfNeeded();
  }

  /// Local recovery does not depend on the foreground service or server TTL.
  Future<bool> restoreSessionIfNeeded() {
    return _restoreOperation ??= _restoreLocalSession().whenComplete(() {
      _restoreOperation = null;
    });
  }

  Future<bool> _restoreLocalSession() async {
    if (_sessionId != null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      var saved = prefs.getString(_keyActive);
      if (saved == null) {
        final oldId = prefs.getString(_keySessionId);
        final oldRoom = prefs.getString(_keyRoomId);
        if (oldId == null || oldRoom == null) return false;
        // Pre-v2 active records have no owner. Preserve without guessing.
        saved = jsonEncode({
          'sessionId': oldId,
          'roomId': oldRoom,
          'roomName': prefs.getString(_keyRoomName),
          'seatNumber': prefs.getInt(_keySeatNumber),
          'startedAt': prefs.getString(_keySessionStartedAt),
          'ownerId': StudySession.legacyOwner,
        });
        if (!await prefs.setString(_keyActive, saved)) {
          throw StateError('Migration failed');
        }
      }
      final data = jsonDecode(saved) as Map<String, dynamic>;
      if (data['ownerId'] != historyOwnerId &&
          data['ownerId'] != StudySession.legacyOwner) {
        _timerProvider?.setRecoveryBlocked(true);
        return false;
      }
      _timerProvider?.setRecoveryBlocked(false);
      _ownerId = data['ownerId'] as String;
      _sessionId = data['sessionId'] as String;
      _currentRoomId = data['roomId'] as String;
      _currentRoomName = data['roomName'] as String?;
      _seatNumber = data['seatNumber'] as int?;
      _sessionStartedAt = data['startedAt'] == null
          ? null
          : DateTime.parse(data['startedAt'] as String);
      _pendingRecord = data['pending'] == null
          ? null
          : StudySession.fromMap(
              Map<String, dynamic>.from(data['pending'] as Map));
      _currentDuration = _pendingRecord?.durationSeconds ?? 0;
      // Restore the timer before announcing the session. This also supports
      // owner changes without requiring a screen recreation or an app restart.
      final timer = _timerProvider;
      if (timer != null) {
        final restored = await timer.restoreState(sessionId: _sessionId);
        if (!restored && _pendingRecord == null) {
          timer.start(sessionId: _sessionId);
        }
      }
      if (_disposed) return false;
      _state = SessionState.seated;
      if (_pendingRecord == null) _startSyncTimer();
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'historySaveFailed';
      if (!_disposed) notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _authProvider?.removeListener(_onAuthChanged);
    _timerProvider?.removeListener(_onTimerChanged);
    _cancelSyncTimer();
    super.dispose();
  }
}
