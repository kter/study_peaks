import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/models.dart';

/// API service for communicating with the Study Peaks backend.
class ApiService {
  final String baseUrl;
  final http.Client _client;
  String? _authToken;

  ApiService({
    this.baseUrl = AppConfig.apiBaseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Set the authentication token for API requests.
  void setAuthToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Fetch all available rooms.
  Future<List<Room>> getRooms() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final roomsList = data['rooms'] as List<dynamic>;
      return roomsList
          .map((json) => Room.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    throw ApiException('Failed to fetch rooms', response.statusCode);
  }

  /// Fetch seats for a specific room.
  Future<List<Seat>> getRoomSeats(String roomId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/rooms/$roomId/seats'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final seatsList = data['seats'] as List<dynamic>;
      return seatsList
          .map((json) => Seat.fromJson(json as Map<String, dynamic>))
          .toList();
    }
    throw ApiException('Failed to fetch seats', response.statusCode);
  }

  /// Sit down on a seat.
  Future<SitResponse> sit(String roomId, int seatNumber) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/sit'),
      headers: _headers,
      body: jsonEncode({'seatNumber': seatNumber}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return SitResponse.fromJson(data);
    }
    throw ApiException('Failed to sit', response.statusCode);
  }

  /// Sync session (called every 5 minutes).
  Future<void> sync(String roomId, String sessionId, int currentDuration) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/sync'),
      headers: _headers,
      body: jsonEncode({
        'sessionId': sessionId,
        'currentDuration': currentDuration,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException('Failed to sync', response.statusCode);
    }
  }

  /// Leave the seat.
  Future<LeaveResponse> leave(String roomId, String sessionId, int finalDuration) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rooms/$roomId/leave'),
      headers: _headers,
      body: jsonEncode({
        'sessionId': sessionId,
        'finalDuration': finalDuration,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return LeaveResponse.fromJson(data);
    }
    throw ApiException('Failed to leave', response.statusCode);
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => 'ApiException: $message (status: $statusCode)';
}

class SitResponse {
  final String sessionId;
  final int seatNumber;
  final DateTime sessionStartedAt;

  SitResponse({
    required this.sessionId,
    required this.seatNumber,
    required this.sessionStartedAt,
  });

  factory SitResponse.fromJson(Map<String, dynamic> json) {
    return SitResponse(
      sessionId: json['sessionId'] as String,
      seatNumber: json['seatNumber'] as int,
      sessionStartedAt: DateTime.parse(json['sessionStartedAt'] as String),
    );
  }
}

class LeaveResponse {
  final int totalSessionDuration;
  final DateTime endedAt;

  LeaveResponse({
    required this.totalSessionDuration,
    required this.endedAt,
  });

  factory LeaveResponse.fromJson(Map<String, dynamic> json) {
    return LeaveResponse(
      totalSessionDuration: json['totalSessionDuration'] as int,
      endedAt: DateTime.parse(json['endedAt'] as String),
    );
  }
}
