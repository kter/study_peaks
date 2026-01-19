/// User information displayed on a seat.
class SeatUser {
  final String userId;
  final String displayName;
  final String countryCode;
  final String statusMessage;
  final String? iconSeed;
  final String? photoUrl;

  const SeatUser({
    required this.userId,
    required this.displayName,
    required this.countryCode,
    this.statusMessage = '',
    this.iconSeed,
    this.photoUrl,
  });

  factory SeatUser.fromJson(Map<String, dynamic> json) {
    // Helper to convert empty string to null
    String? nonEmpty(String? value) => (value?.isEmpty ?? true) ? null : value;
    
    return SeatUser(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      countryCode: json['countryCode'] as String,
      statusMessage: json['statusMessage'] as String? ?? '',
      iconSeed: nonEmpty(json['iconSeed'] as String?),
      photoUrl: nonEmpty(json['photoUrl'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'countryCode': countryCode,
      'statusMessage': statusMessage,
      if (iconSeed != null) 'iconSeed': iconSeed,
      if (photoUrl != null) 'photoUrl': photoUrl,
    };
  }
}
