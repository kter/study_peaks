import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_settings_provider.dart';
import '../services/network_exception.dart';
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
  Timer? _seatRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
 
    // Add listener for session errors
    final sessionProvider = context.read<SessionProvider>();
    sessionProvider.addListener(_onErrorChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final roomProvider = context.read<RoomProvider>();
      await roomProvider.fetchSeats(widget.room.roomId);
      
      // Try to restore session from seat map if user is found
      await _restoreSessionFromSeatMapIfNeeded();
      
      _restoreUserSeat();
    });
    // 定期的に席データを更新して他ユーザーの変更を反映
    _seatRefreshTimer = Timer.periodic(
      const Duration(seconds: AppConfig.seatRefreshIntervalSeconds),
      (_) => _refreshSeats(),
    );
  }

  /// シートマップから自分のセッションを検出して復元
  Future<void> _restoreSessionFromSeatMapIfNeeded() async {
    if (!mounted) return;
    
    final sessionProvider = context.read<SessionProvider>();
    final authProvider = context.read<AuthProvider>();
    final roomProvider = context.read<RoomProvider>();
    
    // Only attempt restore if not already seated and user is signed in
    if (sessionProvider.isSeated || !authProvider.isSignedIn) return;
    
    final seats = roomProvider.getSeats(widget.room.roomId);
    final userId = authProvider.userId;
    
    final restored = await sessionProvider.restoreFromSeatData(
      roomId: widget.room.roomId,
      seats: seats,
      userId: userId,
      roomName: widget.room.name,
    );
    
    if (restored && mounted) {
      // Start timer if session was restored
      context.read<TimerProvider>().start();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session restored from seat map'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _onErrorChanged() {
    if (!mounted) return;
    
    final session = context.read<SessionProvider>();
    if (session.error != null) {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = session.error == NetworkErrorKey.networkError
          ? l10n.networkError
          : session.error!;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
      
      // Clear error immediately after showing SnackBar so it doesn't persist
      session.clearError();
    }
  }

  /// 席データをサーバーから再取得
  Future<void> _refreshSeats() async {
    if (!mounted) return;
    await context.read<RoomProvider>().fetchSeats(widget.room.roomId);
    // 自分のセッションを再適用（サーバーのデータで上書きされないように）
    _restoreUserSeat();
  }

  @override
  void dispose() {
    _seatRefreshTimer?.cancel();
    context.read<SessionProvider>().removeListener(_onErrorChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // アプリ復帰時に席データを再取得
      _refreshSeats();
    }
  }

  void _restoreUserSeat() {
    final session = context.read<SessionProvider>();
    if (session.isSeated &&
        session.currentRoomId == widget.room.roomId &&
        session.seatNumber != null) {
      final userSettings = context.read<UserSettingsProvider>();
      final authProvider = context.read<AuthProvider>();
      
      // Determine photoUrl for restore
      final String? photoUrl = (authProvider.isSignedIn &&
              authProvider.photoUrl != null &&
              userSettings.useGoogleAvatar)
          ? authProvider.photoUrl
          : null;

      context.read<RoomProvider>().updateSeatOccupancy(
            roomId: widget.room.roomId,
            seatNumber: session.seatNumber!,
            isOccupied: true,
            user: SeatUser(
              userId: session.sessionId ?? userSettings.iconSeed,
              displayName: userSettings.displayName,
              countryCode: userSettings.countryCode,
              iconSeed: userSettings.iconSeed,
              photoUrl: photoUrl,
              statusMessage: '',
            ),
            sessionStartedAt: session.sessionStartedAt,
          );
    }
  }

  void _toggleTimerCollapsed() {
    setState(() => _isTimerCollapsed = !_isTimerCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTimerSection(),
          // Persistent error banner removed
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
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: Theme.of(context).appBarTheme.foregroundColor),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terrain, color: Theme.of(context).appBarTheme.foregroundColor, size: 24),
          const SizedBox(width: 8),
          Text(
            widget.room.name,
            style: TextStyle(
              color: Theme.of(context).appBarTheme.foregroundColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Icon(Icons.info_outline, color: Theme.of(context).appBarTheme.foregroundColor),
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



  Widget _buildRoomInfoBar() {
    return Consumer<RoomProvider>(
      builder: (context, roomProvider, _) {
        final seats = roomProvider.getSeats(widget.room.roomId);
        final occupiedCount = seats.where((s) => s.isOccupied).length;

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final primaryColor = Theme.of(context).colorScheme.primary;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: cardColor,
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
              Icon(Icons.people_outline, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                '$occupiedCount studying',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
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
        final isSeated = session.isSeated;
        return OutlinedButton.icon(
          onPressed: isSeated ? () => _handleLeaveRequest(context, session) : null,
          icon: const Icon(Icons.exit_to_app),
          label: const Text('Leave Seat'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            disabledForegroundColor: Colors.grey,
            side: BorderSide(color: isSeated ? Colors.red : Colors.grey),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      },
    );
  }



  void _showAlreadySeatedMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You are already seated!')),
    );
  }

  Future<void> _handleSitRequest(BuildContext context, Seat seat) async {
    // 着席前に最新の席データを取得（競合防止）
    await context.read<RoomProvider>().fetchSeats(widget.room.roomId);
    if (!context.mounted) return;

    // 席が既に埋まっていないか再確認
    final seats = context.read<RoomProvider>().getSeats(widget.room.roomId);
    final currentSeat = seats.firstWhere(
      (s) => s.seatNumber == seat.seatNumber,
      orElse: () => seat,
    );
    if (currentSeat.isOccupied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.seatTaken),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirmed = await showSitConfirmationDialog(context: context, seat: seat);
    if (confirmed != true || !context.mounted) return;

    final userSettings = context.read<UserSettingsProvider>();
    final authProvider = context.read<AuthProvider>();
    final l10n = AppLocalizations.of(context)!;

    // Determine photoUrl: only send if signed in and 'useGoogleAvatar' is true
    final String? photoUrl = (authProvider.isSignedIn &&
            authProvider.photoUrl != null &&
            userSettings.useGoogleAvatar)
        ? authProvider.photoUrl
        : null;

    final success = await context.read<SessionProvider>().sit(
          widget.room.roomId,
          seat.seatNumber,
          roomName: widget.room.name,
          displayName: userSettings.displayName,
          countryCode: userSettings.countryCode,
          iconSeed: userSettings.iconSeed,
          photoUrl: photoUrl,
          notificationTitle: l10n.notificationStudyingAt(widget.room.name),
          notificationSessionStarted: l10n.notificationSessionStarted,
          notificationStudyingFormat: l10n.notificationStudying('{duration}'),
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
              iconSeed: userSettings.iconSeed,
              photoUrl: photoUrl,
              statusMessage: '',
            ),
            sessionStartedAt: context.read<SessionProvider>().sessionStartedAt,
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
