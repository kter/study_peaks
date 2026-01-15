import 'package:study_peaks/models/seat.dart';

/// Mock room data for testing
const mockRooms = [
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
];

/// Mock user for testing
const mockUser = SeatUser(
  userId: 'test-user-1',
  displayName: 'Test User',
  countryCode: 'JP',
  statusMessage: 'Studying!',
);

/// Mock occupied seat for testing
/// sessionStartedAt is set to 1 hour ago for duration testing
Seat get mockOccupiedSeat => Seat(
  seatId: 'seat-001',
  seatNumber: 1,
  isOccupied: true,
  user: mockUser,
  sessionStartedAt: DateTime.now().subtract(const Duration(hours: 1)),
  currentSessionDuration: 3600, // 1 hour (legacy field)
);

/// Mock empty seat for testing
final mockEmptySeat = Seat.empty(5);

/// Room with low occupancy (green color)
const lowOccupancyRoom = Room(
  roomId: 'low',
  name: 'Low Occupancy',
  capacity: 100,
  currentOccupancy: 30, // 30%
);

/// Room with medium occupancy (orange color)
const mediumOccupancyRoom = Room(
  roomId: 'medium',
  name: 'Medium Occupancy',
  capacity: 100,
  currentOccupancy: 65, // 65%
);

/// Room with high occupancy (red color)
const highOccupancyRoom = Room(
  roomId: 'high',
  name: 'High Occupancy',
  capacity: 100,
  currentOccupancy: 90, // 90%
);
