import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/seat.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_settings_provider.dart';
import '../widgets/seat_widget.dart';
import '../widgets/timer_widget.dart';

/// Screen displaying theater-style seat grid for a room.

class RoomDetailScreen extends StatefulWidget {
  final Room room;

  const RoomDetailScreen({
    super.key,
    required this.room,
  });

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen>
    with WidgetsBindingObserver {
  bool _isTimerCollapsed = true; // Start collapsed to show more seats
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<RoomProvider>().fetchSeats(widget.room.roomId);
      // Restore current user's seat if they are seated in this room
      _restoreUserSeat();
    });
    // Start periodic refresh for seat duration updates (every minute)
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh UI when app resumes to show correct durations
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// Restore the current user's seat if they are seated in this room
  void _restoreUserSeat() {
    final session = context.read<SessionProvider>();
    if (session.isSeated && session.currentRoomId == widget.room.roomId && session.seatNumber != null) {
      final userSettings = context.read<UserSettingsProvider>();
      context.read<RoomProvider>().updateSeatOccupancy(
        roomId: widget.room.roomId,
        seatNumber: session.seatNumber!,
        isOccupied: true,
        user: SeatUser(
          userId: userSettings.iconSeed,
          displayName: userSettings.displayName,
          countryCode: userSettings.countryCode,
          statusMessage: '',
        ),
      );
    }
  }

  void _toggleTimerCollapsed() {
    setState(() {
      _isTimerCollapsed = !_isTimerCollapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TimerProvider()),
      ],
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
                widget.room.name,
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.all(16),
              child: TimerWidget(
                isCollapsed: _isTimerCollapsed,
                onToggleCollapsed: _toggleTimerCollapsed,
              ),
            ),
            // Room info bar
            Consumer<RoomProvider>(
              builder: (context, roomProvider, _) {
                final seats = roomProvider.getSeats(widget.room.roomId);
                final occupiedCount = seats.where((s) => s.isOccupied).length;
                
                return Container(
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
                        '$occupiedCount studying',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      const Spacer(),
                      Consumer<SessionProvider>(
                        builder: (context, session, _) {
                          if (session.isSeated) {
                            return OutlinedButton.icon(
                              onPressed: () => _confirmLeave(context, session),
                              icon: const Icon(Icons.exit_to_app),
                              label: const Text('Leave Seat'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            );
                          }
                          return ElevatedButton(
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
                          );
                        }
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Seat grid
            Expanded(
              child: Consumer2<RoomProvider, SessionProvider>(
                builder: (context, roomProvider, session, child) {
                  if (roomProvider.isLoading && roomProvider.getSeats(widget.room.roomId).isEmpty) {
                     return const Center(child: CircularProgressIndicator());
                  }

                  final seats = roomProvider.getSeats(widget.room.roomId);
                  if (seats.isEmpty) {
                    return const Center(child: Text('No seats available'));
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: RefreshIndicator(
                      onRefresh: () => roomProvider.fetchSeats(widget.room.roomId),
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
                              session.currentRoomId == widget.room.roomId &&
                              session.seatNumber == seat.seatNumber;
                          
                          return SeatWidget(
                            seat: seat,
                            size: 60,
                            isCurrentUser: isCurrentUserSeat,
                            onTap: () {
                              if (!seat.isOccupied) {
                                if (session.isSeated) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('You are already seated!')),
                                  );
                                } else {
                                  _confirmSit(context, seat);
                                }
                              } else {
                                _showUserInfo(context, seat);
                              }
                            },
                          );
                        },
                      ),
                    ),
                  );
                },
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
    // Store reference to parent context before showing dialog
    final parentContext = context;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Seat ${seat.seatNumber}'),
        content: const Text('Do you want to take this seat and start studying?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final success = await parentContext
                  .read<SessionProvider>()
                  .sit(widget.room.roomId, seat.seatNumber);
              
              if (parentContext.mounted) {
                if (success) {
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    SnackBar(
                      content: Text('You are now seated at seat ${seat.seatNumber}!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // Update seat locally to show current user
                  final userSettings = parentContext.read<UserSettingsProvider>();
                  parentContext.read<RoomProvider>().updateSeatOccupancy(
                    roomId: widget.room.roomId,
                    seatNumber: seat.seatNumber,
                    isOccupied: true,
                    user: SeatUser(
                      userId: userSettings.iconSeed,
                      displayName: userSettings.displayName,
                      countryCode: userSettings.countryCode,
                      statusMessage: '',
                    ),
                  );
                } else {
                   final error = parentContext.read<SessionProvider>().error;
                   ScaffoldMessenger.of(parentContext).showSnackBar(
                    SnackBar(
                      content: Text('Failed to sit: $error'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
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

  void _confirmLeave(BuildContext context, SessionProvider session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Seat'),
        content: const Text('Are you sure you want to leave your seat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final seatNumber = session.seatNumber;
              final success = await session.leave();
              if (context.mounted && success) {
                 ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You have left your seat.')),
                  );
                 // Clear seat locally
                 if (seatNumber != null) {
                   context.read<RoomProvider>().clearSeatOccupancy(
                     widget.room.roomId,
                     seatNumber,
                   );
                 }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showUserInfo(BuildContext context, Seat seat) {
    if (seat.user == null) return;
    final user = seat.user!;
    // Calculate duration from sessionStartedAt for accurate time tracking
    final duration = seat.sessionStartedAt != null
        ? DateTime.now().difference(seat.sessionStartedAt!)
        : Duration.zero;

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
                  widget.room.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(Icons.event_seat, 'Capacity: ${widget.room.capacity} seats'),
            const SizedBox(height: 8),
            _infoRow(Icons.people, 'Currently: ${widget.room.currentOccupancy} studying'),
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
}
