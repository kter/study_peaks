import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/services/api_service.dart';
import 'package:study_peaks/services/network_exception.dart';

void main() {
  test('errorKeyFor maps connection failures to the network key', () {
    final errors = [
      const NetworkException('offline'),
      const SocketException('offline'),
      TimeoutException('offline'),
      const HttpException('connection failed'),
      Exception('Connection refused'),
    ];

    for (final error in errors) {
      expect(errorKeyFor(error, 'fallback'), NetworkErrorKey.networkError);
    }
  });

  test('errorKeyFor returns the fallback for non-network failures', () {
    expect(errorKeyFor(StateError('invalid state'), 'fallback'), 'fallback');
  });

  test('errorKeyFor treats API errors as server responses', () {
    final error = ApiException('Connection refused', 503);

    expect(errorKeyFor(error, 'fallback'), 'fallback');
  });
}
