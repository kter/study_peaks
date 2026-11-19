import 'dart:async';
import 'dart:io';

// fake_async is provided by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/network_exception.dart';

import '../helpers/test_helpers.dart';

void main() {
  final requests = <String, Future<Object?> Function(ApiService)>{
    'rooms': (api) => api.getRooms(),
    'seats': (api) => api.getRoomSeats('room-1'),
    'sit': (api) => api.sit('room-1', 1),
    'sync': (api) => api.sync('room-1', 'session-1', 0),
    'leave': (api) => api.leave('room-1', 'session-1', 0),
  };

  setUpAll(registerMocktailFallbacks);

  for (final entry in requests.entries) {
    final isMutation = entry.key == 'sit' || entry.key == 'leave';
    final timeoutSeconds = isMutation ? 15 : 27;
    test('hung ${entry.key} requests fail after $timeoutSeconds seconds', () {
      fakeAsync((async) {
        final client = MockHttpClient();
        final apiService = ApiService(
          baseUrl: 'https://example.com',
          client: client,
        );
        var attempts = 0;
        Future<http.Response> hang() {
          attempts++;
          return Completer<http.Response>().future;
        }

        when(() => client.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) => hang());
        when(() => client.post(any(),
            headers: any(named: 'headers'),
            body: any(named: 'body'))).thenAnswer((_) => hang());

        Object? error;
        entry.value(apiService).then<void>(
          (_) => fail('A hung request must fail'),
          onError: (Object e) {
            error = e;
          },
        );

        async.elapse(Duration(seconds: timeoutSeconds - 1));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(
            error,
            isA<NetworkException>().having(
              (e) => e.originalError,
              'originalError',
              isA<TimeoutException>(),
            ));
        expect(attempts, isMutation ? 1 : 3);
        if (isMutation) {
          verify(() => client.post(any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'))).called(1);
        }
        expect(async.pendingTimers, isEmpty);
        apiService.dispose();
      });
    });
  }

  test('sit retries a SocketException', () {
    fakeAsync((async) {
      final client = MockHttpClient();
      final apiService = ApiService(
        baseUrl: 'https://example.com',
        client: client,
      );
      var attempts = 0;
      when(() => client.post(any(),
          headers: any(named: 'headers'),
          body: any(named: 'body'))).thenAnswer((_) async {
        if (++attempts == 1) throw const SocketException('offline');
        return http.Response(
          '{"sessionId":"session-1","seatNumber":1,'
          '"sessionStartedAt":"2026-01-01T00:00:00Z"}',
          200,
        );
      });

      SitResponse? result;
      apiService.sit('room-1', 1).then((value) => result = value);
      async.flushMicrotasks();
      expect(attempts, 1);
      expect(result, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(attempts, 2);
      expect(result?.sessionId, 'session-1');
      expect(async.pendingTimers, isEmpty);
      apiService.dispose();
    });
  });

  test('hung session lookups resolve to null after 27 seconds', () {
    fakeAsync((async) {
      final client = MockHttpClient();
      final apiService = ApiService(
        baseUrl: 'https://example.com',
        client: client,
      );
      var attempts = 0;
      when(() => client.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) {
        attempts++;
        return Completer<http.Response>().future;
      });

      var completed = false;
      Object? result = 'pending';
      apiService.getSession('room-1', 'session-1').then((value) {
        completed = true;
        result = value;
      });

      async.elapse(const Duration(seconds: 26));
      expect(completed, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(completed, isTrue);
      expect(result, isNull);
      expect(attempts, 3);
      expect(async.pendingTimers, isEmpty);
      apiService.dispose();
    });
  });

  test('clearAuthToken removes Authorization from subsequent requests',
      () async {
    final client = MockHttpClient();
    final apiService = ApiService(
      baseUrl: 'https://example.com',
      client: client,
    );
    addTearDown(apiService.dispose);
    final uri = Uri.parse('https://example.com/rooms/room-1/seats');
    when(() => client.get(uri, headers: any(named: 'headers')))
        .thenAnswer((_) async => http.Response('{"seats": []}', 200));

    apiService.setAuthToken('previous-user-token');
    await apiService.getRoomSeats('room-1');
    apiService.clearAuthToken();
    await apiService.getRoomSeats('room-1');

    final headers = verify(
      () => client.get(uri, headers: captureAny(named: 'headers')),
    ).captured.cast<Map<String, String>>();
    expect(headers, hasLength(2));
    expect(headers.first['Authorization'], 'Bearer previous-user-token');
    expect(headers.last, isNot(contains('Authorization')));
    expect(headers.last['Content-Type'], 'application/json');
  });
}
