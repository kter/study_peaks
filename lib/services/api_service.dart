import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/models.dart';
import 'network_exception.dart';

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

  /// Retry configuration
  /// Extended delays to handle network recovery after device sleep
  static const int _maxRetries = 5;
  static const List<Duration> _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  /// Execute a request with automatic retry on network errors.
  /// 
  /// Will retry up to [_maxRetries] times with exponential backoff.
  /// Only retries on network-related errors (DNS, timeout, connection issues).
  Future<T> _withRetry<T>(Future<T> Function() request) async {
    Object? lastError;
    
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        return await request();
      } catch (e) {
        lastError = e;
        
        // Only retry on network errors
        if (!isNetworkError(e)) {
          rethrow;
        }
        
        // Don't delay after the last attempt
        if (attempt < _maxRetries - 1) {
          await Future.delayed(_retryDelays[attempt]);
        }
      }
    }
    
    // All retries exhausted, throw NetworkException
    throw NetworkException(
      'Connection failed after $_maxRetries attempts',
      lastError,
    );
  }

  /// Fetch all available rooms.
  Future<List<Room>> getRooms() async {
    return _withRetry(() async {
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
    });
  }

  /// Fetch seats for a specific room.
  Future<List<Seat>> getRoomSeats(String roomId) async {
    return _withRetry(() async {
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
    });
  }

  /// Sit down on a seat.
  Future<SitResponse> sit(
    String roomId,
    int seatNumber, {
    String? displayName,
    String? countryCode,
    String? userId,
    String? iconSeed,
    String? photoUrl,
  }) async {
    return _withRetry(() async {
      final response = await _client.post(
        Uri.parse('$baseUrl/rooms/$roomId/sit'),
        headers: _headers,
        body: jsonEncode({
          'seatNumber': seatNumber,
          if (displayName != null) 'displayName': displayName,
          if (countryCode != null) 'countryCode': countryCode,
          if (userId != null) 'userId': userId,
          if (iconSeed != null) 'iconSeed': iconSeed,
          if (photoUrl != null) 'photoUrl': photoUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SitResponse.fromJson(data);
      }
      throw ApiException('Failed to sit', response.statusCode);
    });
  }

  /// Sync session (called every 5 minutes).
  Future<void> sync(
    String roomId,
    String sessionId,
    int currentDuration, {
    String? displayName,
    String? countryCode,
    String? iconSeed,
    String? photoUrl,
  }) async {
    return _withRetry(() async {
      final response = await _client.post(
        Uri.parse('$baseUrl/rooms/$roomId/sync'),
        headers: _headers,
        body: jsonEncode({
          'sessionId': sessionId,
          'currentDuration': currentDuration,
          if (displayName != null) 'displayName': displayName,
          if (countryCode != null) 'countryCode': countryCode,
          if (iconSeed != null) 'iconSeed': iconSeed,
          // Always include photoUrl (can be empty string to clear it)
          'photoUrl': photoUrl ?? '',
        }),
      );

      if (response.statusCode != 200) {
        throw ApiException('Failed to sync', response.statusCode);
      }
    });
  }

  /// Leave the seat.
  Future<LeaveResponse> leave(String roomId, String sessionId, int finalDuration) async {
    return _withRetry(() async {
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
    });
  }

  /// Get session info to validate if a session is still active.
  /// Returns null if the session is not found or expired.
  Future<SessionInfo?> getSession(String roomId, String sessionId) async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl/rooms/$roomId/sessions/$sessionId'),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return SessionInfo.fromJson(data);
      }
      // Session not found or expired
      return null;
    } catch (e) {
      // Network error or other issues - treat as session not found
      return null;
    }
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

/// Session information returned from the session validation API.
class SessionInfo {
  final String sessionId;
  final String roomId;
  final String roomName;
  final int seatNumber;
  final DateTime sessionStartedAt;
  final DateTime lastSyncAt;
  final int currentDuration;

  SessionInfo({
    required this.sessionId,
    required this.roomId,
    required this.roomName,
    required this.seatNumber,
    required this.sessionStartedAt,
    required this.lastSyncAt,
    required this.currentDuration,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionId: json['sessionId'] as String,
      roomId: json['roomId'] as String,
      roomName: json['roomName'] as String,
      seatNumber: json['seatNumber'] as int,
      sessionStartedAt: DateTime.parse(json['sessionStartedAt'] as String),
      lastSyncAt: DateTime.parse(json['lastSyncAt'] as String),
      currentDuration: json['currentDuration'] as int,
    );
  }
}
