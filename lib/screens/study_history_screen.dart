import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final weeklyData = await _repository.getDailyStudyTime();
      final totalTime = await _repository.getTotalStudyTime();
      
      if (mounted) {
        setState(() {
          _weeklyData = weeklyData;
          _totalStudyTime = totalTime;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study History'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   _buildTotalSummary(),
                   const SizedBox(height: 24),
                   const Text(
                     'Last 7 Days',
                     style: TextStyle(
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
                'Total Study Time',
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
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No data available')),
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
                    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        days[date.weekday - 1],
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
                  return Text('${hours}h', style: const TextStyle(fontSize: 10));
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                      : Theme.of(context).colorScheme.secondary.withOpacity(0.5),
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
