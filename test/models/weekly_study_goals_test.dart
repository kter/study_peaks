import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/models/weekly_study_goals.dart';

void main() {
  test('6 hours 30 minutes toward a 10-hour goal gives 65% progress', () {
    const progress = WeeklyGoalProgress(600, 23400);
    expect(progress.hasGoal, isTrue);
    expect(progress.targetSeconds, 36000);
    expect(progress.percent, 65);
    expect(progress.remainingSeconds, 12600);
    expect(progress.fraction, 0.65);
    expect(const WeeklyGoalProgress(600, 23401).percent, 65);
  });

  test('progress over the goal caps the bar and floors remaining time', () {
    const progress = WeeklyGoalProgress(300, 23400);
    expect(progress.percent, 130);
    expect(progress.remainingSeconds, 0);
    expect(progress.fraction, 1.0);
  });

  test('progress guards zero and unset goals', () {
    for (final minutes in [0, null]) {
      final progress = WeeklyGoalProgress(minutes, 23400);
      expect(progress.hasGoal, isFalse);
      expect(progress.targetSeconds, 0);
      expect(progress.percent, 0);
      expect(progress.remainingSeconds, 0);
      expect(progress.fraction, 0.0);
    }
  });
}
