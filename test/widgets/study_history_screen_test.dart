import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/study_history.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';
import 'package:study_peaks/screens/study_history_screen.dart';

class _Auth extends ChangeNotifier implements AuthProvider {
  @override
  String userId = '';

  void changeUser(String uid) {
    userId = uid;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _History extends Mock implements StudyHistoryRepository {}

StudyHistory _history([Map<DateTime, int> records = const {}]) {
  return StudyHistory([
    for (final entry in records.entries)
      StudySession(
        roomId: 'fuji',
        startTime: entry.key,
        durationSeconds: entry.value,
      ),
  ]);
}

void main() {
  late _Auth auth;
  late _History repository;
  late DateTime today;

  setUp(() {
    auth = _Auth();
    repository = _History();
    today = DateTime(2027, 1, 1);
  });

  tearDown(() => auth.dispose());

  When<Future<StudyHistory>> query() =>
      when(() => repository.getHistory(ownerId: any(named: 'ownerId')));

  Future<void> show(WidgetTester tester,
      {String language = 'en', Brightness brightness = Brightness.light}) {
    return tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: brightness, useMaterial3: true),
          home: StudyHistoryScreen(repository: repository, now: () => today),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('calendar periods, exact short values and zero days',
      (tester) async {
    query().thenAnswer((_) async => _history({
          DateTime.utc(2026, 12, 31): 60,
          DateTime.utc(2027, 1, 1): 12,
        }));

    await show(tester);
    await tester.pumpAndSettle();

    expect(find.text('Dec 28, 2026 – Jan 3, 2027'), findsOneWidget);
    expect(find.text('12s'), findsNWidgets(2));
    expect(find.text('1m 12s'), findsNWidgets(2));
    final chart = find.byType(BarChart);
    expect(tester.widget<BarChart>(chart).data.barGroups, hasLength(7));
    expect(tester.widget<BarChart>(chart).data.maxY, 60);

    await tap(tester, find.byTooltip('Next day'));
    expect(find.text('Sat, Jan 2, 2027'), findsOneWidget);
    expect(find.text('0s'), findsNWidgets(2));
    await tap(tester, find.byTooltip('Previous period'));
    expect(find.text('Dec 21, 2026 – Dec 27, 2026'), findsOneWidget);
    expect(find.text('No study time in this period'), findsOneWidget);
    await tap(tester, find.byTooltip('Next period'));

    await tap(tester, find.text('Month'));
    expect(find.text('January 2027'), findsOneWidget);
    await tap(tester, find.byTooltip('Previous period'));
    expect(find.text('December 2026'), findsOneWidget);
    expect(tester.widget<BarChart>(chart).data.barGroups, hasLength(31));
    expect(
        tester.widget<BarChart>(chart).data.barGroups.last.barRods.single.toY,
        60);
    expect(find.text('1m 12s'), findsNWidgets(2));
    await tap(tester, find.byTooltip('Next period'));
    final nextPeriod = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Next period');
    expect(tester.widget<IconButton>(nextPeriod).onPressed, isNull);
  });

  testWidgets('loading and failure never show zero totals; retry shows empty',
      (tester) async {
    final load = Completer<StudyHistory>();
    query().thenAnswer((_) => load.future);

    await show(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    load.completeError(StateError('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load history'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
    expect(find.byType(BarChart), findsNothing);

    query().thenAnswer((_) => Future.error(StateError('still unavailable')));
    await tap(tester, find.text('Retry'));
    expect(find.text('Could not load history'), findsOneWidget);
    expect(find.text('Today'), findsNothing);

    query().thenAnswer((_) async => _history());
    await tap(tester, find.text('Retry'));
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('No study records yet'), findsOneWidget);
    expect(
        tester
            .widget<BarChart>(find.byType(BarChart))
            .data
            .barGroups
            .every((group) => group.barRods.single.toY == 0),
        isTrue);
  });

  testWidgets('a late owner response cannot replace current or older history',
      (tester) async {
    final guestQuery = Completer<StudyHistory>();
    query().thenAnswer((call) async {
      final owner = call.namedArguments[#ownerId];
      if (owner == StudySession.guestOwner) return guestQuery.future;
      return _history({
        DateTime.utc(2027, 1, 1): owner == StudySession.legacyOwner ? 26 : 11,
      });
    });

    await show(tester);
    auth.changeUser('account');
    await tester.pumpAndSettle();
    expect(find.text('11s'), findsWidgets);

    guestQuery.complete(_history({DateTime.utc(2027, 1, 1): 35}));
    await tester.pumpAndSettle();
    expect(find.text('35s'), findsNothing);
    expect(find.text('11s'), findsWidgets);

    await tap(tester, find.text('View older history with unknown owner'));
    expect(find.text('26s'), findsWidgets);
    expect(find.text('11s'), findsNothing);
    await tap(tester, find.text('Back to current user history'));
    expect(find.text('11s'), findsWidgets);
    expect(find.text('26s'), findsNothing);
  });

  testWidgets('resume preserves the selection and advances the calendar date',
      (tester) async {
    query().thenAnswer((_) async => _history({
          DateTime.utc(2027, 1, 1): 12,
          DateTime.utc(2027, 1, 4): 23,
        }));
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Dec 28, 2026 – Jan 3, 2027'), findsOneWidget);

    await tap(tester, find.byTooltip('Previous day'));
    expect(find.text('Thu, Dec 31, 2026'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Thu, Dec 31, 2026'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    today = DateTime(2027, 1, 4);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Jan 4, 2027 – Jan 10, 2027'), findsOneWidget);
    expect(find.text('23s'), findsNWidgets(3));
    verify(() => repository.getHistory(ownerId: StudySession.guestOwner))
        .called(1);
  });

  testWidgets('small Japanese dark layout shows long and short units',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    query().thenAnswer((_) async => _history({
          DateTime.utc(2027, 1, 1): 3600021,
          DateTime.utc(2027, 1, 2): 1,
        }));

    await show(tester, language: 'ja', brightness: Brightness.dark);
    await tester.pumpAndSettle();
    expect(find.text('学習履歴'), findsOneWidget);
    expect(find.text('1000時間0分21秒'), findsWidgets);
    await tap(
      tester,
      find.descendant(
        of: find.byType(SegmentedButton<StudyHistoryPeriod>),
        matching: find.text('月'),
      ),
    );
    await tap(tester, find.byTooltip('次の日'));
    expect(find.text('1秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
