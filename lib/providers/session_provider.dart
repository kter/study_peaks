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

sealed class LeaveResult {
  const LeaveResult();
}

enum LeaveFailure implements LeaveResult {
  unavailable,
  storage,
  storageAfterRelease,
}

enum LeaveServerFailure { connection, request }

final class LeaveCompleted extends LeaveResult {
  const LeaveCompleted(this.record, this.serverFailure, {required this.showSummary});

  final StudySession record;
  final LeaveServerFailure? serverFailure;
  final bool showSummary;
}

/// Provider for managing study session state.
class SessionProvider extends ChangeNotifier {
  static const seatReleasedMessageKey = 'sessionSeatReleased';
  static const seatTakenErrorKey = 'seatTaken';
  static const sitFailedErrorKey = 'sitFailed';
  static const syncFailedErrorKey = 'sessionSyncFailed';
  final ApiService _apiService;
  final bool useMockFallback;
  static const _mockSessionPrefix = 'mock-session-';
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
  final NotificationService _notificationService;
  final StudyHistoryRepository _historyRepository;
  final void Function(String ownerId)? _onStudyRecordSaved;
  TimerProvider? _timerProvider;
  String? _ownerId;
  StudySession? _pendingRecord;
  bool _leaving = false;
  bool _sitting = false;
  bool _remoteLeaveCompleted = false;
  bool _historySaved = false;
  bool _disposed = false;
  Future<bool>? _restoreOperation;
  static const _keyActive = StudyPersistenceKeys.activeSession;
  String get historyOwnerId =>
      _authProvider?.historyOwnerId ?? StudySession.guestOwner;

  void setTimerProvider(TimerProvider timer) {
    _timerProvider?.removeListener(_onTimerChanged);
    _timerProvider = timer;
    timer.addListener(_onTimerChanged);
  }

  void _onTimerChanged() {
    // The timer widget listens to TimerProvider for its second-by-second display.
    if (_timerProvider?.sessionId == _sessionId &&
        _sessionId != null &&
        _pendingRecord == null) {
      _currentDuration = _timerProvider!.totalStudySeconds;
    }
  }

  String _notificationLocale = 'en';

  void setNotificationLocale(String languageCode) {
    if (_notificationLocale == languageCode) return;
    _notificationLocale = languageCode;
    unawaited(refreshStudyNotification());
  }

  Future<void> refreshStudyNotification({bool requestPermission = false}) async {
    final id = _sessionId;
    final room = _currentRoomName ?? _currentRoomId;
    if (id == null || room == null || id.startsWith(_mockSessionPrefix)) return;
    bool isCurrent() => !_disposed && _sessionId == id && !_leaving && _pendingRecord == null;
    if (!isCurrent()) return;

    final timer = _timerProvider;
    final boundTimer = timer?.sessionId == id ? timer : null;
    final mode = timer?.mode ?? TimerMode.normal;
    await _notificationService.ensureStudySession(
      sessionId: id,
      roomName: room,
      locale: _notificationLocale,
      requestPermissionIfNeeded: requestPermission,
      isCurrentSession: isCurrent,
      mode: mode,
      pomodoroPhase: boundTimer?.pomodoroPhase,
      isRunning: boundTimer?.isRunning ?? false,
      waitingToStart: boundTimer?.waitingToStart ?? true,
      seconds: mode == TimerMode.normal
          ? boundTimer?.elapsedSeconds ?? 0
          : boundTimer?.pomodoroRemainingSeconds ?? timer!.pomodoroFocusDuration,
    );
  }

  // SharedPreferences keys for session persistence
  static const _keySessionId = StudyPersistenceKeys.legacySessionId;
  static const _keyRoomId = 'persisted_room_id';
  static const _keyRoomName = 'persisted_room_name';
  static const _keySeatNumber = 'persisted_seat_number';
  static const _keySessionStartedAt = 'persisted_session_started_at';

  /// Creates a SessionProvider.
  ///
  /// [useMockFallback] controls whether network errors fall back to mock mode.
  /// Defaults to [kDebugMode], so production builds will show errors to users.
  SessionProvider({
    ApiService? apiService,
    StudyHistoryRepository? historyRepository,
    NotificationService? notificationService,
    void Function(String ownerId)? onStudyRecordSaved,
    bool? useMockFallback,
  })  : _historyRepository = historyRepository ?? StudyHistoryRepository(),
        _notificationService = notificationService ?? NotificationService(),
        _onStudyRecordSaved = onStudyRecordSaved,
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

  Future<T> _withAuthRetry<T>(
    Future<T> Function() call, {
    bool Function()? canRetry,
  }) async {
    try {
      return await call();
    } on ApiException catch (error) {
      if (error.statusCode != 401 || canRetry?.call() == false) rethrow;
      try {
        final token = await _authProvider?.getIdToken(forceRefresh: true);
        if (token != null && canRetry?.call() != false) {
          _apiService.setAuthToken(token);
          return await call();
        }
      } catch (retryError) {
        debugPrint('Retry failed: $retryError');
        rethrow;
      }
      rethrow;
    }
  }

  SessionState get state => _state;
  String? get currentRoomId => _currentRoomId;
  String? get currentRoomName => _currentRoomName;
  String? get sessionId => _sessionId;
  int? get seatNumber => _seatNumber;
  DateTime? get sessionStartedAt => _sessionStartedAt;
  int get currentDuration => _currentDuration;
  String? get error => _error;
  bool get isFinalizing => _pendingRecord != null;
  bool get hasReleasedSeat => _remoteLeaveCompleted;
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
  }) async {
    // A duplicate call while a sit is in flight stays silent; the first
    // call reports its own result.
    if (_sitting) return false;
    if (_sessionId != null || _leaving) {
      _error = sitFailedErrorKey;
      notifyListeners();
      return false;
    }
    _sitting = true;
    final ownerAtStart = historyOwnerId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_keyActive) != null) {
        _timerProvider?.setRecoveryBlocked(true);
        _error = 'historyOtherOwnerActive';
        notifyListeners();
        return false;
      }
      _error = null;
      await _ensureAuthToken();
      final sitDisplayName = displayName ?? _authProvider?.displayName;
      final userId = _authProvider?.userId;
      final response = await _withAuthRetry(() => _apiService.sit(
            roomId,
            seatNumber,
            displayName: sitDisplayName,
            countryCode: countryCode,
            userId: userId,
            iconSeed: iconSeed,
            photoUrl: photoUrl,
          ));

      _currentRoomId = roomId;
      _currentRoomName = roomName;
      _sessionId = response.sessionId;
      _seatNumber = response.seatNumber;
      _sessionStartedAt = response.sessionStartedAt;
      _currentDuration = 0;
      _ownerId = ownerAtStart;
      _state = SessionState.seated;
      await _persistSession();

      if (!_disposed && _sessionId == response.sessionId && _pendingRecord == null) {
        _startSyncTimer();
        _timerProvider?.start(sessionId: response.sessionId);
        await refreshStudyNotification(requestPermission: true);
      }

      if (!_disposed) notifyListeners();
      return true;
    } catch (e) {
      if (_sessionId != null && _ownerId != null) {
        _error = 'historySaveFailed';
        notifyListeners();
        return false;
      }
      final errorKey = errorKeyFor(
        e,
        e is ApiException && e.statusCode == 409
            ? seatTakenErrorKey
            : sitFailedErrorKey,
      );
      if (useMockFallback && errorKey == NetworkErrorKey.networkError) {
        // Development mode: log and fall back to mock mode
        debugPrint('API error (mock fallback): $e');
        _error = null;
        _currentRoomId = roomId;
        _sessionId = '$_mockSessionPrefix${DateTime.now().millisecondsSinceEpoch}';
        _seatNumber = seatNumber;
        _sessionStartedAt = DateTime.now();
        _currentDuration = 0;
        _ownerId = ownerAtStart;
        await _persistSession();
        _state = SessionState.seated;
        _timerProvider?.start(sessionId: _sessionId);
        notifyListeners();
        return true;
      }
      _error = errorKey;
      notifyListeners();
      return false;
    } finally {
      _sitting = false;
    }
  }

  /// Update the session duration directly.
  void updateDuration(int durationSeconds) {
    if (_pendingRecord != null) return;
    _currentDuration = durationSeconds;

    notifyListeners();
  }

  /// Completes local finalization and reports whether seat release was confirmed.
  /// A zero-duration session completes without creating a history record.
  Future<LeaveResult> leave() => _finalizeSession();

  Future<LeaveResult> _finalizeSession({bool seatAlreadyReleased = false}) async {
    if (_sessionId == null || _currentRoomId == null || _leaving) {
      return LeaveFailure.unavailable;
    }
    _leaving = true;
    _error = null;
    if (seatAlreadyReleased) _remoteLeaveCompleted = true;
    try {
      if (_pendingRecord == null) {
        final timer = _timerProvider;
        final boundTimer = timer?.sessionId == _sessionId ? timer : null;
        _pendingRecord = _freezeStudyRecord(boundTimer);
        await boundTimer?.ensurePersisted();
      }
      final record = _pendingRecord!;
      // Persist finalization before contacting the API so recovery cannot add time.
      await _persistSession();

      LeaveServerFailure? serverFailure;
      var retryRelease = false;
      if (!_remoteLeaveCompleted) {
        try {
          await _leaveOnServer(record);
          _remoteLeaveCompleted = true;
        } catch (error) {
          final connectionFailure = isTransportError(error);
          serverFailure = connectionFailure
              ? LeaveServerFailure.connection
              : LeaveServerFailure.request;
          retryRelease = connectionFailure ||
              (error is ApiException &&
                  (error.statusCode >= 500 || error.statusCode == 408 || error.statusCode == 429));
        }
        if (_remoteLeaveCompleted) await _persistSession();
      }

      final showSummary = !_historySaved && record.durationSeconds > 0;
      if (showSummary) {
        await _historyRepository.saveSession(record);
        _historySaved = true;
        _onStudyRecordSaved?.call(record.ownerId);
      }
      if (retryRelease) {
        // Retain the frozen session ID for an explicit, idempotent leave retry.
        _cancelSyncTimer();
        await _persistSession();
        await _stopStudyNotification();
        return LeaveCompleted(record, serverFailure, showSummary: showSummary);
      }

      await _clearPersistedSession();
      _cancelSyncTimer();
      _timerProvider?.endSession();
      _reset();
      await _stopStudyNotification();
      if (seatAlreadyReleased) _error = seatReleasedMessageKey;
      return LeaveCompleted(record, serverFailure, showSummary: showSummary);
    } catch (error) {
      debugPrint('Could not finalize study record: ${error.runtimeType}');
      if (seatAlreadyReleased) _error = 'historySaveFailed';
      return _remoteLeaveCompleted
          ? LeaveFailure.storageAfterRelease
          : LeaveFailure.storage;
    } finally {
      if (_state == SessionState.syncing) _state = SessionState.seated;
      _leaving = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _stopStudyNotification() async {
    try {
      await _notificationService.stopStudySession();
    } catch (error) {
      debugPrint('Could not stop study notification: ${error.runtimeType}');
    }
  }

  StudySession _freezeStudyRecord(TimerProvider? boundTimer) {
    if (boundTimer != null) {
      boundTimer.freezeForFinalization();
      _currentDuration = boundTimer.totalStudySeconds;
    }
    return StudySession(
      sessionId: _sessionId!,
      ownerId: _ownerId ?? StudySession.legacyOwner,
      roomId: _currentRoomId!,
      startTime: _sessionStartedAt ?? DateTime.now(),
      durationSeconds: _currentDuration,
      intervals: boundTimer != null && boundTimer.hasExactIntervals
          ? boundTimer.focusIntervals
          : null,
    );
  }

  Future<void> _leaveOnServer(StudySession record) async {
    if (record.sessionId.startsWith(_mockSessionPrefix)) return;

    try {
      await _ensureAuthToken();
      await _withAuthRetry(() => _apiService.leave(
            record.roomId,
            record.sessionId,
            record.durationSeconds,
          ));
    } on ApiException catch (error) {
      // The response may have been lost or the server session may have expired.
      if (error.statusCode != 404) rethrow;
    }
  }

  /// Start the sync timer.
  void _startSyncTimer() {
    _syncTimer = Timer.periodic(
      const Duration(minutes: AppConfig.sessionSyncIntervalMinutes),
      (_) => _syncSession(),
    );
  }

  /// Cancel the sync timer.
  void _cancelSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Force an immediate sync for an active session, if none is in progress.
  Future<void> forceSync() => _syncSession();

  /// Sync session with server.
  Future<void> _syncSession() async {
    final sessionId = _sessionId;
    final roomId = _currentRoomId;
    if (_disposed ||
        !isSeated ||
        sessionId == null ||
        roomId == null ||
        sessionId.startsWith(_mockSessionPrefix) ||
        _leaving ||
        _pendingRecord != null ||
        _remoteLeaveCompleted ||
        _ownerId != historyOwnerId) {
      return;
    }

    bool stillSyncing() =>
        !_disposed &&
        _sessionId == sessionId &&
        !_leaving &&
        _pendingRecord == null;

    _state = SessionState.syncing;
    notifyListeners();

    try {
      await _ensureAuthToken();
      if (!stillSyncing()) return;

      // Get current user settings for sync
      String? displayName;
      String? countryCode;
      String? iconSeed;
      String? photoUrl;

      final settings = _userSettingsProvider;
      if (settings != null) {
        displayName = settings.displayName;
        countryCode = settings.countryCode;
        iconSeed = settings.iconSeed;
        photoUrl = googleAvatarUrl(_authProvider, settings);
      }

      final duration = _currentDuration;
      await _withAuthRetry(
        () => _apiService.sync(
          roomId,
          sessionId,
          duration,
          displayName: displayName,
          countryCode: countryCode,
          iconSeed: iconSeed,
          photoUrl: photoUrl,
        ),
        canRetry: stillSyncing,
      );
    } catch (e) {
      if (!stillSyncing()) return;
      if (e is ApiException && e.statusCode == 404) {
        await _finalizeSession(seatAlreadyReleased: true);
        return;
      }
      _error = errorKeyFor(e, syncFailedErrorKey);
    }

    if (stillSyncing()) {
      _state = SessionState.seated;
      notifyListeners();
    }
  }

  /// Reset session state.
  void _reset() {
    _pendingRecord = null;
    _remoteLeaveCompleted = false;
    _historySaved = false;
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
          'remoteLeaveCompleted': _remoteLeaveCompleted,
          'historySaved': _historySaved,
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

  /// Local recovery does not depend on the foreground service or server TTL.
  Future<bool> restoreSessionIfNeeded() {
    return _restoreOperation ??= _restoreLocalSession().whenComplete(() {
      _restoreOperation = null;
    });
  }

  Future<bool> _restoreLocalSession() async {
    if (_sessionId != null || _sitting) return false;
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
      _remoteLeaveCompleted = data['remoteLeaveCompleted'] == true;
      _historySaved = _pendingRecord != null && data['historySaved'] == true;
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
      if (_pendingRecord == null) {
        _startSyncTimer();
        unawaited(refreshStudyNotification());
      }
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
