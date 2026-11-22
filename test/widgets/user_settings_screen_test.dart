import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/providers/session_provider.dart';
import 'package:study_peaks/providers/user_settings_provider.dart';
import 'package:study_peaks/screens/user_settings_screen.dart';
import 'package:study_peaks/services/network_exception.dart';

import '../helpers/test_helpers.dart';

class _MockAuthProvider extends Mock implements AuthProvider {}

class _MockSessionProvider extends Mock implements SessionProvider {}

Future<_MockAuthProvider> _pumpSettings(
  WidgetTester tester, {
  required bool signedIn,
  ThemeData? theme,
  Locale? locale,
  Map<String, Object>? preferences,
  String? signInError,
  SessionProvider? session,
}) async {
  await setupMockSharedPreferences(preferences);
  final settings = UserSettingsProvider();
  addTearDown(settings.dispose);
  await settings.init();
  final auth = _MockAuthProvider();
  when(() => auth.isSignedIn).thenReturn(signedIn);
  when(() => auth.isLoading).thenReturn(false);
  when(() => auth.email).thenReturn('test@example.com');
  when(() => auth.photoUrl).thenReturn('https://example.com/avatar.png');
  when(() => auth.signInWithGoogle()).thenAnswer((_) async => false);
  when(() => auth.signOut()).thenAnswer((_) async {});
  when(() => auth.error).thenReturn(signInError);
  final idleSession = _MockSessionProvider();
  when(() => idleSession.state).thenReturn(SessionState.idle);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserSettingsProvider>.value(value: settings),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<SessionProvider>.value(value: session ?? idleSession),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      theme: theme,
      home: const UserSettingsScreen(),
    ),
  ));
  return auth;
}

Finder _containerWithPadding(EdgeInsets padding) => find.byWidgetPredicate(
      (widget) => widget is Container && widget.padding == padding,
    );

void main() {
  final record = StudySession(
    roomId: 'fuji',
    startTime: DateTime(2026),
    durationSeconds: 10,
  );

  AppLocalizations localizations(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(UserSettingsScreen)))!;

  Future<void> tapAuthButton(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> tapDialogButton(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, label),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sign-out waits for a confirmed release of a pending leave',
      (tester) async {
    final session = _MockSessionProvider();
    when(() => session.state).thenReturn(SessionState.seated);
    when(() => session.isFinalizing).thenReturn(true);
    final leave = Completer<LeaveResult>();
    when(() => session.leave()).thenAnswer((_) => leave.future);
    final auth = await _pumpSettings(tester, signedIn: true, session: session);
    final l10n = localizations(tester);

    await tapAuthButton(tester, l10n.signOut);
    expect(find.text('Signing out will leave your seat. Continue?'), findsOneWidget);
    await tapDialogButton(tester, l10n.signOut);
    verifyNever(() => auth.signOut());

    leave.complete(LeaveCompleted(record, null, showSummary: false));
    await tester.pumpAndSettle();
    verifyInOrder([() => session.leave(), () => auth.signOut()]);
    expect(find.text(l10n.signedOutSuccessfully), findsOneWidget);
  });

  for (final failure in LeaveServerFailure.values) {
    testWidgets('sign-out stops on a $failure leave error', (tester) async {
      final session = _MockSessionProvider();
      when(() => session.state).thenReturn(SessionState.seated);
      when(() => session.leave()).thenAnswer(
        (_) async => LeaveCompleted(record, failure, showSummary: false),
      );
      final auth = await _pumpSettings(
        tester,
        signedIn: true,
        session: session,
        locale: const Locale('ja'),
      );
      final l10n = localizations(tester);

      await tapAuthButton(tester, l10n.signOut);
      expect(find.text('サインアウトすると離席します。続けますか？'), findsOneWidget);
      await tapDialogButton(tester, l10n.signOut);
      verify(() => session.leave()).called(1);
      verifyNever(() => auth.signOut());
      expect(find.text('離席できませんでした。もう一度お試しください。'), findsOneWidget);
    });
  }

  testWidgets('canceling sign-out keeps the account and seat', (tester) async {
    final session = _MockSessionProvider();
    when(() => session.state).thenReturn(SessionState.seated);
    final auth = await _pumpSettings(tester, signedIn: true, session: session);

    await tapAuthButton(tester, localizations(tester).signOut);
    final dialogContext = tester.element(find.byType(AlertDialog));
    await tapDialogButton(
        tester, MaterialLocalizations.of(dialogContext).cancelButtonLabel);
    verifyNever(() => session.leave());
    verifyNever(() => auth.signOut());
  });

  testWidgets('sign-out without a seat is immediate', (tester) async {
    final auth = await _pumpSettings(tester, signedIn: true);

    await tapAuthButton(tester, localizations(tester).signOut);
    expect(find.byType(AlertDialog), findsNothing);
    verify(() => auth.signOut()).called(1);
  });

  testWidgets('an active guest session requires confirmation before sign-in',
      (tester) async {
    final session = _MockSessionProvider();
    when(() => session.state).thenReturn(SessionState.seated);
    when(() => session.isFinalizing).thenReturn(false);
    when(() => session.sessionOwnerId).thenReturn(StudySession.guestOwner);
    final auth = await _pumpSettings(tester, signedIn: false, session: session);
    final l10n = localizations(tester);

    await tapAuthButton(tester, l10n.signInWithGoogle);
    expect(find.text(l10n.signInGuestSessionConfirmation), findsOneWidget);
    final dialogContext = tester.element(find.byType(AlertDialog));
    await tapDialogButton(
        tester, MaterialLocalizations.of(dialogContext).cancelButtonLabel);
    verifyNever(() => auth.signInWithGoogle());

    await tapAuthButton(tester, l10n.signInWithGoogle);
    await tapDialogButton(tester, l10n.signIn);
    verify(() => auth.signInWithGoogle()).called(1);
    verifyNever(() => session.leave());
  });

  testWidgets('sign-in during an unknown-owner session skips the guest notice',
      (tester) async {
    final session = _MockSessionProvider();
    when(() => session.state).thenReturn(SessionState.seated);
    when(() => session.isFinalizing).thenReturn(false);
    when(() => session.sessionOwnerId).thenReturn(StudySession.legacyOwner);
    final auth = await _pumpSettings(tester, signedIn: false, session: session);

    await tapAuthButton(tester, localizations(tester).signInWithGoogle);
    expect(find.byType(AlertDialog), findsNothing);
    verify(() => auth.signInWithGoogle()).called(1);
  });

  for (final networkError in [false, true]) {
    testWidgets('sign-in failures show localized feedback (network: $networkError)',
        (tester) async {
      const rawError = 'ApiException: internal details';
      await _pumpSettings(
        tester,
        signedIn: false,
        signInError: networkError ? NetworkErrorKey.networkError : rawError,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(UserSettingsScreen)),
      )!;
      final signIn = find.text(l10n.signInWithGoogle);
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      await tester.pumpAndSettle();

      expect(find.text(networkError ? l10n.networkError : l10n.signInFailed), findsOneWidget);
      expect(find.text(rawError), findsNothing);
    });
  }

  testWidgets('guest profile card spans the content width and is centered',
      (tester) async {
    await _pumpSettings(tester, signedIn: false);

    final card = _containerWithPadding(const EdgeInsets.all(24));
    final screen = find.byType(Scaffold);
    final header = find.descendant(of: card, matching: find.text('Anonymous'));
    expect(tester.getSize(card).width, tester.getSize(screen).width - 40);
    expect(tester.getCenter(header).dx, tester.getCenter(screen).dx);
  });

  testWidgets('display name input and profile header limit long names',
      (tester) async {
    final longName = 'Long name ' * 32;
    await _pumpSettings(
      tester,
      signedIn: false,
      preferences: {'user_display_name': longName},
    );

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).maxLength, 30);
    final header = tester.widget<Text>(find.descendant(
      of: _containerWithPadding(const EdgeInsets.all(24)),
      matching: find.text(longName),
    ));
    expect(header.maxLines, 2);
    expect(header.overflow, TextOverflow.ellipsis);

    await tester.enterText(field, 'a' * 40);
    expect(tester.widget<TextField>(field).controller!.text, 'a' * 30);
  });

  testWidgets('signed-in avatar toggle uses the dark theme colors',
      (tester) async {
    const primary = Color(0xFF7986CB);
    await _pumpSettings(
      tester,
      signedIn: true,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(primary: primary),
      ),
      preferences: {'user_use_google_avatar': false},
    );

    final avatarToggle = tester.widget<Container>(
      _containerWithPadding(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
    expect((avatarToggle.decoration! as BoxDecoration).color,
        Colors.grey.shade800);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(UserSettingsScreen)),
    )!;
    expect(
      tester.widget<Text>(find.text(l10n.useAutoGeneratedAvatar)).style?.color,
      primary,
    );
    expect(tester.widget<Icon>(find.byIcon(Icons.auto_awesome)).color, primary);
    expect(
        tester.widget<Switch>(find.byType(Switch)).activeThumbColor, primary);
  });
}
