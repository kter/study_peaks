import 'dart:async';
import '../services/network_exception.dart';
import '../config/app_config.dart';

/// Helper for executing operations with retry logic.
class RetryHelper {
  /// Execute a function with exponential backoff retry.
  /// 
  /// [operation] - The async function to execute.
  /// [shouldRetry] - Optional callback to determine if an error is retriable.
  ///                 Defaults to checking [isNetworkError].
  /// [maxRetries] - Maximum number of retries. Defaults to [AppConfig.maxRetries].
  /// [retryDelays] - Custom delays. Defaults to [AppConfig.retryDelays].
  static Future<T> execute<T>(
    Future<T> Function() operation, {
    bool Function(Object error)? shouldRetry,
    int maxRetries = AppConfig.maxRetries,
    List<Duration> retryDelays = AppConfig.retryDelays,
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        lastError = e;

        final isRetriable = shouldRetry != null 
            ? shouldRetry(e) 
            : isNetworkError(e);

        if (!isRetriable) {
          rethrow;
        }

        // Don't delay after the last attempt
        if (attempt < maxRetries - 1) {
          final delay = attempt < retryDelays.length 
              ? retryDelays[attempt] 
              : retryDelays.last;
          await Future.delayed(delay);
        }
      }
    }

    throw lastError!;
  }
}
