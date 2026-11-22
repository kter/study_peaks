import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/study_history_sync.dart';

import '../helpers/test_helpers.dart';

class _Auth extends ChangeNotifier implements AuthProvider {
  _Auth(this.userId);

  @override
  String userId;

  @override
  bool get isSignedIn => userId.isNotEmpty;

  @override
  String get historyOwnerId => StudySession.ownerFor(userId);

  Future<String?>? pendingToken;

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async =>
      pendingToken ?? (isSignedIn ? 'token-$userId' : null);

  void switchTo(String uid) {
    userId = uid;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _completed(StudyHistorySync sync, String owner, int revision,
    StudyHistorySyncStatus status) async {
  final done = Completer<void>();
  void check() {
    if (!done.isCompleted &&
        sync.revision >= revision &&
        sync.statusFor(owner) == status) {
      done.complete();
    }
  }

  sync.addListener(check);
  check();
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    sync.removeListener(check);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<StudyHistoryRepository> openDevice() async {
    final directory = await Directory.systemTemp.createTemp('study-history-');
    addTearDown(() => directory.delete(recursive: true));
    final db =
        await StudyHistoryRepository.open('${directory.path}/history.db');
    addTearDown(db.close);
    return StudyHistoryRepository.withDatabase(db);
  }

  StudySession record(String id, String owner) {
    final start = DateTime.utc(2026, 11, 20, 14, 59, 30);
    return StudySession(
      sessionId: id,
      ownerId: owner,
      roomId: 'fuji',
      startTime: start,
      durationSeconds: 60,
      intervals: [
        FocusInterval(
          start: start,
          end: start.add(const Duration(minutes: 1)),
          offsetMinutes: 540,
        ),
      ],
    );
  }

  test('the upload format matches the fixture the Go API accepts', () async {
    final data = jsonDecode(
        await File('api/testdata/study_history_upload.json').readAsString());
    final wireRecord = (data['records'] as List<dynamic>).single;
    final first = DateTime.utc(2026, 11, 20, 14, 59, 58);
    final second = DateTime.utc(2026, 11, 20, 15);
    final original = StudySession(
      sessionId: 'fixture',
      ownerId: 'user:A',
      roomId: 'fuji',
      startTime: first,
      durationSeconds: 3,
      intervals: [
        for (final start in [first, second])
          FocusInterval(
            start: start,
            end: start.add(const Duration(milliseconds: 1600)),
            offsetMinutes: 540,
          ),
      ],
    );
    expect(original.toSyncJson(), wireRecord);
    expect(StudySession.fromSyncJson(wireRecord, 'user:A').dailySeconds,
        {DateTime.utc(2026, 11, 20): 1, DateTime.utc(2026, 11, 21): 2});
  });

  test('history sync never requests a guest Firebase token', () async {
    final events = StreamController<User?>();
    addTearDown(events.close);
    final firebase = MockFirebaseAuth();
    when(() => firebase.authStateChanges()).thenAnswer((_) => events.stream);
    final auth = AuthProvider(auth: firebase, googleSignIn: MockGoogleSignIn());
    addTearDown(auth.dispose);
    final api = MockApiService();
    final sync = StudyHistorySync(auth, StudyHistoryRepository(), api);
    addTearDown(sync.dispose);
    sync.requestSync();

    final guest = MockUser();
    when(() => guest.isAnonymous).thenReturn(true);
    when(() => guest.getIdToken(false)).thenAnswer((_) async => 'guest-token');
    events.add(guest);
    await Future<void>.delayed(Duration.zero);
    expect(auth.user, same(guest));
    sync.recordSaved(StudySession.guestOwner);
    sync.requestSync();
    await Future<void>.delayed(Duration.zero);

    expect(sync.revision, 0);
    expect(sync.statusFor(StudySession.guestOwner), StudyHistorySyncStatus.idle);
    verifyNever(() => firebase.signInAnonymously());
    verifyNever(() => guest.getIdToken(any()));
    verifyZeroInteractions(api);
  });

  test('two devices merge completed records across pages after a failed upload',
      () async {
    const owner = 'user:A';
    final oldDevice = await openDevice();
    final newDevice = await openDevice();
    await oldDevice.saveSession(record('old', owner));
    await oldDevice.saveSession(record('old-2', owner));
    await oldDevice.saveSession(record('guest', StudySession.guestOwner));
    await oldDevice.saveSession(record('other', 'user:B'));
    await oldDevice.saveSession(record('legacy', StudySession.legacyOwner));

    final remote = <String, Map<String, dynamic>>{};
    final posts = <String>[];
    var failFirstUpload = true;
    http.Client client() => MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer token-A');
          expect(request.url.path, '/v1/users/A/study-history');
          if (request.method == 'POST') {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            for (final item in payload['records'] as List<dynamic>) {
              final session = item as Map<String, dynamic>;
              expect(session, isNot(contains('ownerId')));
              final id = session['sessionId'] as String;
              posts.add(id);
              remote.putIfAbsent(id, () => session);
            }
            if (failFirstUpload) {
              failFirstUpload = false;
              return http.Response('', 503);
            }
            return http.Response('{"rejectedSessionIds":[]}', 200);
          }

          // Each test page has one record, including when both devices
          // contribute data in one sync.
          final cursor =
              int.tryParse(request.url.queryParameters['cursor'] ?? '') ?? 0;
          final records = remote.values.skip(cursor).take(1).toList();
          return http.Response(
            jsonEncode({
              'records': records,
              'nextCursor': records.isEmpty ? '' : '${cursor + 1}',
              'hasMore': remote.length > cursor + records.length,
            }),
            200,
          );
        });

    StudyHistorySync syncDevice(StudyHistoryRepository repository) {
      final auth = _Auth('A');
      final sync = StudyHistorySync(
        auth,
        repository,
        ApiService(baseUrl: 'https://example.test/v1', client: client()),
      );
      addTearDown(auth.dispose);
      addTearDown(sync.dispose);
      return sync;
    }

    final oldSync = syncDevice(oldDevice);
    await _completed(oldSync, owner, 1, StudyHistorySyncStatus.failed);
    expect(await oldDevice.getTotalStudyTime(ownerId: owner), 120);
    expect(await oldDevice.pendingSyncSessions(owner, limit: 20), hasLength(2));

    oldSync.requestSync();
    await _completed(oldSync, owner, 2, StudyHistorySyncStatus.synced);
    final newSync = syncDevice(newDevice);
    await _completed(newSync, owner, 1, StudyHistorySyncStatus.synced);
    final migrated = await newDevice.getHistory(ownerId: owner);
    expect(migrated.secondsOn(DateTime.utc(2026, 11, 20)), 60);
    expect(migrated.secondsOn(DateTime.utc(2026, 11, 21)), 60);

    await newDevice.saveSession(record('new', owner));
    newSync.recordSaved(owner);
    await _completed(newSync, owner, 2, StudyHistorySyncStatus.synced);
    oldSync.requestSync();
    await _completed(oldSync, owner, 3, StudyHistorySyncStatus.synced);
    expect(await oldDevice.getTotalStudyTime(ownerId: owner), 180);
    expect(await newDevice.getTotalStudyTime(ownerId: owner), 180);
    expect(
        await newDevice.getTotalStudyTime(ownerId: StudySession.guestOwner), 0);
    expect(await newDevice.getTotalStudyTime(ownerId: 'user:B'), 0);
    expect(posts, ['old', 'old-2', 'old', 'old-2', 'new']);
  });

  test('account switch during token lookup keeps the old upload pending',
      () async {
    final repository = await openDevice();
    await repository.saveSession(record('private', 'user:A'));
    final auth = _Auth('A');
    final token = Completer<String?>();
    auth.pendingToken = token.future;
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.method);
      expect(request.headers['Authorization'], 'Bearer token-B');
      expect(request.url.path, '/v1/users/B/study-history');
      return http.Response(
          '{"records":[],"nextCursor":"","hasMore":false}', 200);
    });
    final sync = StudyHistorySync(auth, repository,
        ApiService(baseUrl: 'https://example.test/v1', client: client));
    addTearDown(auth.dispose);
    addTearDown(sync.dispose);

    auth.pendingToken = null;
    auth.switchTo('B');
    token.complete('token-A');
    await _completed(sync, 'user:B', 1, StudyHistorySyncStatus.synced);
    expect(requests, ['GET']);
    expect(await repository.pendingSyncSessions('user:A', limit: 20),
        hasLength(1));
    expect(await repository.getTotalStudyTime(ownerId: 'user:B'), 0);
  });

  test('a rejected record stays local while other uploads and downloads finish',
      () async {
    const owner = 'user:A';
    final repository = await openDevice();
    await repository.saveSession(record('rejected', owner));
    for (var i = 1; i <= 20; i++) {
      await repository.saveSession(record('ok-$i', owner));
    }
    final posted = <String>[];
    final auth = _Auth('A');
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        final ids = (data['records'] as List<dynamic>)
            .map((item) => item['sessionId'] as String)
            .toList();
        posted.addAll(ids);
        return http.Response(
            jsonEncode({
              'rejectedSessionIds':
                  ids.where((id) => id == 'rejected').toList(),
            }),
            200);
      }
      return http.Response(
          jsonEncode({
            'records': [record('remote', owner).toSyncJson()],
            'nextCursor': '1',
            'hasMore': false,
          }),
          200);
    });
    final sync = StudyHistorySync(auth, repository,
        ApiService(baseUrl: 'https://example.test/v1', client: client));
    addTearDown(auth.dispose);
    addTearDown(sync.dispose);
    await _completed(sync, owner, 1, StudyHistorySyncStatus.failed);
    expect(posted, ['rejected', for (var i = 1; i <= 20; i++) 'ok-$i']);
    final pending = await repository.pendingSyncSessions(owner, limit: 20);
    expect(pending.single.sessionId, 'rejected');
    expect(await repository.getTotalStudyTime(ownerId: owner), 22 * 60);
  });
}
