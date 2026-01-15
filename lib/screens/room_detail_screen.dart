import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_settings_provider.dart';
import '../widgets/dialogs/leave_confirmation_dialog.dart';
import '../widgets/dialogs/room_info_dialog.dart';
import '../widgets/dialogs/sit_confirmation_dialog.dart';
import '../widgets/dialogs/user_info_dialog.dart';
import '../widgets/seat_grid.dart';
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
  bool _isTimerCollapsed = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<RoomProvider>().fetchSeats(widget.room.roomId);
      _restoreUserSeat();
    });
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
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
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _restoreUserSeat() {
    final session = context.read<SessionProvider>();
    if (session.isSeated &&
        session.currentRoomId == widget.room.roomId &&
        session.seatNumber != null) {
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
    setState(() => _isTimerCollapsed = !_isTimerCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTimerSection(),
          _buildErrorBanner(),
          _buildRoomInfoBar(),
          const SizedBox(height: 16),
          Expanded(
            child: SeatGrid(
              roomId: widget.room.roomId,
              onAlreadySeated: () => _showAlreadySeatedMessage(context),
              onEmptySeatTap: (seat) => _handleSitRequest(context, seat),
              onOccupiedSeatTap: (seat) => showUserInfoDialog(
                context: context,
                seat: seat,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
          onPressed: () => showRoomInfoDialog(context: context, room: widget.room),
        ),
      ],
    );
  }

  Widget _buildTimerSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.all(16),
      child: TimerWidget(
        isCollapsed: _isTimerCollapsed,
        onToggleCollapsed: _toggleTimerCollapsed,
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        if (session.error == null) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: Colors.red.shade700, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => session.clearError(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRoomInfoBar() {
    return Consumer<RoomProvider>(
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
              const Icon(Icons.people_outline, color: Color(0xFF1A237E)),
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
              _buildSeatActionButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeatActionButton() {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        if (session.isSeated) {
          return OutlinedButton.icon(
            onPressed: () => _handleLeaveRequest(context, session),
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
          onPressed: () => _showTakeSeatHint(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text('Take a Seat'),
        );
      },
    );
  }

  void _showTakeSeatHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Select an empty seat to sit down'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showAlreadySeatedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You are already seated!')),
    );
  }

  Future<void> _handleSitRequest(BuildContext context, Seat seat) async {
    final confirmed = await showSitConfirmationDialog(context: context, seat: seat);
    if (confirmed != true || !context.mounted) return;

    final success = await context.read<SessionProvider>().sit(
          widget.room.roomId,
          seat.seatNumber,
        );

    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You are now seated at seat ${seat.seatNumber}!'),
          backgroundColor: Colors.green,
        ),
      );
      // Start timer when sitting down
      context.read<TimerProvider>().start();
      final userSettings = context.read<UserSettingsProvider>();
      context.read<RoomProvider>().updateSeatOccupancy(
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
      final error = context.read<SessionProvider>().error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to sit: $error'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _handleLeaveRequest(BuildContext context, SessionProvider session) async {
    final confirmed = await showLeaveConfirmationDialog(context: context);
    if (confirmed != true || !context.mounted) return;

    final seatNumber = session.seatNumber;
    final success = await session.leave();

    if (context.mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have left your seat.')),
      );
      // Reset timer when leaving
      context.read<TimerProvider>().reset();
      if (seatNumber != null) {
        context.read<RoomProvider>().clearSeatOccupancy(
              widget.room.roomId,
              seatNumber,
            );
      }
    }
  }
}
