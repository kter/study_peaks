import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../models/study_session.dart';
import '../l10n/app_localizations.dart';
import '../repositories/study_history_repository.dart';
import '../utils/formatters.dart';

class StudyHistoryScreen extends StatefulWidget {
  const StudyHistoryScreen({super.key});

  @override
  State<StudyHistoryScreen> createState() => _StudyHistoryScreenState();
}

class _StudyHistoryScreenState extends State<StudyHistoryScreen> {
  final StudyHistoryRepository _repository = StudyHistoryRepository();
  Map<DateTime, int>? _weeklyData;
  int _totalStudyTime = 0;
  bool _isLoading = true;

  String? _owner;
  bool _legacy = false;
  bool _failed = false;
  int _loadVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.watch<AuthProvider>().userId;
    final owner = _legacy
        ? StudySession.legacyOwner
        : uid.isEmpty
            ? StudySession.guestOwner
            : 'user:$uid';
    if (_owner != owner) {
      _owner = owner;
      _weeklyData = null;
      _totalStudyTime = 0;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final version = ++_loadVersion;
    final owner = _owner!;
    setState(() {
      _isLoading = true;
      _failed = false;
    });
    try {
      final weeklyData = await _repository.getDailyStudyTime(ownerId: owner);
      final totalTime = await _repository.getTotalStudyTime(ownerId: owner);

      if (mounted && version == _loadVersion) {
        setState(() {
          _weeklyData = weeklyData;
          _totalStudyTime = totalTime;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted && version == _loadVersion) {
        setState(() {
          _isLoading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.studyHistory),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: TextButton(
                      onPressed: _loadData,
                      child: Text(
                          AppLocalizations.of(context)!.historyLoadFailed)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context)!.historyStorageNotice),
                      TextButton(
                        onPressed: () => setState(() {
                          _legacy = !_legacy;
                          final uid = context.read<AuthProvider>().userId;
                          _owner = _legacy
                              ? StudySession.legacyOwner
                              : uid.isEmpty
                                  ? StudySession.guestOwner
                                  : 'user:$uid';
                          _loadData();
                        }),
                        child: Text(_legacy
                            ? AppLocalizations.of(context)!.historyCurrentOwner
                            : AppLocalizations.of(context)!.historyLegacy),
                      ),
                      if (_legacy)
                        Text(AppLocalizations.of(context)!.historyLegacyNotice),
                      _buildTotalSummary(),
                      const SizedBox(height: 24),
                      Text(
                        AppLocalizations.of(context)!.historyLastSevenDays,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildWeeklyChart(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildTotalSummary() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.historyTotal,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                Formatters.formatDuration(_totalStudyTime),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart() {
    if (_weeklyData == null || _weeklyData!.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(child: Text(AppLocalizations.of(context)!.historyEmpty)),
      );
    }

    final sortedKeys = _weeklyData!.keys.toList()..sort();
    final today = DateTime.now();

    // Find max value for y-axis normalization (minimum 1 hour = 3600s)
    int maxSeconds = 3600;
    for (final seconds in _weeklyData!.values) {
      if (seconds > maxSeconds) maxSeconds = seconds;
    }

    return AspectRatio(
      aspectRatio: 1.5,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxSeconds.toDouble(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final seconds = rod.toY.toInt();
                final duration = Formatters.formatDuration(seconds);
                // Format date: MM/DD
                final date = sortedKeys[groupIndex];
                final dateStr = '${date.month}/${date.day}';
                return BarTooltipItem(
                  '$dateStr\n$duration',
                  const TextStyle(color: Colors.white),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < sortedKeys.length) {
                    final date = sortedKeys[index];
                    // Show day name (Mon, Tue)
                    final label = DateFormat.E(
                            Localizations.localeOf(context).toLanguageTag())
                        .format(date);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  // Show hours
                  if (value == 0) return const Text('');
                  final hours = value ~/ 3600;
                  return Text('${hours}h',
                      style: const TextStyle(fontSize: 10));
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(sortedKeys.length, (index) {
            final date = sortedKeys[index];
            final seconds = _weeklyData![date] ?? 0;
            final isToday = date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;

            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: seconds.toDouble(),
                  color: isToday
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .secondary
                          .withOpacity(0.5),
                  width: 16,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
