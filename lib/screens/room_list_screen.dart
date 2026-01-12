import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../widgets/room_card.dart';
import 'room_detail_screen.dart';

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
    // Fetch rooms on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomProvider>().fetchRooms();
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
          Consumer<AuthProvider>(
            builder: (context, auth, _) => IconButton(
              icon: auth.isSignedIn && auth.photoUrl != null
                  ? CircleAvatar(
                      radius: 14,
                      backgroundImage: NetworkImage(auth.photoUrl!),
                    )
                  : Icon(
                      Icons.person_outline,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              onPressed: () => _showProfileDialog(context, auth),
            ),
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
              Text(
                auth.displayName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
}
