import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/utils/retry_helper.dart';

void main() {
  group('RetryHelper', () {
    test('should return result when operation succeeds immediately', () async {
      int callCount = 0;
      final result = await RetryHelper.execute(() async {
        callCount++;
        return 'success';
      });

      expect(result, 'success');
      expect(callCount, 1);
    });

    test('should retry on failure and eventually succeed', () async {
      int callCount = 0;
      final result = await RetryHelper.execute(() async {
        callCount++;
        if (callCount < 3) {
          throw Exception('network error'); // Mock network error
        }
        return 'success';
      }, shouldRetry: (e) => true, retryDelays: [Duration.zero, Duration.zero]);

      expect(result, 'success');
      expect(callCount, 3);
    });

    test('should fail after max retries', () async {
      int callCount = 0;
      
      await expectLater(
        RetryHelper.execute(() async {
          callCount++;
          throw Exception('persistent error');
        }, shouldRetry: (e) => true, maxRetries: 3, retryDelays: const [Duration.zero, Duration.zero]),
        throwsA(predicate((e) => e.toString().contains('persistent error'))),
      );

      expect(callCount, 3);
    });

    test('should rethrow immediately if not retriable', () async {
       int callCount = 0;
      
      await expectLater(
        RetryHelper.execute(() async {
          callCount++;
          throw const FormatException('invalid format');
        }, shouldRetry: (e) => false), // Not retriable
        throwsA(isA<FormatException>()),
      );

      expect(callCount, 1); // No retries
    });
  });
}
