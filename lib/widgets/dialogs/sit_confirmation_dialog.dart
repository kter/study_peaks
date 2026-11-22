import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/models.dart';

enum SitConfirmationResult { cancel, sit, sitAndPin }

/// Confirms sitting in a seat, optionally with screen pinning.
Future<SitConfirmationResult> showSitConfirmationDialog({
  required BuildContext context,
  required Seat seat,
  bool offerScreenPin = false,
}) async {
  final result = await showDialog<SitConfirmationResult>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        title: Text(l10n.seatTitle(seat.seatNumber)),
        content: Text(l10n.sitQuestion),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(SitConfirmationResult.cancel),
            child:
                Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          if (offerScreenPin) ...[
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(SitConfirmationResult.sit),
              child: Text(l10n.sitDown),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(SitConfirmationResult.sitAndPin),
              child: Text(l10n.sitAndPin),
            ),
          ] else
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(SitConfirmationResult.sit),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
              ),
              child: Text(l10n.sitDown,
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      );
    },
  );
  return result ?? SitConfirmationResult.cancel;
}
