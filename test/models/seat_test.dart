import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/models/seat.dart';

void main() {
  final now = DateTime.utc(2026, 11, 19, 12);

  test('elapsedAt uses the session start time and supplied clock', () {
    final seat = Seat(
      seatId: 'seat-001',
      seatNumber: 1,
      isOccupied: true,
      sessionStartedAt: now.subtract(const Duration(minutes: 10, seconds: 30)),
      currentSessionDuration: 1,
    );

    expect(seat.elapsedAt(now), const Duration(minutes: 10, seconds: 30));
  });

  test('elapsedAt returns zero when the session has no start time', () {
    const seat = Seat(
      seatId: 'seat-001',
      seatNumber: 1,
      isOccupied: true,
      currentSessionDuration: 30,
    );

    expect(seat.elapsedAt(now), Duration.zero);
  });

  test('elapsedAt preserves a negative duration for a future start time', () {
    final seat = Seat(
      seatId: 'seat-001',
      seatNumber: 1,
      isOccupied: true,
      sessionStartedAt: now.add(const Duration(seconds: 30)),
    );

    expect(seat.elapsedAt(now), const Duration(seconds: -30));
  });
}
