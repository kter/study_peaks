import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/weekly_study_goals.dart';

class WeeklyStudyGoalDialog extends StatefulWidget {
  const WeeklyStudyGoalDialog({super.key, required this.goalMinutes});

  final int? goalMinutes;

  @override
  State<WeeklyStudyGoalDialog> createState() => _WeeklyStudyGoalDialogState();
}

class _WeeklyStudyGoalDialogState extends State<WeeklyStudyGoalDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _minutes =
      TextEditingController(text: widget.goalMinutes?.toString());

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, (minutes: int.parse(_minutes.text.trim())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.goalMinutes == null ? l10n.weeklyGoalSet : l10n.weeklyGoalEdit,
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _minutes,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.weeklyGoalMinutes,
            helperText: l10n.weeklyGoalInputHelp(
              WeeklyStudyGoals.minMinutes,
              WeeklyStudyGoals.maxMinutes,
              WeeklyStudyGoals.stepMinutes,
            ),
            helperMaxLines: 3,
            errorMaxLines: 3,
          ),
          validator: (value) {
            final minutes = int.tryParse(value?.trim() ?? '', radix: 10);
            return minutes != null && WeeklyStudyGoals.isValidMinutes(minutes)
                ? null
                : l10n.weeklyGoalInvalidMinutes;
          },
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        if (widget.goalMinutes != null)
          TextButton(
            onPressed: () => Navigator.pop(context, (minutes: null)),
            child: Text(l10n.weeklyGoalClear),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.weeklyGoalSave)),
      ],
    );
  }
}
