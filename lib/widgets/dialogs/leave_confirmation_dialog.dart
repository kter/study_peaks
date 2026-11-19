import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Returns true when the user confirms leaving the seat.
Future<bool?> showLeaveConfirmationDialog({
  required BuildContext context,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return AlertDialog(
        title: Text(l10n.leaveSeat),
        content: Text(l10n.leaveSeatConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:
                Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.leave),
          ),
        ],
      );
    },
  );
}
