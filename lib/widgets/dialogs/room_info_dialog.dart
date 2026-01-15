import 'package:flutter/material.dart';
import '../../models/seat.dart';

/// Modal bottom sheet displaying room information.
/// 
/// Shows room name, capacity, and current occupancy.
void showRoomInfoDialog({
  required BuildContext context,
  required Room room,
}) {
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
          _InfoRow(icon: Icons.event_seat, text: 'Capacity: ${room.capacity} seats'),
          const SizedBox(height: 8),
          _InfoRow(icon: Icons.people, text: 'Currently: ${room.currentOccupancy} studying'),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
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
