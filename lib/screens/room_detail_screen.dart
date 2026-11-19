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
import '../repositories/study_history_repository.dart';
import '../utils/error_localization.dart';
import '../widgets/dialogs/leave_confirmation_dialog.dart';
import '../widgets/dialogs/leave_summary_dialog.dart';
import '../widgets/dialogs/room_info_dialog.dart';
import '../widgets/dialogs/sit_confirmation_dialog.dart';
import '../widgets/dialogs/user_info_dialog.dart';
import '../widgets/seat_grid.dart';
import '../widgets/timer_widget.dart';
import 'study_history_screen.dart';

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
  bool _leaveFlowActive = false;
  Timer? _seatRefreshTimer;
  SessionProvider? _sessionProvider;
  TimerProvider? _timerProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
 
    // Add listener for session errors
    _sessionProvider = context.read<SessionProvider>();
    _sessionProvider?.addListener(_onErrorChanged);

    _timerProvider = context.read<TimerProvider>();

    // Set up lock task exit callback
    _timerProvider?.onLockTaskExited = _onLockTaskExited;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final roomProvider = context.read<RoomProvider>();
      await roomProvider.fetchSeats(widget.room.roomId);

      await _restoreSessionIfNeeded();
      if (mounted) {
        _restoreUserSeat();
        if (_sessionProvider?.error == SessionProvider.seatReleasedMessageKey) {
          _onErrorChanged();
        }
      }
    });
    // 定期的に席データを更新して他ユーザーの変更を反映
    _seatRefreshTimer = Timer.periodic(
      const Duration(seconds: AppConfig.seatRefreshIntervalSeconds),
      (_) => _refreshSeats(),
    );
  }

  Future<void> _restoreSessionIfNeeded() async {
    if (!mounted) return;

    final sessionProvider = context.read<SessionProvider>();
    if (sessionProvider.isSeated) return;

    final restored = await sessionProvider.restoreSessionIfNeeded();
    if (restored && mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sessionRestoredFromSeatMap),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _onErrorChanged() {
    if (!mounted) return;

    final session = context.read<SessionProvider>();
    final errorKey = session.error;
    if (errorKey != null) {
      final l10n = AppLocalizations.of(context)!;
      final errorMessage = switch (errorKey) {
        'historySaveFailed' => l10n.historySaveFailed,
        'historyOtherOwnerActive' => l10n.historyOtherOwnerActive,
        SessionProvider.seatReleasedMessageKey => l10n.sessionSeatReleased,
        final key => localizeErrorKey(l10n, key),
      };
      final seatReleased = errorKey == SessionProvider.seatReleasedMessageKey;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: seatReleased ? null : Colors.red,
        ),
      );

      // Clear error immediately after showing SnackBar so it doesn't persist
      session.clearError();
      if (seatReleased) unawaited(_refreshSeats());
    }
  }

  /// 席データをサーバーから再取得
  Future<void> _refreshSeats() async {
    if (!mounted) return;
    await context.read<RoomProvider>().fetchSeats(widget.room.roomId);
    // 自分のセッションを再適用（サーバーのデータで上書きされないように）
    _restoreUserSeat();
  }

  void _onLockTaskExited() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.lockTaskExitedMessage),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  void dispose() {
    _seatRefreshTimer?.cancel();
    _sessionProvider?.removeListener(_onErrorChanged);
    _timerProvider?.onLockTaskExited = null;
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
        !session.hasReleasedSeat &&
        session.currentRoomId == widget.room.roomId &&
        session.seatNumber != null) {
      final userSettings = context.read<UserSettingsProvider>();
      final authProvider = context.read<AuthProvider>();
      
      final photoUrl = googleAvatarUrl(authProvider, userSettings);

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
          onPressed: () => showRoomInfoDialog(
            context: context,
            room: context.read<RoomProvider>().getRoom(widget.room.roomId) ??
                widget.room,
          ),
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
        final canLeave = session.isSeated && !_leaveFlowActive;
        final l10n = AppLocalizations.of(context)!;
        return OutlinedButton.icon(
          onPressed: canLeave ? () => _handleLeaveRequest(session) : null,
          icon: const Icon(Icons.exit_to_app),
          label: Text(
            session.isFinalizing ? l10n.leaveRetry : l10n.leaveSeat,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            disabledForegroundColor: Colors.grey,
            side: BorderSide(color: canLeave ? Colors.red : Colors.grey),
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

    final photoUrl = googleAvatarUrl(authProvider, userSettings);

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
          notificationFocusRemaining: l10n.notificationFocusRemaining('{duration}'),
          notificationBreakRemaining: l10n.notificationBreakRemaining('{duration}'),
          notificationFocusFinished: l10n.notificationFocusFinished,
          notificationBreakFinished: l10n.notificationBreakFinished,
        );

    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You are now seated at seat ${seat.seatNumber}!'),
          backgroundColor: Colors.green,
        ),
      );
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

  Future<void> _handleLeaveRequest(SessionProvider session) async {
    if (_leaveFlowActive) return;
    setState(() => _leaveFlowActive = true);
    try {
      if (!session.isFinalizing) {
        final confirmed = await showLeaveConfirmationDialog(context: context);
        if (confirmed != true || !mounted) return;
      }

      final navigator = Navigator.of(context, rootNavigator: true);
      final rooms = context.read<RoomProvider>();
      final roomId = session.currentRoomId;
      final seatNumber = session.seatNumber;
      final result = await session.leave();
      if (!navigator.mounted) return;

      switch (result) {
        case LeaveFailure.unavailable:
          return;
        case LeaveFailure.storage:
        case LeaveFailure.storageAfterRelease:
          if (result == LeaveFailure.storageAfterRelease && roomId != null) {
            unawaited(rooms.fetchSeats(roomId));
          }
          final l10n = AppLocalizations.of(navigator.context)!;
          ScaffoldMessenger.of(navigator.context).showSnackBar(
            SnackBar(
              content: Text(l10n.historySaveFailed),
              backgroundColor: Colors.red,
            ),
          );
        case LeaveCompleted():
          final record = result.record;
          final cachedSeatIsOurs = rooms.getSeats(record.roomId).any((seat) =>
              seat.seatNumber == seatNumber &&
              seat.sessionStartedAt?.isAtSameMomentAs(record.startTime) == true);
          if (result.serverFailure == null && cachedSeatIsOurs) {
            rooms.clearSeatOccupancy(record.roomId, seatNumber!);
          } else {
            unawaited(rooms.fetchSeats(record.roomId));
          }
          await _showLeaveFeedback(navigator, session, result);
      }
    } finally {
      if (mounted) setState(() => _leaveFlowActive = false);
    }
  }

  Future<void> _showLeaveFeedback(
    NavigatorState navigator,
    SessionProvider session,
    LeaveCompleted result,
  ) async {
    final context = navigator.context;
    final l10n = AppLocalizations.of(context)!;
    final warning = switch (result.serverFailure) {
      LeaveServerFailure.connection => l10n.leaveConnectionFailed,
      LeaveServerFailure.request => l10n.leaveRequestFailed,
      null => null,
    };
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final record = result.record;
    if (record.durationSeconds == 0 ||
        !record.isVisibleTo(session.historyOwnerId)) {
      messenger.showSnackBar(SnackBar(content: Text(warning ?? l10n.leftSeat)));
      return;
    }

    final repository = context.read<StudyHistoryRepository>();
    final openHistory = await showDialog<bool>(
      context: context,
      builder: (_) => LeaveSummaryDialog(
        record: record,
        warning: warning,
        loadHistory: () => repository.getHistory(ownerId: record.ownerId),
      ),
    );
    if (openHistory == true &&
        navigator.mounted &&
        record.isVisibleTo(session.historyOwnerId)) {
      unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => StudyHistoryScreen(
          showLegacyHistory: record.ownerId == StudySession.legacyOwner,
        ),
      )));
    }
  }
}
