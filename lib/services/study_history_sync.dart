import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/study_session.dart';
import '../providers/auth_provider.dart';
import '../repositories/study_history_repository.dart';
import 'api_service.dart';

enum StudyHistorySyncStatus { idle, syncing, synced, failed }

/// Syncs completed records while keeping SQLite available offline.
class StudyHistorySync extends ChangeNotifier {
  StudyHistorySync(this._auth, this._repository, this._api) {
    _lifecycle = AppLifecycleListener(onResume: requestSync);
    _auth.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  final AuthProvider _auth;
  final StudyHistoryRepository _repository;
  final ApiService _api;
  late final AppLifecycleListener _lifecycle;
  String? _ownerId;
  bool _requested = false;
  bool _running = false;
  bool _disposed = false;
  int _revision = 0;
  StudyHistorySyncStatus _status = StudyHistorySyncStatus.idle;

  int get revision => _revision;

  StudyHistorySyncStatus statusFor(String? ownerId) =>
      _ownerId == ownerId ? _status : StudyHistorySyncStatus.idle;

  void _onAuthChanged() {
    final ownerId = _auth.isSignedIn ? _auth.historyOwnerId : null;
    if (_ownerId == ownerId) return;
    _ownerId = ownerId;
    _status = StudyHistorySyncStatus.idle;
    requestSync();
  }

  void recordSaved(String ownerId) {
    if (_ownerId == ownerId) requestSync();
  }

  void requestSync() {
    if (_disposed || _ownerId == null) return;
    _requested = true;
    if (!_running) unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    while (_requested && !_disposed && _ownerId != null) {
      _requested = false;
      final ownerId = _ownerId!;
      _status = StudyHistorySyncStatus.syncing;
      notifyListeners();
      var status = StudyHistorySyncStatus.synced;
      try {
        await _sync(ownerId, _auth.userId);
      } catch (error) {
        debugPrint('Could not sync study history: ${error.runtimeType}');
        status = StudyHistorySyncStatus.failed;
      }
      if (_isCurrent(ownerId)) {
        _status = status;
        _revision++;
        notifyListeners();
      }
    }
    _running = false;
  }

  bool _isCurrent(String ownerId) =>
      !_disposed && _ownerId == ownerId && _auth.historyOwnerId == ownerId;

  Future<void> _sync(String ownerId, String uid) async {
    if (!_isCurrent(ownerId)) return;
    var token = await _auth.getIdToken();
    if (token == null) throw StateError('Missing study history token');

    Future<T?> call<T>(Future<T> Function(String) request) async {
      if (!_isCurrent(ownerId)) return null;
      try {
        return await request(token!);
      } on ApiException catch (error) {
        if (error.statusCode != 401 || !_isCurrent(ownerId)) rethrow;
        final refreshed = await _auth.getIdToken(forceRefresh: true);
        if (!_isCurrent(ownerId)) return null;
        if (refreshed == null) rethrow;
        token = refreshed;
        return request(refreshed);
      }
    }

    try {
      var afterId = 0;
      var rejectedAny = false;
      while (_isCurrent(ownerId)) {
        final pending = await _repository.pendingSyncSessions(ownerId,
            limit: 20, afterId: afterId);
        if (pending.isEmpty || !_isCurrent(ownerId)) break;
        final rejected = await _upload(
            pending,
            (records) =>
                call((token) => _api.uploadStudyRecords(token, uid, records)));
        if (rejected == null || !_isCurrent(ownerId)) return;
        final accepted = pending
            .map((session) => session.sessionId)
            .where((id) => !rejected.contains(id))
            .toList();
        if (accepted.isNotEmpty) {
          await _repository.markSessionsSynced(ownerId, accepted);
        }
        rejectedAny |= rejected.isNotEmpty;
        afterId = pending.last.id!;
      }
      if (rejectedAny) {
        throw StateError('Some study records could not be uploaded');
      }
    } finally {
      if (_isCurrent(ownerId)) {
        await _download(
            ownerId,
            (cursor) =>
                call((token) => _api.getStudyRecords(token, uid, cursor)));
      }
    }
  }

  Future<Set<String>?> _upload(List<StudySession> records,
      Future<Set<String>?> Function(List<StudySession>) send) async {
    try {
      return await send(records);
    } on ApiException catch (error) {
      if (error.statusCode != 400 && error.statusCode != 413) rethrow;
      // A request-level rejection (for example, an oversized batch) must
      // not keep unrelated records from reaching the server.
      if (records.length == 1) return {records.single.sessionId};
      final middle = records.length ~/ 2;
      final first = await _upload(records.sublist(0, middle), send);
      if (first == null) return null;
      final second = await _upload(records.sublist(middle), send);
      return second == null ? null : {...first, ...second};
    }
  }

  Future<void> _download(String ownerId,
      Future<StudyHistoryPage?> Function(String? cursor) fetchPage) async {
    var cursor = await _repository.getSyncCursor(ownerId);
    while (_isCurrent(ownerId)) {
      final page = await fetchPage(cursor);
      if (page == null || !_isCurrent(ownerId)) return;
      if (page.records.isNotEmpty) {
        if (page.nextCursor.isEmpty || page.nextCursor == cursor) {
          throw StateError('Study history cursor did not advance');
        }
        cursor = page.nextCursor;
        await _repository.mergeSyncedSessions(ownerId, page.records, cursor);
      }
      if (!page.hasMore) return;
      if (page.records.isEmpty) {
        throw StateError('Empty study history page with more records');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthChanged);
    _lifecycle.dispose();
    _api.dispose();
    super.dispose();
  }
}
