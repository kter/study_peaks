import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_peaks/providers/study_bgm_controller.dart';
import 'package:study_peaks/providers/timer_provider.dart';

class _TestTimer extends ChangeNotifier implements TimerProvider {
  @override
  String? sessionId;
  @override
  bool isRunning = false;
  @override
  bool isOnBreak = false;
  @override
  bool waitingToStart = true;

  void change({
    String? session = 'seat-1',
    bool running = false,
    bool onBreak = false,
    bool waiting = false,
  }) {
    sessionId = session;
    isRunning = running;
    isOnBreak = onBreak;
    waitingToStart = waiting;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.studypeaks.app/study_bgm');
  final messenger = binding.defaultBinaryMessenger;
  late _TestTimer timer;
  late List<MethodCall> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    timer = _TestTimer();
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    timer.dispose();
  });

  Future<void> sendPlayerEvent(String event, int attempt) async {
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(event, attempt)),
      (_) {},
    );
  }

  testWidgets('starts only when opted in, pauses and stops with the timer',
      (tester) async {
    final bgm = StudyBgmController(timer);
    addTearDown(bgm.dispose);
    await tester.pump();
    expect(bgm.enabled, isFalse);
    expect(bgm.ready, isTrue);
    expect(calls, isEmpty);

    bgm.setEnabled(true);
    expect(calls.last.arguments, containsPair('enabled', true));
    expect(calls.last.arguments, containsPair('playing', false));
    timer.change(running: true);
    expect(calls.last.arguments, containsPair('track', 'rain'));
    expect(calls.last.arguments, containsPair('playing', true));

    final updates = calls.length;
    timer.change(running: true);
    expect(calls, hasLength(updates));

    timer.change();
    expect(calls.last.arguments, containsPair('track', 'rain'));
    expect(calls.last.arguments, containsPair('playing', false));

    timer.change(running: true);
    timer.change(onBreak: true);
    expect(calls.last.arguments, containsPair('track', null));
    expect(calls.last.arguments, containsPair('playing', false));

    timer.change(running: true, onBreak: true);
    expect(calls.last.arguments, containsPair('playing', false));
    timer.change(running: true);
    expect(calls.last.arguments, containsPair('playing', true));

    timer.change(waiting: true);
    expect(calls.last.arguments, containsPair('track', null));
    timer.change(running: true);
    timer.change(session: null, waiting: true);
    expect(bgm.enabled, isFalse);
    expect(calls.last.arguments, containsPair('track', null));
  });

  testWidgets('pinning overlays keep audio; hiding the app pauses it',
      (tester) async {
    final bgm = StudyBgmController(timer);
    addTearDown(bgm.dispose);
    await tester.pump();
    timer.change(running: true);
    bgm.setEnabled(true);
    final before = calls.length;

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(calls, hasLength(before));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(calls.last.arguments, containsPair('playing', false));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(calls.last.arguments, containsPair('playing', true));
  });

  testWidgets('an interruption requires a new action and ignores stale events',
      (tester) async {
    final bgm = StudyBgmController(timer);
    addTearDown(bgm.dispose);
    await tester.pump();
    timer.change(running: true);
    bgm.setEnabled(true);
    final attempt = calls.last.arguments['attempt'] as int;
    bgm.selectTrack(StudyBgmTrack.jazz);
    bgm.setVolume(0.5);

    await sendPlayerEvent('interrupted', attempt);
    expect(bgm.enabled, isFalse);
    expect(bgm.message, StudyBgmMessage.interrupted);
    expect(calls.last.arguments, containsPair('track', null));

    bgm.setEnabled(true);
    await sendPlayerEvent('interrupted', attempt);
    expect(bgm.enabled, isTrue);
    expect(calls.last.arguments, containsPair('track', 'jazz'));
    expect(calls.last.arguments, containsPair('volume', 0.5));
  });

  testWidgets('a headphone disconnect during a break disables the next play',
      (tester) async {
    final bgm = StudyBgmController(timer);
    addTearDown(bgm.dispose);
    await tester.pump();
    timer.change(running: true);
    bgm.setEnabled(true);

    timer.change(onBreak: true);
    expect(calls.last.arguments, containsPair('enabled', true));
    expect(calls.last.arguments, containsPair('track', null));
    final attempt = calls.last.arguments['attempt'] as int;

    await sendPlayerEvent('interrupted', attempt);
    timer.change(running: true);

    expect(bgm.enabled, isFalse);
    expect(calls.last.arguments, containsPair('enabled', false));
    expect(calls.last.arguments, containsPair('playing', false));
  });

  testWidgets('a failed audio load does not stop the timer', (tester) async {
    final bgm = StudyBgmController(timer);
    addTearDown(bgm.dispose);
    await tester.pump();
    timer.change(running: true);
    bgm.setEnabled(true);

    await sendPlayerEvent('failed', calls.last.arguments['attempt'] as int);

    expect(bgm.enabled, isFalse);
    expect(bgm.message, StudyBgmMessage.failed);
    expect(timer.isRunning, isTrue);
  });

  testWidgets('restores the track and volume with playback off',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'study_bgm_track': 'brown_noise',
      'study_bgm_volume': 0.2,
    });
    final bgm = StudyBgmController(timer);
    addTearDown(bgm.dispose);
    timer.change(running: true);
    await tester.pump();

    expect(bgm.track, StudyBgmTrack.brownNoise);
    expect(bgm.volume, 0.2);
    expect(bgm.enabled, isFalse);
    expect(calls, isEmpty);
  });
}
