import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/study_history.dart';
import '../providers/auth_provider.dart';
import '../repositories/study_history_repository.dart';
import '../services/study_history_sync.dart';
import '../widgets/study_duration_row.dart';
import '../widgets/study_history_calendar.dart';
import '../widgets/study_history_chart.dart';
import '../widgets/study_weekly_goal_section.dart';

enum _HistoryView {
  weekGraph(StudyHistoryPeriod.week),
  monthGraph(StudyHistoryPeriod.month),
  calendar(StudyHistoryPeriod.month);

  const _HistoryView(this.period);
  final StudyHistoryPeriod period;
}

class StudyHistoryScreen extends StatefulWidget {
  const StudyHistoryScreen({
    super.key,
    this.now,
  });

  final DateTime Function()? now;

  @override
  State<StudyHistoryScreen> createState() => _StudyHistoryScreenState();
}

class _StudyHistoryScreenState extends State<StudyHistoryScreen> {
  _HistoryView _view = _HistoryView.weekGraph;
  DateTime? _periodDate;
  String? _owner;
  int? _syncRevision;
  late Future<StudyHistory?> _history;
  late DateTime _today;
  late final AppLifecycleListener _lifecycle;
  late final Timer _dateTimer;

  StudyHistoryRepository get _repository =>
      context.read<StudyHistoryRepository>();

  @override
  void initState() {
    super.initState();
    _today = _currentDate;
    _lifecycle = AppLifecycleListener(onResume: _refreshDate);
    _dateTimer =
        Timer.periodic(const Duration(minutes: 1), (_) => _refreshDate());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context.watch<AuthProvider>().historyOwnerId;
    final sync = context.watch<StudyHistorySync?>();
    if (owner != _owner) {
      _owner = owner;
      _history = _fetchHistory(owner);
      if (sync != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _owner == owner &&
              sync.statusFor(owner) != StudyHistorySyncStatus.syncing) {
            sync.requestSync();
          }
        });
      }
    } else if (sync?.revision != _syncRevision) {
      _history = _fetchHistory(owner);
    }
    _syncRevision = sync?.revision;
  }

  @override
  void dispose() {
    _dateTimer.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<StudyHistory?> _fetchHistory(String owner) async {
    try {
      return await _repository.getHistory(ownerId: owner);
    } catch (error, stack) {
      debugPrint('Could not load study history: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      return null;
    }
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  DateTime get _currentDate => civilDate(_now());

  void _refreshDate() {
    final date = _currentDate;
    if (date != _today) setState(() => _today = date);
  }

  void _refresh() {
    final owner = _owner;
    if (owner == null) return;
    final history = _fetchHistory(owner);
    setState(() {
      _history = history;
    });
  }

  void _showPeriod(_HistoryView view, DateTime date) {
    setState(() {
      _today = _currentDate;
      _view = view;
      _periodDate =
          view.period.start(date) == view.period.start(_today) ? null : date;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final today = _today;
    final period = _view.period;
    final sync = context.watch<StudyHistorySync?>();
    final signedIn = sync != null && context.watch<AuthProvider>().isSignedIn;
    final syncStatus = sync?.statusFor(_owner) ?? StudyHistorySyncStatus.idle;
    final syncMessage = switch (syncStatus) {
      StudyHistorySyncStatus.idle => null,
      StudyHistorySyncStatus.syncing => l10n.historySyncing,
      StudyHistorySyncStatus.synced => l10n.historySynced,
      StudyHistorySyncStatus.failed => l10n.historySyncFailed,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.studyHistory),
        actions: [
          if (signedIn)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: l10n.historySyncAction,
              onPressed: syncStatus == StudyHistorySyncStatus.syncing
                  ? null
                  : sync.requestSync,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (signedIn && syncMessage != null) Text(syncMessage),
            FutureBuilder<StudyHistory?>(
              key: ValueKey(_owner),
              future: _history,
              builder: (context, snapshot) {
                final history = snapshot.data;
                final loaded = snapshot.hasData ||
                    snapshot.connectionState == ConnectionState.done;
                final lastNavigableDay =
                    history?.lastNavigableDay(today) ?? today;
                final anchor = StudyHistory.clampAnchor(
                  period,
                  _periodDate ?? today,
                  lastNavigableDay,
                );
                return Column(
                  children: [
                    if (history != null) _buildSummary(history, today, l10n),
                    const SizedBox(height: 16),
                    _buildPeriodControls(l10n, anchor, lastNavigableDay),
                    if (history != null)
                      StudyWeeklyGoalSection(
                        key: ValueKey(_owner),
                        repository: _repository,
                        ownerId: _owner!,
                        history: history,
                        currentWeek: StudyHistoryPeriod.week.start(today),
                        selectedWeek: _view == _HistoryView.weekGraph
                            ? period.start(anchor)
                            : null,
                        now: _now,
                      ),
                    if (!loaded)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      )
                    else if (history == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Text(l10n.historyLoadFailed),
                            TextButton(
                              onPressed: _refresh,
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      )
                    else if (_view == _HistoryView.calendar)
                      StudyHistoryCalendar(
                        key: ValueKey((_owner, period.start(anchor))),
                        month: period.start(anchor),
                        today: today,
                        history: history,
                      )
                    else
                      _buildChart(history, anchor, today, l10n),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(
    StudyHistory history,
    DateTime anchor,
    DateTime today,
    AppLocalizations l10n,
  ) {
    final period = _view.period;
    final days = history.daysIn(period, anchor);
    return Column(
      children: [
        if (!history.hasRecords)
          Text(l10n.historyEmpty)
        else if (history.isPeriodEmpty(period, anchor))
          Text(l10n.historyPeriodEmpty),
        StudyHistoryChart(
          key: ValueKey((_owner, days.keys.first, period, today)),
          days: days,
          today: today,
          period: period,
        ),
      ],
    );
  }

  Widget _buildSummary(
    StudyHistory history,
    DateTime today,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final totals = [
      (l10n.historyToday, history.secondsOn(today)),
      (l10n.historyThisWeek, history.secondsIn(StudyHistoryPeriod.week, today)),
      (l10n.historyTotal, history.totalSeconds),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final (label, seconds) in totals)
              StudyDurationRow(label: label, seconds: seconds),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodControls(
    AppLocalizations l10n,
    DateTime anchor,
    DateTime lastNavigableDay,
  ) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateFormat = DateFormat.yMMMd(locale);
    final period = _view.period;
    final title = switch (period) {
      StudyHistoryPeriod.week => l10n.historyDateRange(
          dateFormat.format(period.start(anchor)),
          dateFormat.format(
            period.shift(anchor, 1).subtract(const Duration(days: 1)),
          ),
        ),
      StudyHistoryPeriod.month => DateFormat.yMMMM(
          locale,
        ).format(period.start(anchor)),
    };
    final nextPeriod = period.shift(anchor, 1);

    return Column(
      children: [
        SegmentedButton<_HistoryView>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          segments: [
            ButtonSegment(
              value: _HistoryView.weekGraph,
              label: Text(l10n.historyWeek, textAlign: TextAlign.center),
            ),
            ButtonSegment(
              value: _HistoryView.monthGraph,
              label: Text(l10n.historyMonth, textAlign: TextAlign.center),
            ),
            ButtonSegment(
              value: _HistoryView.calendar,
              label: Text(l10n.historyCalendar, textAlign: TextAlign.center),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (selection) =>
              _showPeriod(selection.single, anchor),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: l10n.historyPreviousPeriod,
              onPressed: () => _showPeriod(_view, period.shift(anchor, -1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: l10n.historyNextPeriod,
              onPressed: nextPeriod.isAfter(lastNavigableDay)
                  ? null
                  : () => _showPeriod(_view, nextPeriod),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
