import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/formatters.dart';

class StudyDurationRow extends StatelessWidget {
  const StudyDurationRow({
    super.key,
    required this.label,
    required this.seconds,
  });

  final String label;
  final int seconds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              Formatters.formatStudyDuration(seconds, l10n),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
