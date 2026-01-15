import 'package:flutter/material.dart';
import '../../models/seat.dart';

/// Modal bottom sheet displaying user information.
/// 
/// Shows user's display name, status message, and study duration
/// when tapping on an occupied seat.
void showUserInfoDialog({
  required BuildContext context,
  required Seat seat,
}) {
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
