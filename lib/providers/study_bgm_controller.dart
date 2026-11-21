import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'timer_provider.dart';

enum StudyBgmTrack {
  rain('rain'),
  waves('waves'),
  musicBox('music_box'),
  dreamy('dreamy'),
  piano('piano'),
  orchestra('orchestra'),
  loFi('lo_fi'),
  jazz('jazz'),
  brownNoise('brown_noise');

  const StudyBgmTrack(this.asset);

  final String asset;
}

enum StudyBgmMessage { interrupted, failed }

typedef _Playback = ({
  StudyBgmTrack? track,
  bool enabled,
  bool playing,
  double volume,
  int attempt,
});

/// Keeps BGM preferences on this device and playback intent in this session.
class StudyBgmController extends ChangeNotifier {
  static const _channel = MethodChannel('com.studypeaks.app/study_bgm');
  static const _trackKey = 'study_bgm_track';
  static const _volumeKey = 'study_bgm_volume';

  StudyBgmController(this._timer)
      : _sessionId = _timer.sessionId,
        _visible = switch (WidgetsBinding.instance.lifecycleState) {
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached =>
            false,
          _ => true,
        } {
    _timerAllowsPlayback = _canPlay;
    _timer.addListener(_onTimerChanged);
    _channel.setMethodCallHandler(_onPlayerEvent);
    _lifecycle = AppLifecycleListener(
      onResume: () => _setVisible(true),
      onHide: () => _setVisible(false),
      onDetach: () => _setVisible(false),
    );
    unawaited(_loadPreferences());
  }

  final TimerProvider _timer;
  SharedPreferences? _prefs;
  late final AppLifecycleListener _lifecycle;
  String? _sessionId;
  bool _visible;
  late bool _timerAllowsPlayback;
  bool _disposed = false;
  bool _ready = false;
  bool _enabled = false;
  int _attempt = 0;
  StudyBgmTrack _track = StudyBgmTrack.rain;
  double _volume = 0.35;
  StudyBgmMessage? _message;
  _Playback? _sent;

  bool get ready => _ready;
  bool get enabled => _enabled;
  bool get timerAllowsPlayback => _timerAllowsPlayback;
  bool get _canPlay => _timer.isRunning && !_timer.isOnBreak;
  StudyBgmTrack get track => _track;
  double get volume => _volume;
  StudyBgmMessage? get message => _message;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      final asset = prefs.getString(_trackKey);
      final volume = prefs.getDouble(_volumeKey);
      _track = StudyBgmTrack.values.firstWhere(
        (track) => track.asset == asset,
        orElse: () => StudyBgmTrack.rain,
      );
      if (volume != null && volume.isFinite) _volume = volume.clamp(0.0, 1.0);
    } catch (error) {
      debugPrint('Could not read BGM preferences: $error');
    }
    if (_disposed) return;
    _ready = true;
    notifyListeners();
  }

  void setEnabled(bool enabled) {
    if (!_ready || _enabled == enabled) return;
    _enabled = enabled;
    _message = null;
    if (enabled) _attempt++;
    _update();
  }

  void selectTrack(StudyBgmTrack track) {
    if (!_ready || _track == track) return;
    _track = track;
    _message = null;
    unawaited(_save(_prefs?.setString(_trackKey, track.asset)));
    _update();
  }

  void setVolume(double value) {
    if (!_ready || !value.isFinite || _volume == value) return;
    _volume = value.clamp(0.0, 1.0);
    _update();
  }

  void saveVolume() {
    unawaited(_save(_prefs?.setDouble(_volumeKey, _volume)));
  }

  Future<void> _save(Future<bool>? write) async {
    try {
      await write;
    } catch (error) {
      debugPrint('Could not save a BGM preference: $error');
    }
  }

  void _onTimerChanged() {
    final sessionId = _timer.sessionId;
    final changedSession = _sessionId != sessionId;
    if (changedSession && _sessionId != null) {
      _enabled = false;
      _message = null;
    }
    _sessionId = sessionId;
    final playbackAvailabilityChanged = _timerAllowsPlayback != _canPlay;
    _timerAllowsPlayback = _canPlay;
    // Timer notifications also arrive every second. Only rebuild the controls
    // when the playback command or session changes.
    if (_sync() || changedSession || playbackAvailabilityChanged) {
      notifyListeners();
    }
  }

  void _setVisible(bool visible) {
    _visible = visible;
    if (_sync()) notifyListeners();
  }

  void _update() {
    _sync();
    notifyListeners();
  }

  bool _sync() {
    final playing = _enabled && _visible && timerAllowsPlayback;
    final retainTrack = _enabled &&
        !_timer.isOnBreak &&
        (_timer.isRunning || !_timer.waitingToStart);
    final track = retainTrack ? _track : null;
    final next = (
      track: track,
      enabled: _enabled,
      playing: playing,
      volume: track == null ? 0.0 : _volume,
      attempt: _attempt,
    );
    if (next == _sent || (_sent == null && !_enabled)) return false;
    _sent = next;
    unawaited(_send(next));
    return true;
  }

  Future<void> _send(_Playback command) async {
    try {
      await _channel.invokeMethod<void>('updatePlayback', {
        'track': command.track?.asset,
        'enabled': command.enabled,
        'playing': command.playing,
        'volume': command.volume,
        'attempt': command.attempt,
      });
    } catch (error) {
      debugPrint('Could not update BGM playback: $error');
      if (command.playing && _sent == command) {
        _showMessage(StudyBgmMessage.failed, command.attempt);
      }
    }
  }

  Future<void> _onPlayerEvent(MethodCall call) async {
    final attempt = call.arguments;
    if (attempt is! int) return;
    switch (call.method) {
      case 'interrupted':
        _showMessage(StudyBgmMessage.interrupted, attempt);
      case 'failed':
        _showMessage(StudyBgmMessage.failed, attempt);
    }
  }

  void _showMessage(StudyBgmMessage message, int attempt) {
    if (_disposed || !_enabled || attempt != _attempt) return;
    _enabled = false;
    _message = message;
    _update();
  }

  @override
  void dispose() {
    _disposed = true;
    _enabled = false;
    _sync();
    _timer.removeListener(_onTimerChanged);
    _lifecycle.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
