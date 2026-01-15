import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import 'seat_widget.dart';

/// A widget that displays when the user is already seated and taps another seat.
typedef AlreadySeatedCallback = void Function();

/// A widget that displays when an empty seat is tapped.
typedef EmptySeatTapCallback = void Function(Seat seat);

/// A widget that displays when an occupied seat is tapped.
typedef OccupiedSeatTapCallback = void Function(Seat seat);

/// Grid view of seats for a room.
/// 
/// Displays seats in a 4-column grid with refresh capability.
/// Handles seat tap callbacks for empty and occupied seats.
class SeatGrid extends StatelessWidget {
  final String roomId;
  final AlreadySeatedCallback onAlreadySeated;
  final EmptySeatTapCallback onEmptySeatTap;
  final OccupiedSeatTapCallback onOccupiedSeatTap;

  const SeatGrid({
    super.key,
    required this.roomId,
    required this.onAlreadySeated,
    required this.onEmptySeatTap,
    required this.onOccupiedSeatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<RoomProvider, SessionProvider>(
      builder: (context, roomProvider, session, child) {
        if (roomProvider.isLoading && roomProvider.getSeats(roomId).isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final seats = roomProvider.getSeats(roomId);
        if (seats.isEmpty) {
          return const Center(child: Text('No seats available'));
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RefreshIndicator(
            onRefresh: () => roomProvider.fetchSeats(roomId),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: seats.length,
              itemBuilder: (context, index) {
                final seat = seats[index];
                // Check if this seat belongs to the current user
                final isCurrentUserSeat = session.isSeated &&
                    session.currentRoomId == roomId &&
                    session.seatNumber == seat.seatNumber;

                return SeatWidget(
                  seat: seat,
                  size: 60,
                  isCurrentUser: isCurrentUserSeat,
                  onTap: () => _handleSeatTap(seat, session),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _handleSeatTap(Seat seat, SessionProvider session) {
    if (!seat.isOccupied) {
      if (session.isSeated) {
        onAlreadySeated();
      } else {
        onEmptySeatTap(seat);
      }
    } else {
      onOccupiedSeatTap(seat);
    }
  }
}
