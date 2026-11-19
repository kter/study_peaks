import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/study_history.dart';
import '../utils/formatters.dart';

class StudyHistoryChart extends StatefulWidget {
  const StudyHistoryChart({
    super.key,
    required this.days,
    required this.today,
    required this.period,
  });

  final Map<DateTime, int> days;
  final DateTime today;
  final StudyHistoryPeriod period;

  @override
  State<StudyHistoryChart> createState() => _StudyHistoryChartState();
}

class _StudyHistoryChartState extends State<StudyHistoryChart> {
  late DateTime _selected = widget.days.containsKey(widget.today)
      ? widget.today
      : widget.days.keys.first;

  @override
  Widget build(BuildContext context) {
    final dayKeys = widget.days.keys.toList();
    final selectedIndex = dayKeys.indexOf(_selected);
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall!;
    final seconds = widget.days[_selected]!;
    final step = _axisStep(widget.days.values.reduce(math.max));
    final maxSeconds = step * 3;

    String axisLabel(int value) {
      if (step % 3600 == 0) return l10n.historyHours(value ~/ 3600);
      if (step % 60 == 0) return l10n.historyMinutes(value ~/ 60);
      return l10n.historySeconds(value);
    }

    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final tickPainter = TextPainter(
      text: TextSpan(text: axisLabel(maxSeconds), style: labelStyle),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout();
    final axisWidth = tickPainter.width.ceilToDouble() + 8;
    tickPainter.dispose();

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.historyPreviousDay,
              onPressed: selectedIndex == 0
                  ? null
                  : () => _select(dayKeys[selectedIndex - 1]),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  children: [
                    Text(DateFormat.yMMMEd(locale).format(_selected),
                        textAlign: TextAlign.center),
                    Text(
                      Formatters.formatStudyDuration(seconds, l10n),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.historyNextDay,
              onPressed: selectedIndex == dayKeys.length - 1
                  ? null
                  : () => _select(dayKeys[selectedIndex + 1]),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 176 + textScaler.scale(labelStyle.fontSize ?? 12) * 2,
          child: LayoutBuilder(builder: (context, constraints) {
            final slotWidth = math.max(1.0, constraints.maxWidth - axisWidth) /
                dayKeys.length;
            final barWidth = math.min(16.0, slotWidth * 0.65);
            final weekly = widget.period == StudyHistoryPeriod.week;
            final labelInterval = weekly
                ? math.max(1, (textScaler.scale(28) / slotWidth).ceil())
                : math.max(5, (textScaler.scale(20) / slotWidth).ceil());
            final weekdayFormat = DateFormat.E(locale);
            final dayFormat = DateFormat.d(locale);

            return ExcludeSemantics(
              child: BarChart(
                BarChartData(
                  maxY: maxSeconds.toDouble(),
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    handleBuiltInTouches: false,
                    allowTouchBarBackDraw: true,
                    touchExtraThreshold: EdgeInsets.symmetric(
                      horizontal: (slotWidth - barWidth) / 2,
                    ),
                    touchCallback: (event, response) {
                      final spot = response?.spot;
                      if (event is FlTapUpEvent && spot != null) {
                        _select(dayKeys[spot.touchedBarGroupIndex]);
                      }
                    },
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: step.toDouble(),
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: theme.colorScheme.outlineVariant),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: step.toDouble(),
                        reservedSize: axisWidth,
                        getTitlesWidget: (value, meta) => SideTitleWidget(
                          meta: meta,
                          space: 4,
                          child:
                              Text(axisLabel(value.toInt()), style: labelStyle),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: textScaler.scale(18) + 6,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index % labelInterval != 0) {
                            return const SizedBox.shrink();
                          }
                          final format = weekly ? weekdayFormat : dayFormat;
                          return SideTitleWidget(
                            meta: meta,
                            space: 4,
                            child: Text(format.format(dayKeys[index]),
                                style: labelStyle),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var index = 0; index < dayKeys.length; index++)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: widget.days[dayKeys[index]]!.toDouble(),
                            color: index == selectedIndex
                                ? theme.colorScheme.primary
                                : theme.colorScheme.secondary,
                            width: barWidth,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                            backDrawRodData: BackgroundBarChartRodData(
                              show: true,
                              toY: maxSeconds.toDouble(),
                              color: index == selectedIndex
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.12)
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                duration: Duration.zero,
              ),
            );
          }),
        ),
      ],
    );
  }

  void _select(DateTime day) => setState(() => _selected = day);

  // Fit three evenly spaced ticks. Keep their units exact at every scale.
  static int _axisStep(int maxSeconds) {
    if (maxSeconds == 0) return 1200;
    const steps = [
      5,
      10,
      20,
      60,
      120,
      300,
      600,
      1200,
      3600,
      7200,
      14400,
      28800
    ];
    return steps.firstWhere(
      (step) => maxSeconds <= step * 3,
      orElse: () => (maxSeconds / (3600 * 3)).ceil() * 3600,
    );
  }
}
