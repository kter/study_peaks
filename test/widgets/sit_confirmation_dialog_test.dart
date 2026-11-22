import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/seat.dart';
import 'package:study_peaks/widgets/dialogs/sit_confirmation_dialog.dart';

void main() {
  Future<void> showDialogTestApp(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale('en'),
      home: Scaffold(),
    ));
  }

  testWidgets('without screen pinning the existing sit button returns sit',
      (tester) async {
    await showDialogTestApp(tester);
    final result = showSitConfirmationDialog(
      context: tester.element(find.byType(Scaffold)),
      seat: Seat.empty(1),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).actions,
        hasLength(2));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sit Down'));
    await tester.pumpAndSettle();
    expect(await result, SitConfirmationResult.sit);
  });

  for (final choice in [
    SitConfirmationResult.sit,
    SitConfirmationResult.sitAndPin,
  ]) {
    testWidgets('with screen pinning the dialog can return ${choice.name}',
        (tester) async {
      await showDialogTestApp(tester);
      final result = showSitConfirmationDialog(
        context: tester.element(find.byType(Scaffold)),
        seat: Seat.empty(1),
        offerScreenPin: true,
      );
      await tester.pumpAndSettle();

      final sit = find.widgetWithText(TextButton, 'Sit Down');
      final pin = find.widgetWithText(FilledButton, 'Pin screen & sit');
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).actions,
          hasLength(3));
      expect(sit, findsOneWidget);
      expect(pin, findsOneWidget);
      await tester.tap(choice == SitConfirmationResult.sit ? sit : pin);
      await tester.pumpAndSettle();
      expect(await result, choice);
    });
  }

  testWidgets('dismissing the dialog returns cancel', (tester) async {
    await showDialogTestApp(tester);
    final context = tester.element(find.byType(Scaffold));
    final result =
        showSitConfirmationDialog(context: context, seat: Seat.empty(1));
    await tester.pumpAndSettle();

    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(await result, SitConfirmationResult.cancel);
  });
}
