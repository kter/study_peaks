import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/models.dart';
import 'package:study_peaks/widgets/dialogs/user_info_dialog.dart';

void main() {
  testWidgets(
      'user info sheet limits long names and keeps elapsed time visible',
      (tester) async {
    final longName = 'Long name ' * 500;
    final seat = Seat(
      seatId: 'seat-001',
      seatNumber: 1,
      isOccupied: true,
      user: SeatUser(
          userId: 'test-user', displayName: longName, countryCode: 'JP'),
    );
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showUserInfoDialog(context: context, seat: seat),
            child: const Text('Show user info'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Show user info'));
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(longName));
    expect(title.maxLines, 2);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(find.byIcon(Icons.timer).hitTestable(), findsOneWidget);
  });
}
