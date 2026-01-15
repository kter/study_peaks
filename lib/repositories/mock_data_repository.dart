import '../models/models.dart';

/// Abstract interface for mock data generation.
/// 
/// This abstraction allows for:
/// - Easy mocking in tests
/// - Environment-based switching between dev and prod implementations
abstract class MockDataRepository {
  /// Get mock seats for a given room.
  List<Seat> getMockSeats(String roomId);
  
  /// Get mock room list.
  List<Room> getMockRooms();
}

/// Development implementation that returns mock data.
class DevMockDataRepository implements MockDataRepository {
  @override
  List<Seat> getMockSeats(String roomId) {
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

  @override
  List<Room> getMockRooms() {
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
}

/// Production implementation that returns empty data.
/// Used when mock data should be disabled.
class EmptyMockDataRepository implements MockDataRepository {
  @override
  List<Seat> getMockSeats(String roomId) => [];
  
  @override
  List<Room> getMockRooms() => [];
}
