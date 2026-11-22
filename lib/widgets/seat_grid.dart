import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import '../utils/error_localization.dart';
import 'seat_widget.dart';

/// A widget that displays when the user is already seated and taps another seat.
typedef AlreadySeatedCallback = void Function();

/// A widget that displays when an empty seat is tapped.
typedef EmptySeatTapCallback = void Function(Seat seat);

/// A widget that displays when an occupied seat is tapped.
typedef OccupiedSeatTapCallback = void Function(Seat seat);

/// Grid view of seats for a room.
/// 
/// Displays seats in a grid with at least four columns and refresh capability.
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
        final l10n = AppLocalizations.of(context)!;
        if (seats.isEmpty) {
          final error = roomProvider.seatError(roomId);
          if (error == null) {
            return Center(child: Text(l10n.noSeatsAvailable));
          }
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(localizeErrorKey(l10n, error, fallback: l10n.loadSeatsFailed)),
                  TextButton(
                    onPressed: () => roomProvider.fetchSeats(roomId),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RefreshIndicator(
              onRefresh: () => roomProvider.fetchSeats(roomId),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: math.max(4, (constraints.maxWidth / 110).floor()),
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
