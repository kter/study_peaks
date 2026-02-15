import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Result of the lock task confirmation dialog.
enum LockTaskDialogResult {
  lockAndStart,
  startWithoutLock,
  cancel,
}

/// Shows a dialog explaining screen pinning before activating it.
///
/// Returns [LockTaskDialogResult] indicating the user's choice.
Future<LockTaskDialogResult?> showLockTaskDialog({
  required BuildContext context,
}) {
  final l10n = AppLocalizations.of(context)!;

  return showDialog<LockTaskDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.lockTaskDialogTitle,
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.lockTaskDialogBody,
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(LockTaskDialogResult.cancel),
            child: Text(l10n.lockTaskDialogCancel),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(context).pop(LockTaskDialogResult.startWithoutLock),
            child: Text(l10n.lockTaskDialogStartWithoutLock),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(LockTaskDialogResult.lockAndStart),
            icon: const Icon(Icons.lock, size: 16),
            label: Text(l10n.lockTaskDialogPinAndStart),
          ),
        ],
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
    },
  );
}
