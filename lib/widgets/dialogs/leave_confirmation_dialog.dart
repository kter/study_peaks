import 'package:flutter/material.dart';

/// Dialog to confirm leaving a seat.
/// 
/// Shows a confirmation dialog when user attempts to leave their seat.
/// Returns true if user confirmed, false if cancelled.
Future<bool?> showLeaveConfirmationDialog({
  required BuildContext context,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Leave Seat'),
      content: const Text('Are you sure you want to leave your seat?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Leave'),
        ),
      ],
    ),
  );
}
