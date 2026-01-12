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

  List<Room> get rooms => _rooms;
  bool get isLoading => _isLoading;
  String? get error => _error;

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
