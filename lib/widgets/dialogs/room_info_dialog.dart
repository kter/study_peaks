import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';

/// Shows the room name, capacity, and current occupancy.
void showRoomInfoDialog({
  required BuildContext context,
  required Room room,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      final l10n = AppLocalizations.of(context)!;
      final colors = Theme.of(context).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.terrain, color: colors.primary, size: 32),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      room.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(
                icon: Icons.event_seat,
                text: l10n.roomCapacity(room.capacity),
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.people,
                text: l10n.roomCurrentOccupancy(room.currentOccupancy),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Flexible(
            child: Text(text, style: TextStyle(fontSize: 15, color: color))),
      ],
    );
  }
}
