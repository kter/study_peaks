import 'seat_user.dart';

/// Seat data model representing a seat in a study room.
class Seat {
  final String seatId;
  final int seatNumber;
  final bool isOccupied;
  final SeatUser? user;
  final DateTime? sessionStartedAt;
  final int currentSessionDuration; // in seconds

  const Seat({
    required this.seatId,
    required this.seatNumber,
    required this.isOccupied,
    this.user,
    this.sessionStartedAt,
    this.currentSessionDuration = 0,
  });

  factory Seat.empty(int seatNumber) {
    return Seat(
      seatId: 'seat-${seatNumber.toString().padLeft(3, '0')}',
      seatNumber: seatNumber,
      isOccupied: false,
    );
  }

  factory Seat.fromJson(Map<String, dynamic> json) {
    return Seat(
      seatId: json['seatId'] as String,
      seatNumber: json['seatNumber'] as int,
      isOccupied: json['isOccupied'] as bool,
      user: json['user'] != null
          ? SeatUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      sessionStartedAt: json['sessionStartedAt'] != null
          ? DateTime.parse(json['sessionStartedAt'] as String)
          : null,
      currentSessionDuration: json['currentSessionDuration'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seatId': seatId,
      'seatNumber': seatNumber,
      'isOccupied': isOccupied,
      'user': user?.toJson(),
      'sessionStartedAt': sessionStartedAt?.toIso8601String(),
      'currentSessionDuration': currentSessionDuration,
    };
  }
}
