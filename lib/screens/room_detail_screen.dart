import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/seat.dart';
import '../providers/timer_provider.dart';
import '../widgets/seat_widget.dart';
import '../widgets/timer_widget.dart';

/// Screen displaying theater-style seat grid for a room.
class RoomDetailScreen extends StatelessWidget {
  final Room room;

  const RoomDetailScreen({
    super.key,
    required this.room,
  });

  @override
  Widget build(BuildContext context) {
    // Generate mock seats for demo
    final seats = _generateMockSeats();

    return ChangeNotifierProvider(
      create: (_) => TimerProvider(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1A237E)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terrain, color: Color(0xFF1A237E), size: 24),
              const SizedBox(width: 8),
              Text(
                room.name,
                style: const TextStyle(
                  color: Color(0xFF1A237E),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline, color: Color(0xFF1A237E)),
              onPressed: () => _showRoomInfo(context),
            ),
          ],
        ),
        body: Column(
          children: [
            // Timer section (collapsible)
            Container(
              margin: const EdgeInsets.all(16),
              child: const TimerWidget(),
            ),
            // Room info bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    color: Color(0xFF1A237E),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${seats.where((s) => s.isOccupied).length} studying',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => _takeSeat(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A237E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Take a Seat'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Seat grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: seats.length,
                  itemBuilder: (context, index) {
                    return SeatWidget(
                      seat: seats[index],
                      size: 60,
                      onTap: () {
                        final seat = seats[index];
                        if (!seat.isOccupied) {
                          _confirmSit(context, seat);
                        } else {
                          _showUserInfo(context, seat);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _takeSeat(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select an empty seat to sit down'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _confirmSit(BuildContext context, Seat seat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Seat ${seat.seatNumber}'),
        content: const Text('Do you want to take this seat and start studying?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('You are now seated at seat ${seat.seatNumber}!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
            ),
            child: const Text('Sit Down', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showUserInfo(BuildContext context, Seat seat) {
    if (seat.user == null) return;
    final user = seat.user!;
    final duration = Duration(seconds: seat.currentSessionDuration);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user.displayName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 8),
            if (user.statusMessage.isNotEmpty)
              Text(
                '"${user.statusMessage}"',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer, color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                Text(
                  'Studying for ${duration.inHours}h ${duration.inMinutes.remainder(60)}m',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showRoomInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terrain, color: Color(0xFF1A237E), size: 32),
                const SizedBox(width: 12),
                Text(
                  room.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(Icons.event_seat, 'Capacity: ${room.capacity} seats'),
            const SizedBox(height: 8),
            _infoRow(Icons.people, 'Currently: ${room.currentOccupancy} studying'),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  List<Seat> _generateMockSeats() {
    final mockUsers = [
      const SeatUser(userId: 'u1', displayName: 'Taro', countryCode: 'JP', statusMessage: '頑張る！'),
      const SeatUser(userId: 'u2', displayName: 'Emma', countryCode: 'US', statusMessage: 'Studying for finals'),
      const SeatUser(userId: 'u3', displayName: 'Liu Wei', countryCode: 'CN', statusMessage: '专注学习'),
      const SeatUser(userId: 'u4', displayName: 'Hans', countryCode: 'DE', statusMessage: 'Prüfungsvorbereitung'),
      const SeatUser(userId: 'u5', displayName: 'Maria', countryCode: 'BR', statusMessage: 'Estudando!'),
    ];

    final List<Seat> seats = [];
    int userIdx = 0;
    final occupiedSeats = [1, 3, 7, 8, 12, 15, 20];

    for (int i = 1; i <= 24; i++) {
      if (occupiedSeats.contains(i) && userIdx < mockUsers.length) {
        seats.add(Seat(
          seatId: 'seat-$i',
          seatNumber: i,
          isOccupied: true,
          user: mockUsers[userIdx],
          currentSessionDuration: (userIdx + 1) * 900,
        ));
        userIdx++;
      } else {
        seats.add(Seat.empty(i));
      }
    }
    return seats;
  }
}
