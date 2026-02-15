import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for controlling Android's Lock Task (screen pinning) mode.
///
/// Communicates with native Android code via MethodChannel to
/// start/stop lock task mode and manage keep-screen-on flag.
class LockTaskService {
  static const _channel = MethodChannel('com.studypeaks.app/lock_task');

  final StreamController<bool> _lockTaskExitedController =
      StreamController<bool>.broadcast();

  /// Stream that emits when lock task mode is exited by the user
  /// (e.g., via long-pressing Back + Recent buttons).
  Stream<bool> get onLockTaskModeExited => _lockTaskExitedController.stream;

  LockTaskService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onLockTaskModeExited':
        _lockTaskExitedController.add(true);
        break;
    }
  }

  /// Start lock task (screen pinning) mode.
  /// Android will show a system confirmation dialog.
  Future<bool> startLockTask() async {
    try {
      final result = await _channel.invokeMethod<bool>('startLockTask');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService: startLockTask failed: ${e.message}');
      return false;
    }
  }

  /// Stop lock task (screen pinning) mode.
  Future<bool> stopLockTask() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopLockTask');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService: stopLockTask failed: ${e.message}');
      return false;
    }
  }

  /// Check if the app is currently in lock task mode.
  Future<bool> isInLockTaskMode() async {
    try {
      final result = await _channel.invokeMethod<bool>('isInLockTaskMode');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('LockTaskService: isInLockTaskMode failed: ${e.message}');
      return false;
    }
  }

  /// Set whether the screen should stay on (FLAG_KEEP_SCREEN_ON).
  Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod('setKeepScreenOn', {'enabled': enabled});
    } on PlatformException catch (e) {
      debugPrint('LockTaskService: setKeepScreenOn failed: ${e.message}');
    }
  }

  /// Dispose resources.
  void dispose() {
    _channel.setMethodCallHandler(null);
    _lockTaskExitedController.close();
  }
}
