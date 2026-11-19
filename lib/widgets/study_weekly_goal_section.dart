import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/study_history.dart';
import '../models/weekly_study_goals.dart';
import '../providers/auth_provider.dart';
import '../repositories/study_history_repository.dart';
import '../utils/formatters.dart';
import 'dialogs/weekly_study_goal_dialog.dart';

class StudyWeeklyGoalSection extends StatefulWidget {
  const StudyWeeklyGoalSection({
    super.key,
    required this.repository,
    required this.ownerId,
    required this.history,
    required this.currentWeek,
    required this.selectedWeek,
    required this.now,
  });

  final StudyHistoryRepository repository;
  final String ownerId;
  final StudyHistory history;
  final DateTime currentWeek;
  final DateTime? selectedWeek;
  final DateTime Function() now;

  @override
  State<StudyWeeklyGoalSection> createState() => _StudyWeeklyGoalSectionState();
}

class _StudyWeeklyGoalSectionState extends State<StudyWeeklyGoalSection> {
  Future<WeeklyStudyGoals?>? _goals;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _goals = _loadVisibleGoals();
  }

  @override
  void didUpdateWidget(StudyWeeklyGoalSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_goals == null ||
        oldWidget.currentWeek != widget.currentWeek ||
        oldWidget.repository != widget.repository) {
      _goals = _loadVisibleGoals();
    }
  }

  Future<WeeklyStudyGoals?>? _loadVisibleGoals() =>
      widget.selectedWeek == null ? null : _loadGoals();

  Future<WeeklyStudyGoals?> _loadGoals() async {
    try {
      return await widget.repository.observeWeeklyGoals(
        ownerId: widget.ownerId,
        today: widget.currentWeek,
      );
    } catch (error, stack) {
      debugPrint('Could not load weekly study goals: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      return null;
    }
  }

  Future<void> _editGoal(DateTime week, int? minutes) async {
    final owner = widget.ownerId;
    final result = await showDialog<({int? minutes})>(
      context: context,
      builder: (dialogContext) {
        final currentOwner = dialogContext.select<AuthProvider, String>(
          (auth) => auth.historyOwnerId,
        );
        if (currentOwner == owner) {
          return WeeklyStudyGoalDialog(goalMinutes: minutes);
        }
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          content: Text(l10n.weeklyGoalOwnerChanged),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    await _changeGoal(
      owner,
      week,
      (today) => widget.repository.saveWeeklyGoal(
        ownerId: owner,
        today: today,
        minutes: result.minutes,
      ),
    );
  }

  Future<void> _correctDate(DateTime week, DateTime latest) async {
    final owner = widget.ownerId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.weeklyGoalCorrectDate),
          content: Text(l10n.weeklyGoalCorrectDateConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.weeklyGoalCorrectDate),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _changeGoal(
      owner,
      week,
      (today) => widget.repository.correctWeeklyGoalDate(
        ownerId: owner,
        today: today,
        expectedLatestWeek: latest,
      ),
    );
  }

  Future<void> _changeGoal(
    String owner,
    DateTime week,
    Future<bool> Function(DateTime today) save,
  ) async {
    if (!mounted || !_isCurrentOwner(owner) || _saving) return;
    final today = widget.now();
    if (StudyHistoryPeriod.week.start(today) != week) {
      _showMessage(AppLocalizations.of(context)!.weeklyGoalWeekChanged);
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await save(today);
      if (mounted && _isCurrentOwner(owner)) {
        _refreshGoals();
        if (!saved) {
          _showMessage(AppLocalizations.of(context)!.weeklyGoalDateEarlier);
        }
      }
    } catch (error, stack) {
      debugPrint('Could not save weekly study goal: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      if (mounted && _isCurrentOwner(owner)) {
        _showMessage(AppLocalizations.of(context)!.weeklyGoalSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isCurrentOwner(String owner) =>
      widget.ownerId == owner &&
      context.read<AuthProvider>().historyOwnerId == owner;

  void _refreshGoals() {
    setState(() {
      _goals = _loadVisibleGoals();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final week = widget.selectedWeek;
    return FutureBuilder<WeeklyStudyGoals?>(
      future: _goals,
      builder: (context, snapshot) {
        if (week == null) return const SizedBox.shrink();
        final loaded = snapshot.connectionState == ConnectionState.done;
        final goals = snapshot.data;
        if (goals == null) {
          if (!loaded) return const LinearProgressIndicator();
          return Column(
            children: [
              Text(l10n.weeklyGoalLoadFailed),
              TextButton(
                onPressed: _refreshGoals,
                child: Text(l10n.retry),
              ),
            ],
          );
        }
        final minutes = goals.minutesInWeek(week);
        final current = week == widget.currentWeek;
        if (!current && minutes == null) return const SizedBox.shrink();
        final latestWeek = goals.latestObservedWeek;
        final dateEarlier =
            latestWeek != null && latestWeek.isAfter(widget.currentWeek);
        final editable = current && !dateEarlier;
        return _WeeklyGoalCard(
          progress: WeeklyGoalProgress(
            minutes,
            widget.history.secondsIn(StudyHistoryPeriod.week, week),
          ),
          editable: editable,
          onEdit: loaded && !_saving ? () => _editGoal(week, minutes) : null,
          notice: current && dateEarlier ? l10n.weeklyGoalDateEarlier : null,
          onCorrectDate: current &&
                  loaded &&
                  !_saving &&
                  latestWeek != null &&
                  WeeklyStudyGoals.canCorrectDate(widget.now(), latestWeek)
              ? () => _correctDate(week, latestWeek)
              : null,
        );
      },
    );
  }
}

class _WeeklyGoalCard extends StatelessWidget {
  const _WeeklyGoalCard({
    required this.progress,
    required this.editable,
    required this.onEdit,
    required this.notice,
    required this.onCorrectDate,
  });

  final WeeklyGoalProgress progress;
  final bool editable;
  final VoidCallback? onEdit;
  final String? notice;
  final VoidCallback? onCorrectDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasGoal = progress.hasGoal;

    String duration(int seconds) =>
        Formatters.formatStudyDuration(seconds, l10n);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.weeklyGoal, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (hasGoal) ...[
              Text(l10n.weeklyGoalTarget(duration(progress.targetSeconds))),
              Text(l10n.weeklyGoalActual(duration(progress.actualSeconds))),
              Text(
                l10n.weeklyGoalRemaining(
                  duration(progress.remainingSeconds),
                ),
              ),
              const SizedBox(height: 8),
              _buildProgress(context),
            ] else
              Text(l10n.weeklyGoalNotSet),
            if (notice != null) ...[
              const SizedBox(height: 8),
              Text(notice!),
              if (onCorrectDate != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: onCorrectDate,
                    child: Text(l10n.weeklyGoalCorrectDate),
                  ),
                ),
            ],
            if (editable)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onEdit,
                  child:
                      Text(hasGoal ? l10n.weeklyGoalEdit : l10n.weeklyGoalSet),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final label = l10n.weeklyGoalAchievement(
      NumberFormat.percentPattern(l10n.localeName)
          .format(progress.percent / 100),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: LinearProgressIndicator(value: progress.fraction),
        ),
      ],
    );
  }
}
