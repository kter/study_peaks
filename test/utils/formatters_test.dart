import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/utils/formatters.dart';

void main() {
  group('Formatters', () {
    test('formatDuration should format seconds to "Xh Ym"', () {
      expect(Formatters.formatDuration(3600), '1h 0m');
      expect(Formatters.formatDuration(3660), '1h 1m');
      expect(Formatters.formatDuration(3661), '1h 1m'); // Truncates seconds
    });

    test('formatDuration should format seconds to "Ym" if less than an hour', () {
      expect(Formatters.formatDuration(59), '0m');
      expect(Formatters.formatDuration(60), '1m');
      expect(Formatters.formatDuration(3599), '59m');
    });

    test('formatDuration should handle 0', () {
      expect(Formatters.formatDuration(0), '0m');
    });
  });
}
