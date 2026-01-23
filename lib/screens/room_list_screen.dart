import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jdenticon_dart/jdenticon_dart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../providers/session_provider.dart';
import '../providers/user_settings_provider.dart';
import '../services/network_exception.dart';
import '../widgets/room_card.dart';
import 'room_detail_screen.dart';
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
      
      // Try to restore session if foreground service is running
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
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.landscape,
              color: Color(0xFF1A237E),
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              'Global Study Peaks',
              style: TextStyle(
                color: Color(0xFF1A237E),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Consumer2<AuthProvider, UserSettingsProvider>(
            builder: (context, auth, userSettings, _) {
              final showGoogleAvatar = auth.isSignedIn && 
                  auth.photoUrl != null && 
                  userSettings.useGoogleAvatar;
              
              return IconButton(
                icon: showGoogleAvatar
                    ? CircleAvatar(
                        radius: 14,
                        backgroundImage: NetworkImage(auth.photoUrl!),
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
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF1A237E),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.fetchRooms,
            color: const Color(0xFF1A237E),
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Choose Your Peak',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Join a virtual study room and start focusing',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
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

  void _showProfileDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(auth.isSignedIn ? 'Profile' : 'Sign In'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (auth.isSignedIn) ...[
              if (auth.photoUrl != null)
                CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(auth.photoUrl!),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    auth.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () {
                      Navigator.pop(context);
                      _showEditNameDialog(context, auth);
                    },
                    tooltip: 'Edit Name',
                  ),
                ],
              ),
              Text(
                auth.email,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ] else ...[
              Icon(
                Icons.account_circle,
                size: 80,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'Sign in to save your study progress and sync across devices.',
                textAlign: TextAlign.center,
              ),
            ],
            if (auth.error != null) ...[
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context)!;
                  final errorMessage = auth.error == NetworkErrorKey.networkError
                      ? l10n.networkError
                      : auth.error!;
                  return Text(
                    errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                    textAlign: TextAlign.center,
                  );
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (auth.isSignedIn)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await auth.signOut();
              },
              child: const Text('Sign Out'),
            )
          else
            FilledButton.icon(
              onPressed: auth.isLoading
                  ? null
                  : () async {
                      final success = await auth.signInWithGoogle();
                      if (context.mounted) {
                        Navigator.pop(context);
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Signed in successfully!')),
                          );
                        } else if (auth.error != null) {
                          final l10n = AppLocalizations.of(context)!;
                          final errorMessage = auth.error == NetworkErrorKey.networkError
                              ? l10n.networkError
                              : auth.error!;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(errorMessage),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: auth.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(auth.isLoading ? 'Signing in...' : 'Sign in with Google'),
            ),
        ],
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, AuthProvider auth) {
    final controller = TextEditingController(text: auth.displayName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                try {
                  await auth.updateUserName(newName);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Name updated successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    // Localize network error messages
                    final l10n = AppLocalizations.of(context)!;
                    final errorMessage = isNetworkError(e)
                        ? l10n.networkError
                        : e.toString();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorMessage),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
