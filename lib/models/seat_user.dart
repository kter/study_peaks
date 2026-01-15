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
