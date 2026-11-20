import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/models.dart';
import '../../utils/formatters.dart';
import '../seat_elapsed_duration.dart';

/// Shows the user and the time elapsed since they took the seat.
void showUserInfoDialog({
  required BuildContext context,
  required Seat seat,
}) {
  final user = seat.user;
  if (user == null) return;

  showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final l10n = AppLocalizations.of(context)!;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.displayName, style: theme.textTheme.titleLarge),
              if (user.statusMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(user.statusMessage, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.timer, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: SeatElapsedDuration(
                      seat: seat,
                      builder: (context, elapsed) {
                        final seconds =
                            elapsed.inMinutes * Duration.secondsPerMinute;
                        return Text(l10n.seatedFor(
                            Formatters.formatStudyDuration(seconds, l10n)));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
