import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/study_history.dart';
import '../../models/study_session.dart';
import '../../providers/auth_provider.dart';
import '../../utils/formatters.dart';
import '../study_duration_row.dart';

class LeaveSummaryDialog extends StatefulWidget {
  const LeaveSummaryDialog({
    super.key,
    required this.record,
    required this.loadHistory,
    this.warning,
    this.now,
  });

  final StudySession record;
  final String? warning;
  final Future<StudyHistory> Function() loadHistory;
  final DateTime Function()? now;

  @override
  State<LeaveSummaryDialog> createState() => _LeaveSummaryDialogState();
}

class _LeaveSummaryDialogState extends State<LeaveSummaryDialog> {
  late final _history = widget.loadHistory();
  late final _sessionHistory = StudyHistory([widget.record]);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentOwner = context.select<AuthProvider, String>(
      (auth) => auth.historyOwnerId,
    );
    final record = widget.record;
    final canOpenHistory = record.isVisibleTo(currentOwner);
    final savedToGuestHistory =
        record.ownerId == StudySession.guestOwner && !canOpenHistory;
    final canShowRecord = canOpenHistory || savedToGuestHistory;
    final warning = widget.warning;
    return AlertDialog(
      title: Text(canShowRecord ? l10n.leaveSummaryTitle : l10n.leftSeat),
      scrollable: true,
      content: canShowRecord
          ? FutureBuilder<StudyHistory>(
              future: _history,
              builder: (context, snapshot) {
                final today = widget.now?.call() ?? DateTime.now();
                final totals = snapshot.data;
                final thisSessionToday = _sessionHistory.secondsOn(today);
                final thisSessionWeek =
                    _sessionHistory.secondsIn(StudyHistoryPeriod.week, today);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (warning != null) Text(warning),
                    if (savedToGuestHistory) Text(l10n.leaveSummarySavedToGuest),
                    StudyDurationRow(
                      label: l10n.leaveSummarySession,
                      seconds: record.durationSeconds,
                    ),
                    if (totals != null) ...[
                      StudyDurationRow(
                        label: l10n.historyToday,
                        seconds: totals.secondsOn(today),
                      ),
                      StudyDurationRow(
                        label: l10n.historyThisWeek,
                        seconds:
                            totals.secondsIn(StudyHistoryPeriod.week, today),
                      ),
                      if (thisSessionToday != record.durationSeconds ||
                          thisSessionWeek != record.durationSeconds)
                        Text(l10n.leaveSummaryAllocation(
                          Formatters.formatStudyDuration(
                              thisSessionToday, l10n),
                          Formatters.formatStudyDuration(thisSessionWeek, l10n),
                        )),
                    ] else if (snapshot.hasError)
                      Text(l10n.leaveSummaryTotalsUnavailable)
                    else
                      const Center(child: CircularProgressIndicator()),
                  ],
                );
              },
            )
          : warning == null
              ? null
              : Text(warning),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
        if (canOpenHistory)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.studyHistory),
          ),
      ],
    );
  }
}
