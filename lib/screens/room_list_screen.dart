import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/app_localizations.dart';
import '../models/room.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_settings_provider.dart';
import '../utils/error_localization.dart';
import '../services/notification_service.dart';
import '../widgets/room_card.dart';
import 'room_detail_screen.dart';
import 'study_history_screen.dart';
import 'user_settings_screen.dart';

/// Main screen displaying list of available study rooms.
class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen>
    with WidgetsBindingObserver {
  late final StreamSubscription<void> _sessionTaps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionTaps = NotificationService().sessionTaps.listen((_) => _openActiveRoom());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final rooms = context.read<RoomProvider>();
      final session = context.read<SessionProvider>();
      await rooms.fetchRooms();
      if (!mounted) return;
      await session.restoreSessionIfNeeded();
      if (mounted && session.state != SessionState.idle) _openActiveRoom();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context)!;
    context.read<TimerProvider>().updateLocalization(
      focusFinishedTitle: l10n.notificationFocusFinished,
      breakFinishedTitle: l10n.notificationBreakFinished,
      focusFinishedBody: l10n.notificationTimeForBreak,
      breakFinishedBody: l10n.notificationTimeToFocus,
    );
    context.read<SessionProvider>().setNotificationLocale(Localizations.localeOf(context).languageCode);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(context.read<SessionProvider>().refreshStudyNotification());
    }
  }

  @override
  void dispose() {
    _sessionTaps.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _roomRouteName(String roomId) => '/rooms/$roomId';

  Route<void> _roomRoute(Room room) => MaterialPageRoute<void>(
        settings: RouteSettings(name: _roomRouteName(room.roomId)),
        builder: (_) => RoomDetailScreen(room: room),
      );

  void _openActiveRoom() {
    if (!mounted) return;
    final roomId = context.read<SessionProvider>().currentRoomId;
    if (roomId == null) return;
    final room = context.read<RoomProvider>().getRoom(roomId);
    if (room == null) return;

    final navigator = Navigator.of(context);
    var roomOpened = false;
    navigator.popUntil((route) {
      roomOpened = route.settings.name == _roomRouteName(roomId);
      return roomOpened || route.isFirst;
    });
    if (!roomOpened) navigator.push(_roomRoute(room));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.landscape,
              color: Theme.of(context).appBarTheme.foregroundColor,
              size: 28,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
              l10n.appTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).appBarTheme.foregroundColor,
                fontWeight: FontWeight.bold,
              ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.studyHistory,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const StudyHistoryScreen(),
                ),
              );
            },
          ),
          Consumer2<AuthProvider, UserSettingsProvider>(
            builder: (context, auth, userSettings, _) {
              final photoUrl = googleAvatarUrl(auth, userSettings);
              
              return IconButton(
                tooltip: l10n.profileSettings,
                icon: photoUrl != null
                    ? CircleAvatar(
                        radius: 14,
                        backgroundImage: NetworkImage(photoUrl),
                      )
                    : ClipOval(
                        child: SvgPicture.string(
                          Jdenticon.toSvg(userSettings.iconSeed, size: 28),
                          width: 28,
                          height: 28,
                        ),
                      ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const UserSettingsScreen(),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Consumer<RoomProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            );
          }

          final roomsError = provider.roomsError;
          return RefreshIndicator(
            onRefresh: provider.fetchRooms,
            color: Theme.of(context).colorScheme.primary,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (roomsError != null)
                  SliverToBoxAdapter(
                    child: Card(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizeErrorKey(
                                l10n,
                                roomsError,
                                fallback: l10n.loadRoomsFailed,
                              ),
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: provider.fetchRooms,
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.chooseYourPeak,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.joinRoomSubtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).brightness == Brightness.dark 
                                ? Colors.grey.shade400 
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Room grid
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final cards = SliverChildBuilderDelegate(
                        (context, index) {
                          final room = provider.rooms[index];
                          return RoomCard(
                            room: room,
                            onTap: () => Navigator.of(context).push(_roomRoute(room)),
                          );
                        },
                        childCount: provider.rooms.length,
                      );
                      final textWidth = MediaQuery.textScalerOf(context).scale(16);
                      if (constraints.crossAxisExtent < 350 || textWidth > 18) {
                        return SliverList(delegate: cards);
                      }
                      return SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.9,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: cards,
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 20),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
