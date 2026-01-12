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

/// User information displayed on a seat.
class SeatUser {
  final String userId;
  final String displayName;
  final String countryCode;
  final String statusMessage;

  const SeatUser({
    required this.userId,
    required this.displayName,
    required this.countryCode,
    this.statusMessage = '',
  });

  factory SeatUser.fromJson(Map<String, dynamic> json) {
    return SeatUser(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      countryCode: json['countryCode'] as String,
      statusMessage: json['statusMessage'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'countryCode': countryCode,
      'statusMessage': statusMessage,
    };
  }
}

/// Room data model representing a study room.
class Room {
  final String roomId;
  final String name;
  final int capacity;
  final int currentOccupancy;

  const Room({
    required this.roomId,
    required this.name,
    required this.capacity,
    required this.currentOccupancy,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      roomId: json['roomId'] as String,
      name: json['name'] as String,
      capacity: json['capacity'] as int,
      currentOccupancy: json['currentOccupancy'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'name': name,
      'capacity': capacity,
      'currentOccupancy': currentOccupancy,
    };
  }
}
