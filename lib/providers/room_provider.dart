import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/mock_data_repository.dart';
import '../services/api_service.dart';

/// Provider for managing room list state.
class RoomProvider extends ChangeNotifier {
  final ApiService _apiService;
  final MockDataRepository? _mockDataRepository;

  List<Room> _rooms = [];
  bool _isLoading = false;
  String? _error;

  RoomProvider({
    ApiService? apiService,
    MockDataRepository? mockDataRepository,
  })  : _apiService = apiService ?? ApiService(),
        _mockDataRepository = mockDataRepository;

  final Map<String, List<Seat>> _roomSeats = {};

  List<Room> get rooms => _rooms;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Get seats for a specific room
  List<Seat> getSeats(String roomId) => _roomSeats[roomId] ?? [];

  /// Update a seat's occupancy status locally (for sit/leave without refetch)
  void updateSeatOccupancy({
    required String roomId,
    required int seatNumber,
    required bool isOccupied,
    SeatUser? user,
  }) {
    final seats = _roomSeats[roomId];
    if (seats == null) return;

    final index = seats.indexWhere((s) => s.seatNumber == seatNumber);
    if (index == -1) return;

    _roomSeats[roomId] = List.from(seats)
      ..[index] = Seat(
        seatId: seats[index].seatId,
        seatNumber: seatNumber,
        isOccupied: isOccupied,
        user: user,
        sessionStartedAt: isOccupied ? DateTime.now() : null,
        currentSessionDuration: 0,
      );
    notifyListeners();
  }

  /// Clear seat occupancy (when user leaves)
  void clearSeatOccupancy(String roomId, int seatNumber) {
    updateSeatOccupancy(
      roomId: roomId,
      seatNumber: seatNumber,
      isOccupied: false,
    );
  }

  /// Fetch rooms from API.
  Future<void> fetchRooms() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _rooms = await _apiService.getRooms();
    } catch (e) {
      _error = e.toString();
      // Use mock data for development (if repository provided)
      _rooms = _mockDataRepository?.getMockRooms() ?? [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch seats for a specific room
  Future<void> fetchSeats(String roomId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final seats = await _apiService.getRoomSeats(roomId);
      // Use mock data if API returns empty seats (backend not configured yet)
      if (seats.isEmpty) {
        _roomSeats[roomId] = _mockDataRepository?.getMockSeats(roomId) ?? [];
      } else {
        _roomSeats[roomId] = seats;
      }
    } catch (e) {
      _error = e.toString();
      // Use mock data for development (fallback, if repository provided)
      _roomSeats[roomId] = _mockDataRepository?.getMockSeats(roomId) ?? [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
