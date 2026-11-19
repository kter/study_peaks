import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/services/lock_task_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LockTaskService lockTaskService;
  late List<MethodCall> methodCalls;

  setUp(() {
    methodCalls = [];
    lockTaskService = LockTaskService();

    // Set up mock method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.studypeaks.app/lock_task'),
      (MethodCall call) async {
        methodCalls.add(call);
        switch (call.method) {
          case 'startLockTask':
            return true;
          case 'stopLockTask':
            return true;
          case 'isInLockTaskMode':
            return false;
          case 'setKeepScreenOn':
            return true;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.studypeaks.app/lock_task'),
      null,
    );
    lockTaskService.dispose();
  });

  group('LockTaskService', () {
    test('startLockTask invokes correct method channel method', () async {
      final result = await lockTaskService.startLockTask();

      expect(result, true);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'startLockTask');
    });

    test('stopLockTask invokes correct method channel method', () async {
      final result = await lockTaskService.stopLockTask();

      expect(result, true);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'stopLockTask');
    });

    test('isInLockTaskMode returns value from method channel', () async {
      final result = await lockTaskService.isInLockTaskMode();

      expect(result, false);
      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'isInLockTaskMode');
    });

    test('setKeepScreenOn invokes with correct arguments', () async {
      await lockTaskService.setKeepScreenOn(true);

      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'setKeepScreenOn');
      expect(methodCalls.first.arguments, {'enabled': true});
    });

    test('setKeepScreenOn with false invokes with correct arguments', () async {
      await lockTaskService.setKeepScreenOn(false);

      expect(methodCalls.length, 1);
      expect(methodCalls.first.method, 'setKeepScreenOn');
      expect(methodCalls.first.arguments, {'enabled': false});
    });

    test('onLockTaskModeExited stream emits when native callback fires',
        () async {
      bool exitedCalled = false;
      final subscription =
          lockTaskService.onLockTaskModeExited.listen((_) {
        exitedCalled = true;
      });

      // Simulate native callback by sending a method call from "native" side
      final message = const StandardMethodCodec()
          .encodeMethodCall(const MethodCall('onLockTaskModeExited'));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'com.studypeaks.app/lock_task',
        message,
        (ByteData? data) {},
      );

      // Allow the stream to process
      await Future.delayed(Duration.zero);

      expect(exitedCalled, true);
      await subscription.cancel();
    });

    test('startLockTask handles platform exception gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.studypeaks.app/lock_task'),
        (MethodCall call) async {
          throw PlatformException(code: 'ERROR', message: 'Test error');
        },
      );

      final result = await lockTaskService.startLockTask();
      expect(result, false);
    });

    test('stopLockTask handles platform exception gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.studypeaks.app/lock_task'),
        (MethodCall call) async {
          throw PlatformException(code: 'ERROR', message: 'Test error');
        },
      );

      final result = await lockTaskService.stopLockTask();
      expect(result, false);
    });
  });
}
