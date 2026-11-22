import 'dart:convert';
import 'package:uuid/uuid.dart';

/// A focus interval, with a fixed civil-time offset captured when it starts.
class FocusInterval {
  final DateTime start;
  final DateTime end;
  final int offsetMinutes;

  FocusInterval(
      {required DateTime start,
      required DateTime end,
      required this.offsetMinutes})
      : start = start.toUtc(),
        end = end.toUtc() {
    if (end.isBefore(start)) throw ArgumentError('Negative focus interval');
  }

  int get milliseconds => end.difference(start).inMilliseconds;
  Map<String, dynamic> toMap() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'offset': offsetMinutes,
      };
  factory FocusInterval.fromMap(Map<String, dynamic> map) => FocusInterval(
        start: DateTime.parse(map['start'] as String),
        end: DateTime.parse(map['end'] as String),
        offsetMinutes: map['offset'] as int,
      );
}

/// Immutable identity and owner; retries replace the same record.
class StudySession {
  static const guestOwner = 'guest:device';
  static const legacyOwner = 'legacy:unknown';

  static String ownerFor(String? uid) =>
      uid == null || uid.isEmpty ? guestOwner : 'user:$uid';

  /// The explicitly separated legacy history is visible to any current owner.
  bool isVisibleTo(String currentOwnerId) =>
      ownerId == currentOwnerId || ownerId == legacyOwner;

  final int? id;
  final String sessionId;
  final String ownerId;
  final String roomId;
  final DateTime startTime;
  final int durationSeconds;

  /// Null means timing is unavailable: attribute to start day, explicitly legacy.
  final List<FocusInterval>? intervals;

  /// The first device-clock focus start, with seat time as a fallback.
  DateTime get displayStartTime => intervals?.firstOrNull?.start ?? startTime;

  StudySession(
      {this.id,
      String? sessionId,
      this.ownerId = guestOwner,
      required this.roomId,
      required this.startTime,
      required this.durationSeconds,
      List<FocusInterval>? intervals})
      : sessionId = sessionId ?? const Uuid().v4(),
        intervals = intervals == null ? null : List.unmodifiable(intervals) {
    if (durationSeconds < 0) throw ArgumentError('Negative study duration');
    if (intervals != null &&
        intervals.fold<int>(0, (sum, i) => sum + i.milliseconds) ~/ 1000 !=
            durationSeconds) {
      throw ArgumentError('Focus intervals do not match duration');
    }
    if (intervals != null) {
      for (var i = 1; i < intervals.length; i++) {
        if (intervals[i].start.isBefore(intervals[i - 1].end)) {
          throw ArgumentError('Overlapping focus intervals');
        }
      }
    }
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'owner_id': ownerId,
        'room_id': roomId,
        'start_time': startTime.toIso8601String(),
        'duration_seconds': durationSeconds,
        'focus_intervals': intervals == null
            ? null
            : jsonEncode(intervals!.map((i) => i.toMap()).toList()),
      };

  factory StudySession.fromMap(Map<String, dynamic> map) => StudySession(
        id: map['id'] as int?,
        sessionId: map['session_id'] as String?,
        ownerId: map['owner_id'] as String? ?? legacyOwner,
        roomId: map['room_id'] as String,
        startTime: DateTime.parse(map['start_time'] as String),
        durationSeconds: map['duration_seconds'] as int,
        intervals: map['focus_intervals'] == null
            ? null
            : (jsonDecode(map['focus_intervals'] as String) as List)
                .map((i) =>
                    FocusInterval.fromMap(Map<String, dynamic>.from(i as Map)))
                .toList(),
      );

  Map<String, dynamic> toSyncJson() => {
        'sessionId': sessionId,
        'roomId': roomId,
        'startTime': startTime.toIso8601String(),
        'durationSeconds': durationSeconds,
        'focusIntervals': intervals?.map((i) => i.toMap()).toList(),
      };

  factory StudySession.fromSyncJson(
          Map<String, dynamic> json, String ownerId) =>
      StudySession(
        sessionId: json['sessionId'] as String,
        ownerId: ownerId,
        roomId: json['roomId'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        durationSeconds: json['durationSeconds'] as int,
        intervals: (json['focusIntervals'] as List<dynamic>?)
            ?.map((i) => FocusInterval.fromMap(i as Map<String, dynamic>))
            .toList(),
      );

  /// Civil dates are UTC date labels, independent of the viewer's timezone.
  Map<DateTime, int> get dailySeconds {
    if (intervals == null) {
      return {
        DateTime.utc(startTime.year, startTime.month, startTime.day):
            durationSeconds
      };
    }
    final result = <DateTime, int>{};
    var cumulativeMs = 0;
    for (final interval in intervals!) {
      final start =
          interval.start.add(Duration(minutes: interval.offsetMinutes));
      final end = interval.end.add(Duration(minutes: interval.offsetMinutes));
      var cursor = start;
      var allocatedMs = 0;
      while (cursor.isBefore(end)) {
        final day = DateTime.utc(cursor.year, cursor.month, cursor.day);
        final midnight =
            DateTime.utc(cursor.year, cursor.month, cursor.day + 1);
        final stop = end.isBefore(midnight) ? end : midnight;
        final before = cumulativeMs ~/ 1000;
        // Round from the start of the interval so a midnight split does not
        // truncate the sub-millisecond remainder twice.
        final elapsedMs = stop.difference(start).inMilliseconds;
        cumulativeMs += elapsedMs - allocatedMs;
        allocatedMs = elapsedMs;
        result[day] = (result[day] ?? 0) + cumulativeMs ~/ 1000 - before;
        cursor = stop;
      }
    }
    return result;
  }
}
