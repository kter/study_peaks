import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/network_exception.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/providers/timer_provider.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';
import 'package:study_peaks/services/notification_service.dart';
import 'package:study_peaks/services/lock_task_service.dart';
import 'package:study_peaks/services/study_persistence_keys.dart';
import '../helpers/test_helpers.dart';

class Notifications extends Mock implements NotificationService {}

class LockTask extends Mock implements LockTaskService {}

class Auth extends Mock implements AuthProvider {}

class History extends Mock implements StudyHistoryRepository {}

class MutableAuth extends ChangeNotifier implements AuthProvider {
  String uid;
  MutableAuth(this.uid);
  @override
  String get userId => uid;
  @override
  String get historyOwnerId => StudySession.ownerFor(userId);
  @override
  String get displayName => uid;
  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => null;
  void changeOwner(String next) {
    uid = next;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  setUpAll(() {
    registerFallbackValue(PomodoroPhase.focus);
    registerFallbackValue(StudySession(
        roomId: 'fuji', startTime: DateTime.utc(2026), durationSeconds: 0));
  });
  setUp(() async {
    await setupMockSharedPreferences();
    now = DateTime.utc(2026, 12, 31, 23, 59, 50);
  });
  TimerProvider timer() {
    final notifications = Notifications();
    when(() => notifications.isRunning()).thenAnswer((_) async => false);
    when(() => notifications.showPhaseFinishedNotification(
        phase: any(named: 'phase'),
        title: any(named: 'title'),
        body: any(named: 'body'))).thenAnswer((_) async {});
    final lock = LockTask();
    when(() => lock.onLockTaskModeExited)
        .thenAnswer((_) => const Stream.empty());
    final t = TimerProvider(
        now: () => now,
        notificationService: notifications,
        lockTaskService: lock);
    addTearDown(t.dispose);
    return t;
  }

  test('timer ticks update duration without notifying session listeners',
      () async {
    final api = MockApiService();
    when(() => api.sit('fuji', 1))
        .thenAnswer((_) async => createMockSitResponse(sessionId: 'a'));
    final t = timer();
    final session = SessionProvider(apiService: api)..setTimerProvider(t);
    try {
      final startedAt = now;
      expect(await session.sit('fuji', 1), true);
      expect(t.sessionId, 'a');
      expect(t.isRunning, true);

      var notifications = 0;
      session.addListener(() => notifications++);
      for (final seconds in [1, 59, 60]) {
        now = startedAt.add(Duration(seconds: seconds));
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        expect(session.currentDuration, seconds);
        expect(notifications, 0);
      }
    } finally {
      session.dispose();
      t.pause();
      await t.ensurePersisted();
    }
  });

  test('normal pause, reset and mode changes retain only focus intervals',
      () async {
    final t = timer();
    t.start(sessionId: 'a');
    now = now.add(const Duration(seconds: 10));
    t.pause();
    now = now.add(const Duration(minutes: 20));
    t.reset();
    t.setMode(TimerMode.pomodoro);
    t.start();
    now = now.add(const Duration(seconds: 30));
    t.pause();
    expect(t.totalStudySeconds, 40);
    expect(t.focusIntervals.length, 2);
    await t.ensurePersisted();
    final restored = timer();
    expect(await restored.restoreState(sessionId: 'a'), true);
    expect(restored.totalStudySeconds, 40);
    expect(restored.focusIntervals.first.end, DateTime.utc(2027, 1, 1));
  });

  test('kill during focus caps expired pomodoro and excludes break and pauses',
      () async {
    final t = timer();
    t.pomodoroFocusDuration = 20;
    t.setMode(TimerMode.pomodoro);
    t.start(sessionId: 'a');
    await t.ensurePersisted();
    now = now.add(const Duration(hours: 2));
    final restored = timer();
    restored.pomodoroFocusDuration = 20;
    expect(await restored.restoreState(sessionId: 'a'), true);
    expect(restored.isRunning, false);
    expect(restored.pomodoroPhase, PomodoroPhase.shortBreak);
    expect(restored.totalStudySeconds, 20);
    restored.start();
    now = now.add(const Duration(seconds: 30));
    restored.pause();
    expect(restored.totalStudySeconds, 20);
  });

  test('running normal recovery includes process downtime exactly once',
      () async {
    final t = timer();
    t.start(sessionId: 'a');
    await t.ensurePersisted();
    now = now.add(const Duration(seconds: 20));
    final restored = timer();
    expect(await restored.restoreState(sessionId: 'a'), true);
    expect(restored.totalStudySeconds, 20);
    restored.pause();
    now = now.add(const Duration(hours: 1));
    await restored.ensurePersisted();
    final again = timer();
    expect(await again.restoreState(sessionId: 'a'), true);
    expect(again.totalStudySeconds, 20);
  });

  test(
      'database failure preserves frozen record across process death and retry',
      () async {
    final api = MockApiService();
    final history = History();
    when(() => api.sit('fuji', 1)).thenAnswer((_) async =>
        createMockSitResponse(sessionId: 'a', sessionStartedAt: now));
    when(() => api.leave('fuji', 'a', any()))
        .thenAnswer((_) async => createMockLeaveResponse());
    var fail = true;
    final records = <StudySession>[];
    when(() => history.saveSession(any())).thenAnswer((call) async {
      if (fail) throw StateError('disk full');
      records.add(call.positionalArguments.single as StudySession);
    });
    final t = timer();
    final session = SessionProvider(
        apiService: api, historyRepository: history, useMockFallback: false)
      ..setTimerProvider(t);
    addTearDown(session.dispose);
    expect(await session.sit('fuji', 1), true);
    now = now.add(const Duration(seconds: 20));
    expect(await session.leave(), LeaveFailure.storageAfterRelease);
    expect(session.isSeated, true);
    t.start();
    expect(t.isRunning, false);
    expect((await SharedPreferences.getInstance()).getString('study_active_v2'),
        isNotNull);
    now = now.add(const Duration(hours: 3));
    final recovered = SessionProvider(
        apiService: api, historyRepository: history, useMockFallback: false);
    addTearDown(recovered.dispose);
    expect(await recovered.restoreSessionIfNeeded(), true);
    expect(recovered.currentDuration, 20);
    fail = false;
    final result = await recovered.leave() as LeaveCompleted;
    expect(result.record, same(records.single));
    verify(() => api.leave('fuji', 'a', 20)).called(1);
    expect(recovered.error, isNull);
    expect(records.single.sessionId, 'a');
    expect(records.single.durationSeconds, 20);
    expect(records.single.intervals!.single.end,
        DateTime.utc(2027, 1, 1, 0, 0, 10));
    expect(await recovered.leave(), LeaveFailure.unavailable);
    expect((await SharedPreferences.getInstance()).getString('study_active_v2'),
        isNull);
  });

  test('sync 404 finalizes the study record and clears the active session',
      () async {
    final api = MockApiService();
    final auth = MutableAuth('moved-user');
    final history = History();
    final t = timer();
    final session = SessionProvider(
      apiService: api,
      historyRepository: history,
      useMockFallback: false,
    )
      ..setTimerProvider(t)
      ..setAuthProvider(auth);
    addTearDown(auth.dispose);
    addTearDown(session.dispose);
    final startedAt = now;
    when(() => api.sit('fuji', 1, displayName: 'moved-user', userId: 'moved-user'))
        .thenAnswer((_) async => createMockSitResponse(
            sessionId: 'moved', sessionStartedAt: startedAt));
    when(() => api.sync('fuji', 'moved', any()))
        .thenThrow(ApiException('Failed to sync', 404));
    when(() => history.saveSession(any())).thenAnswer((_) async {});

    expect(await session.sit('fuji', 1), isTrue);
    now = startedAt.add(const Duration(seconds: 20));
    await t.ensurePersisted();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(StudyPersistenceKeys.activeSession), isTrue);
    expect(prefs.containsKey(StudyPersistenceKeys.timerState), isTrue);
    await prefs.setString(StudyPersistenceKeys.notificationState, '{}');

    await session.forceSync();
    await session.forceSync();

    expect(session.state, SessionState.idle);
    expect(session.sessionId, isNull);
    expect(session.error, 'sessionSeatReleased');
    expect(t.sessionId, isNull);
    expect(t.isRunning, isFalse);
    expect(prefs.containsKey(StudyPersistenceKeys.activeSession), isFalse);
    expect(prefs.containsKey(StudyPersistenceKeys.legacySessionId), isFalse);
    expect(prefs.containsKey(StudyPersistenceKeys.timerState), isFalse);
    expect(prefs.containsKey(StudyPersistenceKeys.notificationState), isFalse);
    final saved = verify(() => history.saveSession(captureAny()));
    saved.called(1);
    final record = saved.captured.single as StudySession;
    expect(record.sessionId, 'moved');
    expect(record.ownerId, auth.historyOwnerId);
    expect(record.roomId, 'fuji');
    expect(record.durationSeconds, 20);
    expect(record.intervals!.single.start, startedAt);
    expect(record.intervals!.single.end, now);
    verify(() => api.sync('fuji', 'moved', any())).called(1);
    verifyNever(() => api.leave(any(), any(), any()));
  });

  test('retry after network and storage failures reuses the frozen record',
      () async {
    final api = MockApiService();
    final history = History();
    when(() => api.sit('fuji', 1))
        .thenAnswer((_) async => createMockSitResponse(sessionId: 'a'));
    final firstRequest = Completer<LeaveResponse>();
    final requestStarted = Completer<void>();
    when(() => api.leave('fuji', 'a', 12)).thenAnswer((_) {
      requestStarted.complete();
      return firstRequest.future;
    });
    when(() => history.saveSession(any())).thenThrow(StateError('disk full'));
    final session = SessionProvider(
      apiService: api,
      historyRepository: history,
      useMockFallback: true,
    );
    addTearDown(session.dispose);
    expect(await session.sit('fuji', 1), true);
    session.updateDuration(12);

    final firstLeave = session.leave();
    await requestStarted.future;
    expect(await session.leave(), LeaveFailure.unavailable);
    firstRequest.completeError(const NetworkException('Offline'));
    expect(await firstLeave, LeaveFailure.storage);
    expect(session.isSeated, true);
    expect(session.isFinalizing, true);
    session.updateDuration(100);
    final failedSave = verify(() => history.saveSession(captureAny()));
    failedSave.called(1);
    final frozenRecord = failedSave.captured.single as StudySession;
    when(() => history.saveSession(any())).thenAnswer((_) async {});

    when(() => api.leave('fuji', 'a', 12))
        .thenThrow(ApiException('Already left', 404));
    final result = await session.leave() as LeaveCompleted;
    expect(result.record, same(frozenRecord));
    expect(result.record.durationSeconds, 12);
    expect(result.serverFailure, isNull);
    verify(() => history.saveSession(frozenRecord)).called(1);
    expect(await session.leave(), LeaveFailure.unavailable);
    expect(await session.sit('fuji', 1), true);
  });

  test('network failure still saves locally and returns a distinct warning',
      () async {
    final api = MockApiService();
    final history = History();
    when(() => api.sit('fuji', 1))
        .thenAnswer((_) async => createMockSitResponse(sessionId: 'offline'));
    when(() => api.leave('fuji', 'offline', 12))
        .thenThrow(const NetworkException('Offline'));
    when(() => history.saveSession(any())).thenAnswer((_) async {});
    final session =
        SessionProvider(apiService: api, historyRepository: history);
    addTearDown(session.dispose);
    expect(await session.sit('fuji', 1), true);
    session.updateDuration(12);

    final result = await session.leave() as LeaveCompleted;
    expect(result.record.durationSeconds, 12);
    expect(result.serverFailure, LeaveServerFailure.connection);
    verify(() => history.saveSession(result.record)).called(1);
    expect(await session.leave(), LeaveFailure.unavailable);
    expect(session.state, SessionState.idle);
  });

  test('sign-in does not transfer guest record and other owners cannot restore',
      () async {
    final api = MockApiService(), auth = Auth();
    final history = History();
    when(() => api.sit('fuji', 1))
        .thenAnswer((_) async => createMockSitResponse(sessionId: 'guest'));
    when(() => api.leave('fuji', 'guest', any()))
        .thenAnswer((_) async => createMockLeaveResponse());
    when(() => auth.userId).thenReturn('A');
    when(() => auth.historyOwnerId).thenReturn('user:A');
    when(() => auth.getIdToken()).thenAnswer((_) async => null);
    StudySession? saved;
    when(() => history.saveSession(any())).thenAnswer((i) async {
      saved = i.positionalArguments.single as StudySession;
    });
    final session =
        SessionProvider(apiService: api, historyRepository: history);
    addTearDown(session.dispose);
    expect(await session.sit('fuji', 1), true);
    session.updateDuration(30);
    session.setAuthProvider(auth);
    final other = SessionProvider(apiService: api, historyRepository: history)
      ..setAuthProvider(auth);
    addTearDown(other.dispose);
    expect(await other.restoreSessionIfNeeded(), false);
    expect(await other.sit('fuji', 1), false);
    expect(await session.leave(), isA<LeaveCompleted>());
    expect(saved!.ownerId, StudySession.guestOwner);
  });
  test(
      'pre-v2 active metadata and timer retain unknown ownership and estimated time',
      () async {
    await setupMockSharedPreferences({
      'persisted_session_id': 'old-session',
      'persisted_room_id': 'fuji',
      'persisted_room_name': 'Mt. Fuji',
      'persisted_seat_number': 6,
      'persisted_session_started_at': '2026-12-31T23:00:00',
      'persisted_timer_state': jsonEncode({
        'sessionId': 'old-session',
        'mode': 0,
        'isRunning': false,
        'pausedDurationMs': 20000,
        'pomodoroPhase': 0,
        'pomodoroCompletedCycles': 0,
        'pomodoroElapsedBeforePause': 0,
      }),
    });
    final api = MockApiService(), history = History();
    when(() => api.leave('fuji', 'old-session', 20))
        .thenAnswer((_) async => createMockLeaveResponse());
    StudySession? saved;
    when(() => history.saveSession(any())).thenAnswer((i) async {
      saved = i.positionalArguments.single as StudySession;
    });
    final t = timer();
    final session = SessionProvider(apiService: api, historyRepository: history)
      ..setTimerProvider(t);
    addTearDown(session.dispose);
    expect(await session.restoreSessionIfNeeded(), true);
    expect(t.sessionId, 'old-session');
    expect(t.isRunning, false);
    expect(t.totalStudySeconds, 20);
    expect(await session.leave(), isA<LeaveCompleted>());
    expect(saved!.ownerId, StudySession.legacyOwner);
    expect(saved!.intervals, isNull);
    expect(saved!.durationSeconds, 20);
  });
  test(
      'binding a new seat discards unseated focus instead of assigning it to the next owner',
      () async {
    final t = timer();
    t.start();
    now = now.add(const Duration(minutes: 30));
    t.reset();
    t.start(sessionId: 'account-A-seat');
    now = now.add(const Duration(seconds: 10));
    t.pause();
    expect(t.totalStudySeconds, 10);
    expect(t.focusIntervals.single.start, DateTime.utc(2027, 1, 1, 0, 29, 50));
    await t.ensurePersisted();
    final recovered = timer();
    expect(await recovered.restoreState(sessionId: 'account-A-seat'), true);
    expect(recovered.totalStudySeconds, 10);
  });

  test('unseated writes cannot overwrite another owners recoverable timer',
      () async {
    final api = MockApiService();
    final auth = Auth();
    when(() => auth.userId).thenReturn('A');
    when(() => auth.historyOwnerId).thenReturn('user:A');
    when(() => auth.displayName).thenReturn('A');
    when(() => auth.getIdToken()).thenAnswer((_) async => null);
    when(() => api.sit('fuji', 1, displayName: 'A', userId: 'A'))
        .thenAnswer((_) async => createMockSitResponse(sessionId: 'A-seat'));
    final original = SessionProvider(apiService: api)..setAuthProvider(auth);
    addTearDown(original.dispose);
    expect(await original.sit('fuji', 1), true);
    final ownerTimer = timer();
    ownerTimer.start(sessionId: 'A-seat');
    now = now.add(const Duration(seconds: 40));
    ownerTimer.pause();
    await ownerTimer.ensurePersisted();
    final originalSnapshot = (await SharedPreferences.getInstance())
        .getString('persisted_timer_state');
    // A cold guest startup refuses A's metadata. Even early timer actions must
    // preserve it, including actions before owner-aware session restoration.
    final guestTimer = timer();
    guestTimer.start();
    guestTimer.pause();
    await Future<void>.delayed(Duration.zero);
    final guest = SessionProvider(apiService: api)
      ..setTimerProvider(guestTimer);
    addTearDown(guest.dispose);
    expect(await guest.restoreSessionIfNeeded(), false);
    guestTimer.setMode(TimerMode.pomodoro);
    guestTimer.start();
    guestTimer.reset();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
        (await SharedPreferences.getInstance())
            .getString('persisted_timer_state'),
        originalSnapshot);
    final recovered = timer();
    expect(await recovered.restoreState(sessionId: 'A-seat'), true);
    expect(recovered.totalStudySeconds, 40);
  });
  test(
      'clock rollback between focus intervals still finalizes and preserves elapsed study',
      () async {
    final t = timer();
    t.start(sessionId: 'rollback');
    now = now.add(const Duration(seconds: 40));
    t.pause();
    now = now.subtract(const Duration(minutes: 5));
    t.start();
    now = now.add(const Duration(seconds: 10));
    t.pause();
    final record = StudySession(
        sessionId: 'rollback',
        roomId: 'fuji',
        startTime: DateTime.utc(2026, 12, 31, 23, 59, 50),
        durationSeconds: t.totalStudySeconds,
        intervals: t.focusIntervals);
    expect(record.durationSeconds, 50);
    expect(
        record.intervals![1].start.isBefore(record.intervals![0].end), false);
    await t.ensurePersisted();
    final recovered = timer();
    expect(await recovered.restoreState(sessionId: 'rollback'), true);
    expect(recovered.totalStudySeconds, 50);
  });

  test(
      'switching back to the guest automatically restores its paused timer without restart',
      () async {
    final api = MockApiService();
    final auth = MutableAuth('');
    addTearDown(auth.dispose);
    when(() => api.sit('fuji', 1, displayName: '', userId: '')).thenAnswer(
        (_) async => createMockSitResponse(sessionId: 'guest-seat'));
    final original = SessionProvider(apiService: api)..setAuthProvider(auth);
    addTearDown(original.dispose);
    expect(await original.sit('fuji', 1), true);
    final t = timer();
    t.start(sessionId: 'guest-seat');
    now = now.add(const Duration(seconds: 30));
    t.pause();
    await t.ensurePersisted();
    auth.changeOwner('A');
    final restoredTimer = timer();
    final recovered = SessionProvider(apiService: api)
      ..setAuthProvider(auth)
      ..setTimerProvider(restoredTimer);
    addTearDown(recovered.dispose);
    expect(await recovered.restoreSessionIfNeeded(), false);
    auth.changeOwner('');
    // Auth change schedules restoration immediately; this joins the in-flight
    // operation rather than requiring an app restart or another room visit.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(recovered.isSeated, true);
    expect(restoredTimer.sessionId, 'guest-seat');
    expect(restoredTimer.totalStudySeconds, 30);
    expect(restoredTimer.isRunning, false);
  });
}
