import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/study_history.dart';
import '../models/study_session.dart';
import '../providers/auth_provider.dart';
import '../repositories/study_history_repository.dart';
import '../utils/formatters.dart';
import '../widgets/study_history_chart.dart';

class StudyHistoryScreen extends StatefulWidget {
  const StudyHistoryScreen({super.key, this.repository, this.now});

  final StudyHistoryRepository? repository;
  final DateTime Function()? now;

  @override
  State<StudyHistoryScreen> createState() => _StudyHistoryScreenState();
}

class _StudyHistoryScreenState extends State<StudyHistoryScreen> {
  StudyHistoryPeriod _period = StudyHistoryPeriod.week;
  DateTime? _pastDate;
  bool _legacy = false;
  String? _owner;
  late Future<StudyHistory?> _history;
  late DateTime _today;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _today = _currentDate;
    _lifecycle = AppLifecycleListener(onResume: _refreshDate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setOwner(context.watch<AuthProvider>().userId);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _setOwner(String uid) {
    final owner =
        _legacy ? StudySession.legacyOwner : StudySession.ownerFor(uid);
    if (owner != _owner) {
      _owner = owner;
      _history = _fetchHistory(owner);
    }
  }

  Future<StudyHistory?> _fetchHistory(String owner) async {
    try {
      return await (widget.repository ?? StudyHistoryRepository())
          .getHistory(ownerId: owner);
    } catch (error, stack) {
      debugPrint('Could not load study history: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
      return null;
    }
  }

  DateTime get _currentDate => civilDate(widget.now?.call() ?? DateTime.now());

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

  void _toggleOwner() {
    final uid = context.read<AuthProvider>().userId;
    setState(() {
      _legacy = !_legacy;
      _setOwner(uid);
    });
  }

  void _showPeriod(StudyHistoryPeriod period, DateTime date) {
    setState(() {
      _today = _currentDate;
      _period = period;
      _pastDate =
          period.start(date).isBefore(period.start(_today)) ? date : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final today = _today;
    final anchor = _pastDate ?? today;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.studyHistory)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.historyStorageNotice),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _toggleOwner,
                child: Text(
                    _legacy ? l10n.historyCurrentOwner : l10n.historyLegacy),
              ),
            ),
            if (_legacy) Text(l10n.historyLegacyNotice),
            FutureBuilder<StudyHistory?>(
              future: _history,
              builder: (context, snapshot) {
                final loaded = snapshot.connectionState == ConnectionState.done;
                final history = loaded ? snapshot.data : null;
                final days = history?.daysIn(_period, anchor);
                return Column(
                  children: [
                    if (history != null) _buildSummary(history, today, l10n),
                    const SizedBox(height: 16),
                    _buildPeriodControls(l10n, anchor, today),
                    if (!loaded)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      )
                    else if (history == null || days == null)
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
                    else ...[
                      if (!history.hasRecords)
                        Text(l10n.historyEmpty)
                      else if (days.values.every((seconds) => seconds == 0))
                        Text(l10n.historyPeriodEmpty),
                      StudyHistoryChart(
                        key:
                            ValueKey((_owner, days.keys.first, _period, today)),
                        days: days,
                        today: today,
                        period: _period,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(
      StudyHistory history, DateTime today, AppLocalizations l10n) {
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(label)),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        Formatters.formatStudyDuration(seconds, l10n),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodControls(
      AppLocalizations l10n, DateTime anchor, DateTime today) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dateFormat = DateFormat.yMMMd(locale);
    final title = switch (_period) {
      StudyHistoryPeriod.week => l10n.historyDateRange(
          dateFormat.format(_period.start(anchor)),
          dateFormat.format(
              _period.shift(anchor, 1).subtract(const Duration(days: 1))),
        ),
      StudyHistoryPeriod.month =>
        DateFormat.yMMMM(locale).format(_period.start(anchor)),
    };
    final nextPeriod = _period.shift(anchor, 1);

    return Column(
      children: [
        SegmentedButton<StudyHistoryPeriod>(
          segments: [
            ButtonSegment(
                value: StudyHistoryPeriod.week, label: Text(l10n.historyWeek)),
            ButtonSegment(
                value: StudyHistoryPeriod.month,
                label: Text(l10n.historyMonth)),
          ],
          selected: {_period},
          onSelectionChanged: (selection) =>
              _showPeriod(selection.single, anchor),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              tooltip: l10n.historyPreviousPeriod,
              onPressed: () => _showPeriod(_period, _period.shift(anchor, -1)),
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
              onPressed: nextPeriod.isAfter(today)
                  ? null
                  : () => _showPeriod(_period, nextPeriod),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
