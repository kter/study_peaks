import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/services/api_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  test('clearAuthToken removes Authorization from subsequent requests', () async {
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
