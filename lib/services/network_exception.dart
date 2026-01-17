import 'dart:async';
import 'dart:io';

/// Exception for network-related errors.
/// 
/// This is thrown when a network operation fails due to connectivity issues,
/// DNS resolution failures, timeouts, etc.
class NetworkException implements Exception {
  final String message;
  final Object? originalError;

  const NetworkException(this.message, [this.originalError]);

  @override
  String toString() => 'NetworkException: $message';
}

/// Error key for localization.
/// Use this key to look up the localized error message.
class NetworkErrorKey {
  static const String networkError = 'networkError';
  static const String connectionRestored = 'connectionRestored';
}

/// Check if an error is a network-related error.
/// 
/// Returns true for:
/// - SocketException (DNS resolution failure, connection refused, etc.)
/// - TimeoutException
/// - NetworkException (our custom exception)
/// - HttpException with network-related messages
bool isNetworkError(Object error) {
  if (error is NetworkException) return true;
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  if (error is HttpException) {
    // Check for common network-related HttpException messages
    final message = error.message.toLowerCase();
    return message.contains('connection') ||
        message.contains('network') ||
        message.contains('host');
  }
  
  // Check error message for common network error patterns
  final errorString = error.toString().toLowerCase();
  return errorString.contains('socketexception') ||
      errorString.contains('failed host lookup') ||
      errorString.contains('connection refused') ||
      errorString.contains('network is unreachable') ||
      errorString.contains('no address associated') ||
      errorString.contains('connection reset') ||
      errorString.contains('connection timed out');
}
