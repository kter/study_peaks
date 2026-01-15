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
