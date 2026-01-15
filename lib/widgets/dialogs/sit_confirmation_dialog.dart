import 'package:flutter/material.dart';
import '../../models/seat.dart';

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
    builder: (dialogContext) => AlertDialog(
      title: Text('Seat ${seat.seatNumber}'),
      content: const Text('Do you want to take this seat and start studying?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
          ),
          child: const Text('Sit Down', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
