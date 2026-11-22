import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/study_history.dart';
import '../utils/formatters.dart';

enum _StudyTimeBand {
  none,
  underThirtyMinutes,
  underOneHour,
  oneHourOrMore,
  future;

  factory _StudyTimeBand.fromSeconds(int seconds) => switch (seconds) {
        0 => none,
        < 30 * 60 => underThirtyMinutes,
        < 60 * 60 => underOneHour,
        _ => oneHourOrMore,
      };

  Color fill(ColorScheme colors) => switch (this) {
        none => colors.surfaceContainerHighest,
        underThirtyMinutes => Color.lerp(colors.surface, colors.primary, 0.29)!,
        underOneHour => Color.lerp(colors.surface, colors.primary, 0.43)!,
        oneHourOrMore => Color.lerp(colors.surface, colors.primary, 0.75)!,
        future => Colors.transparent,
      };

  String label(AppLocalizations l10n) => switch (this) {
        none => l10n.historyCalendarNoStudy,
        underThirtyMinutes => l10n.historyCalendarUnderThirty,
        underOneHour => l10n.historyCalendarUnderSixty,
        oneHourOrMore => l10n.historyCalendarSixtyOrMore,
        future => l10n.historyCalendarFuture,
      };
}

class StudyHistoryCalendar extends StatefulWidget {
  const StudyHistoryCalendar({
    super.key,
    required this.month,
    required this.today,
    required this.history,
  });

  final DateTime month;
  final DateTime today;
  final StudyHistory history;

  @override
  State<StudyHistoryCalendar> createState() => _StudyHistoryCalendarState();
}

class _StudyHistoryCalendarState extends State<StudyHistoryCalendar> {
  static const _minDaySize = 48.0;
  static const _dayPadding = 2.0;
  static const _minGridWidth =
      DateTime.daysPerWeek * (_minDaySize + 2 * _dayPadding);

  final _horizontalScroll = ScrollController();
  final _detailsKey = GlobalKey();
  DateTime? _selection;

  @override
  void dispose() {
    _horizontalScroll.dispose();
    super.dispose();
  }

  bool _canSelect(DateTime day, int seconds) =>
      !day.isAfter(widget.today) || seconds > 0;

  DateTime? _selectedDay(Map<DateTime, int> days) {
    final selection = _selection;
    if (selection != null &&
        days.containsKey(selection) &&
        _canSelect(selection, days[selection]!)) {
      return selection;
    }
    if (days.containsKey(widget.today)) return widget.today;
    for (final entry in days.entries) {
      if (entry.value > 0) return entry.key;
    }
    final first = days.keys.first;
    return _canSelect(first, days[first]!) ? first : null;
  }

  void _select(DateTime day) {
    setState(() => _selection = day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final details = _detailsKey.currentContext;
      if (details == null) return;
      Scrollable.ensureVisible(
        details,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 180),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final fullDate = DateFormat.yMMMMEEEEd(locale);
    final days = widget.history.daysIn(StudyHistoryPeriod.month, widget.month);
    final selected = _selectedDay(days);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.historyStudyDays(widget.history.studyDaysIn(widget.month)),
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _buildGrid(days, selected, l10n, fullDate, locale),
        const SizedBox(height: 12),
        Text(l10n.historyCalendarLegend, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final band in _StudyTimeBand.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: band.fill(theme.colorScheme),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(band.label(l10n), style: theme.textTheme.labelSmall),
                ],
              ),
          ],
        ),
        if (selected != null) ...[
          const Divider(height: 32),
          _buildDayDetails(selected, days[selected]!, l10n, fullDate, locale),
        ],
      ],
    );
  }

  Widget _buildGrid(
    Map<DateTime, int> days,
    DateTime? selected,
    AppLocalizations l10n,
    DateFormat fullDate,
    String locale,
  ) {
    final weekday = DateFormat.E(locale);
    final dayNumber = NumberFormat.decimalPattern(locale);
    final first = days.keys.first;
    final leading = first.weekday - DateTime.monday;
    final monday = first.subtract(Duration(days: leading));
    final trailing =
        (DateTime.daysPerWeek - days.keys.last.weekday) % DateTime.daysPerWeek;
    final cells = [
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (final MapEntry(key: day, value: seconds) in days.entries)
        _buildDay(day, seconds, day == selected, l10n, dayNumber, fullDate),
      for (var i = 0; i < trailing; i++) const SizedBox.shrink(),
    ];
    final grid = Table(
      children: [
        TableRow(
          children: [
            for (var i = 0; i < DateTime.daysPerWeek; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    weekday.format(monday.add(Duration(days: i))),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
        for (var i = 0; i < cells.length; i += DateTime.daysPerWeek)
          TableRow(children: cells.sublist(i, i + DateTime.daysPerWeek)),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _minGridWidth) return grid;
        return Scrollbar(
          controller: _horizontalScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(width: _minGridWidth, child: grid),
          ),
        );
      },
    );
  }

  Widget _buildDay(
    DateTime day,
    int seconds,
    bool isSelected,
    AppLocalizations l10n,
    NumberFormat dayNumber,
    DateFormat fullDate,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selectable = _canSelect(day, seconds);
    final isToday = day == widget.today;
    final band = selectable
        ? _StudyTimeBand.fromSeconds(seconds)
        : _StudyTimeBand.future;
    final fill = band.fill(colors);
    // Choose the higher-contrast foreground for each point on the color scale.
    final foreground = selectable
        ? (fill.computeLuminance() > 0.179 ? Colors.black : Colors.white)
        : colors.onSurfaceVariant;
    final dateLabel = fullDate.format(day);
    final label = l10n.historyCalendarDayLabel(
      isToday ? l10n.historyCalendarToday(dateLabel) : dateLabel,
      selectable
          ? Formatters.formatStudyDuration(seconds, l10n)
          : l10n.historyCalendarFuture,
    );

    return Padding(
      padding: const EdgeInsets.all(_dayPadding),
      child: Semantics(
        button: true,
        enabled: selectable,
        selected: isSelected,
        label: label,
        child: Material(
          color: fill,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isSelected
                ? BorderSide(color: foreground, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: selectable ? () => _select(day) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _minDaySize),
              child: Center(
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            dayNumber.format(day.day),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foreground,
                              fontWeight: isSelected ? FontWeight.bold : null,
                              decoration:
                                  isToday ? TextDecoration.underline : null,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 4,
                          height: 4,
                          child: seconds > 0
                              ? DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: foreground,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayDetails(
    DateTime day,
    int seconds,
    AppLocalizations l10n,
    DateFormat fullDate,
    String locale,
  ) {
    final theme = Theme.of(context);
    final sessions = widget.history.sessionsOn(day);
    final startFormat = DateFormat.yMMMd(locale).add_jm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fullDate.format(day), style: theme.textTheme.titleMedium),
              Text(
                l10n.historyDayTotal(
                  Formatters.formatStudyDuration(seconds, l10n),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(l10n.historyDaySessions, style: theme.textTheme.titleSmall),
        if (sessions.isEmpty) Text(l10n.historyDayEmpty, key: _detailsKey),
        for (final (index, session) in sessions.indexed)
          Padding(
            key: index == 0 ? _detailsKey : null,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  l10n.historySessionStart(
                    startFormat.format(session.displayStartTime.toLocal()),
                  ),
                ),
                Text(
                  Formatters.formatStudyDuration(session.seconds, l10n),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
