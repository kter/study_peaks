import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/services/notification_service.dart';
import 'package:study_peaks/models/timer_mode.dart';

class MockFlutterLocalNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class MockNotificationDetails extends Mock implements NotificationDetails {}

void main() {
  late NotificationService notificationService;
  late MockFlutterLocalNotificationsPlugin mockLocalNotifications;

  setUp(() {
    mockLocalNotifications = MockFlutterLocalNotificationsPlugin();
    notificationService = NotificationService();
    notificationService.localNotifications = mockLocalNotifications;
    
    registerFallbackValue(NotificationDetails());
  });

  group('NotificationService', () {
    test('showPhaseFinishedNotification shows notification with correct details',
        () async {
      when(() => mockLocalNotifications.show(
            any(),
            any(),
            any(),
            any(),
            payload: any(named: 'payload'),
          )).thenAnswer((_) async {});

      await notificationService.showPhaseFinishedNotification(
        phase: PomodoroPhase.focus,
        title: 'Focus Finished!',
        body: 'Time for a break.',
      );

      verify(() => mockLocalNotifications.show(
            0,
            'Focus Finished!',
            'Time for a break.',
            any(that: isA<NotificationDetails>()),
            payload: any(named: 'payload'),
          )).called(1);
    });
  });
}
