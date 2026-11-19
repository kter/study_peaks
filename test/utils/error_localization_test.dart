import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/l10n/app_localizations_en.dart';
import 'package:study_peaks/l10n/app_localizations_ja.dart';
import 'package:study_peaks/services/network_exception.dart';
import 'package:study_peaks/utils/error_localization.dart';

void main() {
  test('localizeErrorKey translates the network key using the active locale',
      () {
    for (final l10n in [AppLocalizationsEn(), AppLocalizationsJa()]) {
      expect(
        localizeErrorKey(
          l10n,
          NetworkErrorKey.networkError,
          fallback: l10n.loadRoomsFailed,
        ),
        l10n.networkError,
      );
    }
  });

  test('localizeErrorKey preserves unknown messages or uses the given fallback',
      () {
    final l10n = AppLocalizationsEn();
    const message = 'API request failed';

    expect(localizeErrorKey(l10n, message), message);
    expect(
      localizeErrorKey(l10n, message, fallback: l10n.loadRoomsFailed),
      l10n.loadRoomsFailed,
    );
  });
}
