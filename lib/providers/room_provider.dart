import 'package:flutter/foundation.dart';
import '../models/seat.dart';
import '../services/api_service.dart';

/// Provider for managing room list state.
class RoomProvider extends ChangeNotifier {
  final ApiService _apiService;

  List<Room> _rooms = [];
  bool _isLoading = false;
  String? _error;

  RoomProvider({ApiService? apiService})
      : _apiService = apiService ?? ApiService();


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
      // Use mock data for development
      _rooms = _getMockRooms();
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
        _roomSeats[roomId] = _getMockSeats(roomId);
      } else {
        _roomSeats[roomId] = seats;
      }
    } catch (e) {
      _error = e.toString();
      // Use mock data for development (fallback)
      _roomSeats[roomId] = _getMockSeats(roomId);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get mock seats for development.
  List<Seat> _getMockSeats(String roomId) {
    // Determine capacity based on room
    final roomCapacity = _getRoomCapacity(roomId);
    final seats = <Seat>[];
    
    // Generate seats with some randomly occupied
    for (int i = 1; i <= roomCapacity; i++) {
      // Randomly occupy ~30% of seats
      final isOccupied = i % 3 == 0;
      
      if (isOccupied) {
        seats.add(Seat(
          seatId: '$roomId-seat-$i',
          seatNumber: i,
          isOccupied: true,
          user: SeatUser(
            userId: 'mock-user-$i',
            displayName: _getMockUserName(i),
            countryCode: _getMockCountryCode(i),
            statusMessage: _getMockStatus(i),
          ),
          sessionStartedAt: DateTime.now().subtract(Duration(minutes: i * 5)),
          currentSessionDuration: i * 300, // 5 min increments
        ));
      } else {
        seats.add(Seat.empty(i));
      }
    }
    
    return seats;
  }

  int _getRoomCapacity(String roomId) {
    switch (roomId) {
      case 'everest':
        return 24;
      case 'fuji':
        return 20;
      case 'matterhorn':
        return 16;
      case 'kilimanjaro':
        return 20;
      case 'denali':
        return 16;
      case 'aconcagua':
        return 20;
      default:
        return 16;
    }
  }

  String _getMockUserName(int index) {
    const names = [
      'Alex', 'Jordan', 'Taylor', 'Morgan', 'Casey',
      'Riley', 'Quinn', 'Avery', 'Charlie', 'Dakota',
      'Skyler', 'Jamie', 'Reese', 'Finley', 'Harper',
    ];
    return names[index % names.length];
  }

  String _getMockCountryCode(int index) {
    const countries = ['JP', 'US', 'GB', 'KR', 'DE', 'FR', 'CN', 'BR', 'IN', 'AU'];
    return countries[index % countries.length];
  }

  String _getMockStatus(int index) {
    const statuses = [
      'Studying hard!', 'Deep focus', 'Math exam prep',
      'Coding time', 'Reading', 'Essay writing',
      '', '', '', // Some empty statuses
    ];
    return statuses[index % statuses.length];
  }

  /// Get mock rooms for development.
  List<Room> _getMockRooms() {
    return const [
      Room(
        roomId: 'everest',
        name: 'Mt. Everest',
        capacity: 100,
        currentOccupancy: 42,
      ),
      Room(
        roomId: 'fuji',
        name: 'Mt. Fuji',
        capacity: 50,
        currentOccupancy: 23,
      ),
      Room(
        roomId: 'matterhorn',
        name: 'Matterhorn',
        capacity: 75,
        currentOccupancy: 31,
      ),
      Room(
        roomId: 'kilimanjaro',
        name: 'Mt. Kilimanjaro',
        capacity: 80,
        currentOccupancy: 15,
      ),
      Room(
        roomId: 'denali',
        name: 'Denali',
        capacity: 60,
        currentOccupancy: 8,
      ),
      Room(
        roomId: 'aconcagua',
        name: 'Aconcagua',
        capacity: 70,
        currentOccupancy: 19,
      ),
    ];
  }
}
