/// Model representing a completed study session.
class StudySession {
  final int? id;
  final String roomId;
  final DateTime startTime;
  final int durationSeconds;

  StudySession({
    this.id,
    required this.roomId,
    required this.startTime,
    required this.durationSeconds,
  });

  /// Convert to map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'room_id': roomId,
      'start_time': startTime.toIso8601String(),
      'duration_seconds': durationSeconds,
    };
  }

  /// Create from database map
  factory StudySession.fromMap(Map<String, dynamic> map) {
    return StudySession(
      id: map['id'] as int?,
      roomId: map['room_id'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      durationSeconds: map['duration_seconds'] as int,
    );
  }
}
