import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_settings_provider.dart';
import '../utils/error_localization.dart';
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

class _RoomListScreenState extends State<RoomListScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch rooms and restore session on init
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final roomProvider = context.read<RoomProvider>();
      final sessionProvider = context.read<SessionProvider>();
      
      // Fetch rooms first
      await roomProvider.fetchRooms();
      
      
      // Update TimerProvider with localized strings
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        context.read<TimerProvider>().updateLocalization(
          focusFinishedTitle: l10n.notificationFocusFinished,
          breakFinishedTitle: l10n.notificationBreakFinished,
          focusFinishedBody: l10n.notificationTimeForBreak,
          breakFinishedBody: l10n.notificationTimeToFocus,
        );
      }

      // Recover the saved session before trying to navigate to its room.
      final restored = await sessionProvider.restoreSessionIfNeeded();
      if (restored && mounted) {
        // Find the room the user was in and navigate to it
        final roomId = sessionProvider.currentRoomId;
        if (roomId != null) {
          final room = roomProvider.rooms.where((r) => r.roomId == roomId).firstOrNull;
          if (room != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => RoomDetailScreen(room: room),
              ),
            );
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
            Text(
              'Global Study Peaks',
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
            icon: const Icon(Icons.history),
            tooltip: AppLocalizations.of(context)!.studyHistory,
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

          final l10n = AppLocalizations.of(context)!;
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
                          'Choose Your Peak',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Join a virtual study room and start focusing',
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
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final room = provider.rooms[index];
                        return RoomCard(
                          room: room,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => RoomDetailScreen(room: room),
                              ),
                            );
                          },
                        );
                      },
                      childCount: provider.rooms.length,
                    ),
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
