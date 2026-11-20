import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../repositories/mock_data_repository.dart';
import '../services/api_service.dart';
import '../services/network_exception.dart';

/// Provider for managing room list state.
class RoomProvider extends ChangeNotifier {
  final ApiService _apiService;
  final MockDataRepository? _mockDataRepository;

  List<Room> _rooms = [];
  bool _loadingRooms = false;
  int _pendingSeatLoads = 0;
  int _nextSeatRequest = 0;
  String? _error;
  String? _roomsError;

  RoomProvider({
    ApiService? apiService,
    MockDataRepository? mockDataRepository,
  })  : _apiService = apiService ?? ApiService(),
        _mockDataRepository = mockDataRepository;

  final Map<String, List<Seat>> _roomSeats = {};
  final Map<String, String> _seatErrors = {};
  final Map<String, int> _seatRequests = {};

  List<Room> get rooms => _rooms;
  bool get isLoading => _loadingRooms || _pendingSeatLoads > 0;
  String? get error => _error;
  String? get roomsError => _roomsError;

  /// Get seats for a specific room
  List<Seat> getSeats(String roomId) => _roomSeats[roomId] ?? [];

  String? seatError(String roomId) => _seatErrors[roomId];

  /// Get the latest known room data (falls back to null if not loaded).
  Room? getRoom(String roomId) =>
      _rooms.where((r) => r.roomId == roomId).firstOrNull;

  /// Keep the room's occupancy count in sync with its seat list, so the room
  /// list and room info show the same number as the seat map.
  void _syncRoomOccupancy(String roomId) {
    final seats = _roomSeats[roomId];
    if (seats == null || seats.isEmpty) return;
    final index = _rooms.indexWhere((r) => r.roomId == roomId);
    if (index == -1) return;

    final room = _rooms[index];
    final occupied = seats.where((s) => s.isOccupied).length;
    if (room.currentOccupancy == occupied) return;

    _rooms = List.from(_rooms)
      ..[index] = Room(
        roomId: room.roomId,
        name: room.name,
        capacity: room.capacity,
        currentOccupancy: occupied,
      );
  }

  /// Update a seat's occupancy status locally (for sit/leave without refetch)
  void updateSeatOccupancy({
    required String roomId,
    required int seatNumber,
    required bool isOccupied,
    SeatUser? user,
    DateTime? sessionStartedAt,
    bool replacesUserSeat = false,
  }) {
    final seats = _roomSeats[roomId];
    if (seats == null) return;

    final index = seats.indexWhere((s) => s.seatNumber == seatNumber);
    if (index == -1) return;

    if (replacesUserSeat && isOccupied && user != null) {
      _clearUserSeats(user.userId);
    }
    _seatRequests.remove(roomId);
    _roomSeats[roomId] = List.of(_roomSeats[roomId]!)
      ..[index] = Seat(
        seatId: seats[index].seatId,
        seatNumber: seatNumber,
        isOccupied: isOccupied,
        user: user,
        sessionStartedAt: sessionStartedAt ?? (isOccupied ? DateTime.now() : null),
        currentSessionDuration: 0,
      );
    _syncRoomOccupancy(roomId);
    notifyListeners();
  }

  void _clearUserSeats(String userId) {
    for (final roomId in _roomSeats.keys) {
      final seats = _roomSeats[roomId]!;
      if (seats.any((seat) => seat.user?.userId == userId)) {
        _seatRequests.remove(roomId);
        _roomSeats[roomId] = [
          for (final seat in seats)
            if (seat.user?.userId == userId)
              Seat(seatId: seat.seatId, seatNumber: seat.seatNumber, isOccupied: false)
            else
              seat,
        ];
        _syncRoomOccupancy(roomId);
      }
    }
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
    _loadingRooms = true;
    _error = null;
    _roomsError = null;
    notifyListeners();

    try {
      _rooms = await _apiService.getRooms();
    } catch (e) {
      _error = errorKeyFor(e, e.toString());
      _roomsError = _error;
      // Use mock data for development (if repository provided)
      _rooms = _mockDataRepository?.getMockRooms() ?? [];
    } finally {
      _loadingRooms = false;
      notifyListeners();
    }
  }

  /// Fetch seats for a specific room
  Future<void> fetchSeats(String roomId) async {
    final request = ++_nextSeatRequest;
    _seatRequests[roomId] = request;
    _pendingSeatLoads++;
    _error = null;
    notifyListeners();

    try {
      final seats = await _apiService.getRoomSeats(roomId);
      if (_seatRequests[roomId] != request) return;
      _seatErrors.remove(roomId);
      // Use mock data if API returns empty seats (backend not configured yet)
      if (seats.isEmpty) {
        _roomSeats[roomId] = _mockDataRepository?.getMockSeats(roomId) ?? [];
      } else {
        _roomSeats[roomId] = seats;
      }
      _syncRoomOccupancy(roomId);
    } catch (e) {
      if (_seatRequests[roomId] != request) return;
      final error = errorKeyFor(e, e.toString());
      _error = error;
      _seatErrors[roomId] = error;
      // Preserve existing seat data on network error; fall back to mock only if no existing data
      if (!_roomSeats.containsKey(roomId) || _roomSeats[roomId]!.isEmpty) {
        _roomSeats[roomId] = _mockDataRepository?.getMockSeats(roomId) ?? [];
      }
    } finally {
      _pendingSeatLoads--;
      notifyListeners();
    }
  }
}
