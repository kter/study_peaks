import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:study_peaks/providers/room_provider.dart';
import 'package:study_peaks/models/models.dart';
import 'package:study_peaks/repositories/mock_data_repository.dart';

import '../helpers/test_helpers.dart';
import '../helpers/mock_data.dart';

void main() {
  late RoomProvider provider;
  late MockApiService mockApiService;

  setUp(() {
    mockApiService = MockApiService();
    provider = RoomProvider(apiService: mockApiService);
  });

  group('RoomProvider', () {
    test('initial state has empty rooms', () {
      expect(provider.rooms, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.error, isNull);
    });

    test('fetchRooms sets isLoading while fetching', () async {
      // Setup mock to delay response
      when(() => mockApiService.getRooms()).thenAnswer(
        (_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return mockRooms;
        },
      );

      // Start fetching
      final fetchFuture = provider.fetchRooms();

      // Should be loading
      expect(provider.isLoading, true);

      // Wait for completion
      await fetchFuture;

      // Should not be loading
      expect(provider.isLoading, false);
    });

    test('fetchRooms populates rooms on success', () async {
      when(() => mockApiService.getRooms()).thenAnswer(
        (_) async => mockRooms,
      );

      await provider.fetchRooms();

      expect(provider.rooms.length, 2);
      expect(provider.rooms[0].name, 'Mt. Everest');
      expect(provider.rooms[1].name, 'Mt. Fuji');
      expect(provider.error, isNull);
    });

    test('fetchRooms falls back to mock data on API error', () async {
      // Create provider with mock data repository for this test
      final providerWithMock = RoomProvider(
        apiService: mockApiService,
        mockDataRepository: DevMockDataRepository(),
      );
      
      when(() => mockApiService.getRooms()).thenThrow(
        Exception('Network error'),
      );

      await providerWithMock.fetchRooms();

      // Should have mock rooms (fallback)
      expect(providerWithMock.rooms.isNotEmpty, true);
      expect(providerWithMock.error, isNotNull);
    });

    test('rooms list contains Room objects with expected properties', () async {
      when(() => mockApiService.getRooms()).thenAnswer(
        (_) async => [
          const Room(
            roomId: 'test',
            name: 'Test Room',
            capacity: 50,
            currentOccupancy: 25,
          ),
        ],
      );

      await provider.fetchRooms();

      final room = provider.rooms.first;
      expect(room.roomId, 'test');
      expect(room.name, 'Test Room');
      expect(room.capacity, 50);
      expect(room.currentOccupancy, 25);
    });
  });
}
