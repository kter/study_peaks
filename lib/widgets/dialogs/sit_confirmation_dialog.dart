import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';

/// Dialog to confirm sitting in a seat.
///
/// Shows a confirmation dialog when user attempts to take a seat.
/// Returns true if user confirmed, false if cancelled.
Future<bool?> showSitConfirmationDialog({
  required BuildContext context,
  required Seat seat,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        title: Text(l10n.seatTitle(seat.seatNumber)),
        content: Text(l10n.sitQuestion),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
            ),
            child:
                Text(l10n.sitDown, style: const TextStyle(color: Colors.white)),
          ),
        ],
      );
    },
  );
}
