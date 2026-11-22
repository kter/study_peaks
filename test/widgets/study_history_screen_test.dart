import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:study_peaks/l10n/app_localizations.dart';
import 'package:study_peaks/models/study_history.dart';
import 'package:study_peaks/models/study_session.dart';
import 'package:study_peaks/models/weekly_study_goals.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/repositories/study_history_repository.dart';
import 'package:study_peaks/screens/study_history_screen.dart';
import 'package:study_peaks/widgets/dialogs/leave_summary_dialog.dart';

class _Auth extends ChangeNotifier implements AuthProvider {
  @override
  String userId = '';

  @override
  String get historyOwnerId => StudySession.ownerFor(userId);

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

  setUpAll(() => registerFallbackValue(DateTime.utc(2027)));

  setUp(() {
    auth = _Auth();
    repository = _History();
    today = DateTime(2027, 1, 1);
    when(() => repository.observeWeeklyGoals(
            today: any(named: 'today'), ownerId: any(named: 'ownerId')))
        .thenAnswer((_) async => WeeklyStudyGoals({}));
  });

  tearDown(() => auth.dispose());

  When<Future<StudyHistory>> query() =>
      when(() => repository.getHistory(ownerId: any(named: 'ownerId')));

  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    Brightness brightness = Brightness.light,
  }) {
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          Provider<StudyHistoryRepository>.value(value: repository),
        ],
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: brightness, useMaterial3: true),
          home: StudyHistoryScreen(now: () => today),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> showSummary(
    WidgetTester tester,
    String language,
    StudySession record,
    Future<StudyHistory> Function() loadHistory,
  ) =>
      tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LeaveSummaryDialog(
              record: record,
              loadHistory: loadHistory,
              now: () => today,
            ),
          ),
        ),
      );

  for (final language in ['en', 'ja']) {
    testWidgets('leave summary splits a Sunday-to-Monday record ($language)',
        (tester) async {
      today = DateTime.utc(2027, 1, 4);
      final start = today.subtract(const Duration(seconds: 15));
      final record = StudySession(
        roomId: 'fuji',
        startTime: start,
        durationSeconds: 25,
        intervals: [
          FocusInterval(
            start: start,
            end: today.add(const Duration(seconds: 10)),
            offsetMinutes: 0,
          ),
        ],
      );
      final history = StudyHistory([
        record,
        StudySession(
          roomId: 'fuji',
          startTime: today,
          durationSeconds: 20,
        ),
      ]);
      query().thenAnswer((_) async => history);
      await showSummary(
        tester,
        language,
        record,
        () => repository.getHistory(ownerId: record.ownerId),
      );
      await tester.pumpAndSettle();

      final isJapanese = language == 'ja';
      final sessionDuration = isJapanese ? '25秒' : '25s';
      final aggregateDuration = isJapanese ? '30秒' : '30s';
      expect(find.text(sessionDuration), findsOneWidget);
      expect(find.text(aggregateDuration), findsNWidgets(2));
      expect(
        find.text(
          isJapanese
              ? '今回のうち、今日の合計に10秒、今週の合計に10秒入っています。'
              : 'From this session, 10s counts toward today and 10s toward this week.',
        ),
        findsOneWidget,
      );
      expect(find.text(isJapanese ? '閉じる' : 'Close'), findsOneWidget);
      expect(find.text(isJapanese ? '学習履歴' : 'Study History'), findsOneWidget);

      await show(tester, language: language);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
            of: find.byType(Card), matching: find.text(aggregateDuration)),
        findsNWidgets(2),
      );
    });
  }

  testWidgets('a summary hides an earlier owner’s record after auth changes',
      (tester) async {
    auth.changeUser('original-owner');
    final record = StudySession(
      ownerId: StudySession.ownerFor('original-owner'),
      roomId: 'fuji',
      startTime: today,
      durationSeconds: 20,
    );
    await showSummary(
      tester,
      'en',
      record,
      () async => throw StateError('could not read database'),
    );
    await tester.pumpAndSettle();

    expect(find.text('20s'), findsOneWidget);
    expect(
      find.text('Could not load today’s and this week’s totals.'),
      findsOneWidget,
    );
    auth.changeUser('another-owner');
    await tester.pumpAndSettle();

    expect(find.text('20s'), findsNothing);
    expect(find.text('Study History'), findsNothing);
    expect(find.text('You have left your seat.'), findsOneWidget);
  });

  testWidgets('calendar periods, exact short values and zero days', (
    tester,
  ) async {
    query().thenAnswer(
      (_) async => _history({
        DateTime.utc(2026, 12, 31): 60,
        DateTime.utc(2027, 1, 1): 12,
      }),
    );

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

    await tap(tester, find.text('Month graph'));
    expect(find.text('January 2027'), findsOneWidget);
    await tap(tester, find.byTooltip('Previous period'));
    expect(find.text('December 2026'), findsOneWidget);
    expect(tester.widget<BarChart>(chart).data.barGroups, hasLength(31));
    expect(
      tester.widget<BarChart>(chart).data.barGroups.last.barRods.single.toY,
      60,
    );
    expect(find.text('1m 12s'), findsNWidgets(2));
    await tap(tester, find.byTooltip('Next period'));
    final nextPeriod = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Next period',
    );
    expect(tester.widget<IconButton>(nextPeriod).onPressed, isNull);
  });

  testWidgets(
    'calendar counts distinct days and shows each day’s session share',
    (tester) async {
      final semantics = tester.ensureSemantics();
      today = DateTime(2028, 3, 1);
      final lateFebruary = DateTime.utc(2028, 2, 29, 14, 59, 47);
      query().thenAnswer(
        (_) async => StudyHistory([
          StudySession(
            roomId: 'fuji',
            startTime: lateFebruary,
            durationSeconds: 37,
            intervals: [
              FocusInterval(
                start: lateFebruary,
                end: lateFebruary.add(const Duration(seconds: 37)),
                offsetMinutes: 9 * 60,
              ),
            ],
          ),
          StudySession(
            roomId: 'fuji',
            startTime: DateTime(2028, 2, 29, 12),
            durationSeconds: 8,
          ),
          StudySession(
            roomId: 'fuji',
            startTime: DateTime(2028, 2, 21),
            durationSeconds: 3600,
          ),
        ]),
      );

      await show(tester);
      await tester.pumpAndSettle();
      await tap(tester, find.text('Calendar'));
      expect(find.text('March 2028'), findsOneWidget);
      expect(find.text('1 study day'), findsOneWidget);
      expect(find.text('Total for this day: 24s'), findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel('Thursday, March 2, 2028, Future date'),
            )
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );

      await tap(tester, find.byTooltip('Previous period'));
      expect(find.text('February 2028'), findsOneWidget);
      expect(find.text('2 study days'), findsOneWidget);
      expect(find.text('60+ min'), findsOneWidget);
      await tap(
        tester,
        find.bySemanticsLabel('Tuesday, February 29, 2028, 21s'),
      );
      expect(find.text('Total for this day: 21s'), findsOneWidget);
      expect(find.text('13s'), findsOneWidget);
      expect(find.text('8s'), findsOneWidget);
      expect(find.textContaining('Started '), findsNWidgets(2));
      expect(
        tester
            .getSemantics(
              find.bySemanticsLabel('Tuesday, February 29, 2028, 21s'),
            )
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tap(tester, find.bySemanticsLabel('Monday, February 28, 2028, 0s'));
      expect(find.text('Total for this day: 0s'), findsOneWidget);
      expect(find.text('No study sessions'), findsOneWidget);
      expect(find.text('2 study days'), findsOneWidget);
      await tap(tester, find.text('Month graph'));
      expect(find.text('February 2028'), findsOneWidget);
      final bars =
          tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;
      expect(bars, hasLength(29));
      expect(bars.last.barRods.single.toY, 21);
      semantics.dispose();
      verify(
        () => repository.getHistory(ownerId: StudySession.guestOwner),
      ).called(1);
    },
  );

  testWidgets('calendar keeps recorded future dates visible across year end', (
    tester,
  ) async {
    today = DateTime(2026, 12, 31);
    query().thenAnswer((_) async => _history({DateTime(2027, 2, 1): 90}));

    await show(tester);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Calendar'));
    expect(find.text('December 2026'), findsOneWidget);
    expect(find.text('0 study days'), findsOneWidget);
    expect(find.text('Total for this day: 0s'), findsOneWidget);
    await tap(tester, find.byTooltip('Next period'));
    expect(find.text('January 2027'), findsOneWidget);
    expect(find.text('0 study days'), findsOneWidget);
    expect(find.textContaining('Total for this day'), findsNothing);
    await tap(tester, find.byTooltip('Next period'));
    expect(find.text('February 2027'), findsOneWidget);
    expect(find.text('1 study day'), findsOneWidget);
    expect(find.text('Total for this day: 1m 30s'), findsOneWidget);
    await tap(tester, find.text('Month graph'));
    expect(find.text('February 2027'), findsOneWidget);
    final bars = tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;
    expect(bars.first.barRods.single.toY, 90);
  });

  testWidgets(
    'calendar keeps 48 dp date targets on a narrow large-text screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      today = DateTime(2027, 1, 4);
      query().thenAnswer((_) async => _history({DateTime(2027, 1, 3): 5}));

      await show(tester);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Calendar'), 180);
      await tap(tester, find.text('Calendar'));

      final gridScroll = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      expect(gridScroll, findsOneWidget);
      final sunday = find.bySemanticsLabel('Sunday, January 3, 2027, 5s');
      await Scrollable.ensureVisible(tester.element(sunday));
      await tester.pumpAndSettle();
      final target = tester.getSize(sunday);
      expect(target.width, greaterThanOrEqualTo(48));
      expect(target.height, greaterThanOrEqualTo(48));
      await tap(tester, sunday);
      final dayTotal = find.text('Total for this day: 5s');
      expect(dayTotal, findsOneWidget);
      expect(tester.getBottomLeft(dayTotal).dy, lessThanOrEqualTo(600));
      final firstSession = find.textContaining('Started ');
      expect(tester.getBottomLeft(firstSession).dy, lessThanOrEqualTo(600));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('calendar color bands follow the 30 and 60 minute thresholds', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    today = DateTime(2027, 1, 7);
    query().thenAnswer(
      (_) async => _history({
        DateTime(2027, 1, 2): 1,
        DateTime(2027, 1, 3): 1799,
        DateTime(2027, 1, 4): 1800,
        DateTime(2027, 1, 5): 3599,
        DateTime(2027, 1, 6): 3600,
      }),
    );

    await show(tester, brightness: Brightness.dark);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Calendar'));

    Color? fill(String label) {
      final day = find.bySemanticsLabel(label);
      final material = find.descendant(
        of: day,
        matching: find.byType(Material),
      );
      return tester.widget<Material>(material).color;
    }

    final neutral = fill('Friday, January 1, 2027, 0s');
    final light = fill('Saturday, January 2, 2027, 1s');
    expect(fill('Sunday, January 3, 2027, 29m 59s'), light);
    final medium = fill('Monday, January 4, 2027, 30m');
    expect(fill('Tuesday, January 5, 2027, 59m 59s'), medium);
    final strong = fill('Wednesday, January 6, 2027, 1h 0m 0s');
    expect({neutral, light, medium, strong}, hasLength(4));
    final studyDot = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).shape == BoxShape.circle,
    );
    expect(
      find.descendant(
        of: find.bySemanticsLabel('Saturday, January 2, 2027, 1s'),
        matching: studyDot,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.bySemanticsLabel('Friday, January 1, 2027, 0s'),
        matching: studyDot,
      ),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('loading and failure never show zero totals; retry shows empty', (
    tester,
  ) async {
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
      isTrue,
    );
  });

  testWidgets('empty graphs label the vertical axis in minutes', (tester) async {
    query().thenAnswer((_) async => _history());
    await show(tester);
    await tester.pumpAndSettle();

    void expectMinuteTicks() {
      for (final label in ['0m', '20m', '40m', '60m']) {
        expect(
          find.descendant(of: find.byType(BarChart), matching: find.text(label)),
          findsOneWidget,
        );
      }
    }

    expectMinuteTicks();
    await tap(tester, find.text('Month graph'));
    expectMinuteTicks();
  });

  testWidgets('a late guest response cannot replace account history', (
    tester,
  ) async {
    final guestQuery = Completer<StudyHistory>();
    when(() => repository.getHistory(ownerId: StudySession.guestOwner))
        .thenAnswer((_) => guestQuery.future);
    when(() => repository.getHistory(ownerId: StudySession.ownerFor('account')))
        .thenAnswer((_) async => _history({DateTime.utc(2027, 1, 1): 11}));

    await show(tester);
    auth.changeUser('account');
    await tester.pumpAndSettle();
    await tap(tester, find.text('Calendar'));
    expect(find.text('Total for this day: 11s'), findsOneWidget);

    guestQuery.complete(_history({DateTime.utc(2027, 1, 1): 35}));
    await tester.pumpAndSettle();
    expect(find.text('35s'), findsNothing);
    expect(find.text('11s'), findsWidgets);

    verifyNever(() => repository.getHistory(ownerId: StudySession.legacyOwner));
  });

  testWidgets('resume preserves the selection and advances the calendar date', (
    tester,
  ) async {
    query().thenAnswer(
      (_) async => _history({
        DateTime.utc(2027, 1, 1): 12,
        DateTime.utc(2027, 1, 4): 23,
      }),
    );
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
    verify(
      () => repository.getHistory(ownerId: StudySession.guestOwner),
    ).called(1);
  });

  testWidgets('small Japanese dark layout shows long and short units', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    query().thenAnswer(
      (_) async => _history({
        DateTime.utc(2027, 1, 1): 3600021,
        DateTime.utc(2027, 1, 2): 1,
      }),
    );

    await show(tester, language: 'ja', brightness: Brightness.dark);
    await tester.pumpAndSettle();
    expect(find.text('学習履歴'), findsOneWidget);
    expect(find.text('1000時間0分21秒'), findsWidgets);
    await tap(tester, find.text('月グラフ'));
    await tap(tester, find.byTooltip('次の日'));
    expect(find.text('1秒'), findsOneWidget);
    await tap(tester, find.text('カレンダー'));
    expect(find.text('2027年1月'), findsOneWidget);
    expect(find.text('学習日数 2日'), findsOneWidget);
    expect(find.text('この日の合計 1000時間0分21秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'ja']) {
    testWidgets('goals use the whole week and cap the progress bar ($language)',
        (tester) async {
      final ja = language == 'ja';
      today = DateTime(2027, 1, 7);
      final monday = DateTime.utc(2027, 1, 4);
      query().thenAnswer((_) async => _history({monday: 23400}));
      final changes = <DateTime, int?>{};
      when(() => repository.observeWeeklyGoals(
              today: any(named: 'today'), ownerId: StudySession.guestOwner))
          .thenAnswer((_) async => WeeklyStudyGoals(Map.of(changes)));
      when(() => repository.saveWeeklyGoal(
            ownerId: StudySession.guestOwner,
            today: today,
            minutes: any(named: 'minutes'),
          )).thenAnswer((call) async {
        changes[monday] = call.namedArguments[#minutes] as int?;
        return true;
      });

      await show(tester, language: language);
      await tester.pumpAndSettle();
      expect(find.text(ja ? '目標は未設定です' : 'No goal set'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      final field = find.byType(TextFormField);
      final save = find.text(ja ? '目標を保存' : 'Save goal');
      await tap(tester, find.text(ja ? '目標を設定' : 'Set goal'));
      await tester.enterText(field, '16');
      await tap(tester, save);
      expect(field, findsOneWidget);
      await tester.enterText(field, '600');
      await tap(tester, save);

      expect(
          find.text(ja ? '目標 10時間0分0秒' : 'Target: 10h 0m 0s'), findsOneWidget);
      expect(
          find.text(ja ? '実績 6時間30分0秒' : 'Studied: 6h 30m 0s'), findsOneWidget);
      expect(find.text(ja ? '残り 3時間30分0秒' : 'Remaining: 3h 30m 0s'),
          findsOneWidget);
      expect(find.text(ja ? '達成率 65%' : 'Progress: 65%'), findsOneWidget);
      expect(
        find.textContaining(ja ? '保存できませんでした' : 'Could not save'),
        findsNothing,
      );
      final bar = find.byType(LinearProgressIndicator);
      expect(tester.widget<LinearProgressIndicator>(bar).value, 0.65);

      final edit = find.text(ja ? '目標を変更' : 'Edit goal');
      await tap(tester, edit);
      expect(tester.widget<TextFormField>(field).controller!.text, '600');
      await tester.enterText(field, '300');
      await tap(tester, save);
      expect(find.text(ja ? '達成率 130%' : 'Progress: 130%'), findsOneWidget);
      expect(find.text(ja ? '残り 0秒' : 'Remaining: 0s'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(bar).value, 1.0);

      await tap(tester, edit);
      await tap(tester, find.text(ja ? '目標を解除' : 'Clear goal'));
      expect(find.text(ja ? '目標は未設定です' : 'No goal set'), findsOneWidget);
      expect(bar, findsNothing);
      await tap(tester, find.text(ja ? 'カレンダー' : 'Calendar'));
      expect(find.text(ja ? '学習日数 1日' : '1 study day'), findsOneWidget);
    });
  }

  testWidgets('observes the current week only when the week graph is shown',
      (tester) async {
    today = DateTime(2027, 1, 3);
    final load = Completer<StudyHistory>();
    query().thenAnswer((_) => load.future);
    final firstWeek = DateTime.utc(2026, 12, 28);
    final nextWeek = DateTime.utc(2027, 1, 4);
    when(() => repository.observeWeeklyGoals(
          ownerId: StudySession.guestOwner,
          today: any(named: 'today'),
        )).thenAnswer((_) async => WeeklyStudyGoals({firstWeek: 600}));

    await show(tester);
    await tester.tap(find.text('Month graph'));
    await tester.pump();
    load.complete(_history());
    await tester.pumpAndSettle();
    verifyNever(() => repository.observeWeeklyGoals(
          ownerId: any(named: 'ownerId'),
          today: any(named: 'today'),
        ));

    await tap(tester, find.text('Week graph'));
    verify(() => repository.observeWeeklyGoals(
          ownerId: StudySession.guestOwner,
          today: firstWeek,
        )).called(1);
    expect(find.text('Target: 10h 0m 0s'), findsOneWidget);

    await tap(tester, find.text('Month graph'));
    await tap(tester, find.text('Week graph'));
    verifyNever(() => repository.observeWeeklyGoals(
          ownerId: any(named: 'ownerId'),
          today: any(named: 'today'),
        ));

    await tap(tester, find.text('Calendar'));
    today = DateTime(2027, 1, 4);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    verifyNever(() => repository.observeWeeklyGoals(
          ownerId: any(named: 'ownerId'),
          today: any(named: 'today'),
        ));

    await tap(tester, find.text('Week graph'));
    verify(() => repository.observeWeeklyGoals(
          ownerId: StudySession.guestOwner,
          today: nextWeek,
        )).called(1);
    expect(find.text('Target: 10h 0m 0s'), findsOneWidget);
  });

  testWidgets('the new week inherits its goal and the prior week is read only',
      (tester) async {
    final earlierWeek = DateTime.utc(2026, 12, 28);
    query().thenAnswer((_) async => _history({earlierWeek: 23400}));
    when(() => repository.observeWeeklyGoals(
            today: any(named: 'today'), ownerId: StudySession.guestOwner))
        .thenAnswer((_) async => WeeklyStudyGoals({earlierWeek: 600}));
    today = DateTime(2027, 1, 3, 23, 59);
    await show(tester);
    await tester.pumpAndSettle();
    expect(find.text('Progress: 65%'), findsOneWidget);
    await tap(tester, find.text('Edit goal'));

    today = DateTime(2027, 1, 4);
    await tester.pump(const Duration(minutes: 1));
    await tester.enterText(find.byType(TextFormField), '300');
    await tap(tester, find.text('Save goal'));
    expect(find.textContaining('The week has changed'), findsOneWidget);
    expect(find.text('Progress: 0%'), findsOneWidget);
    verifyNever(() => repository.saveWeeklyGoal(
          ownerId: any(named: 'ownerId'),
          today: any(named: 'today'),
          minutes: any(named: 'minutes'),
        ));

    await tap(tester, find.byTooltip('Previous period'));
    expect(find.text('Progress: 65%'), findsOneWidget);
    expect(find.text('Edit goal'), findsNothing);

    when(() => repository.observeWeeklyGoals(
          today: any(named: 'today'),
          ownerId: StudySession.guestOwner,
        )).thenAnswer((_) async => WeeklyStudyGoals({
          DateTime.utc(2027, 1, 4): 600,
          earlierWeek: 600,
        }));
    today = DateTime(2027, 1, 3);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('The device date is before'), findsOneWidget);
    expect(find.text('Progress: 65%'), findsOneWidget);
    expect(find.text('Edit goal'), findsNothing);
  });

  testWidgets('switching owners hides the previous goal and its open editor',
      (tester) async {
    final guestGoals = Completer<WeeklyStudyGoals>();
    query().thenAnswer((_) async => _history());
    when(() => repository.observeWeeklyGoals(
        today: any(named: 'today'),
        ownerId: StudySession.guestOwner)).thenAnswer((_) => guestGoals.future);
    when(() => repository.observeWeeklyGoals(
            today: any(named: 'today'), ownerId: 'user:account'))
        .thenAnswer(
            (_) async => WeeklyStudyGoals({DateTime.utc(2026, 12, 28): 120}));
    await show(tester);
    await tester.pump();
    verify(() => repository.observeWeeklyGoals(
          ownerId: StudySession.guestOwner,
          today: DateTime.utc(2026, 12, 28),
        )).called(1);
    auth.changeUser('account');
    await tester.pumpAndSettle();
    expect(find.text('Target: 2h 0m 0s'), findsOneWidget);
    guestGoals.complete(WeeklyStudyGoals({DateTime.utc(2026, 12, 28): 600}));
    await tester.pumpAndSettle();
    expect(find.text('Target: 10h 0m 0s'), findsNothing);

    await tap(tester, find.text('Edit goal'));
    expect(find.byType(TextFormField), findsOneWidget);
    auth.changeUser('different-account');
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Your account changed'), findsOneWidget);
    await tap(tester, find.text('Close'));
    expect(find.text('No goal set'), findsOneWidget);
    expect(find.text('Target: 2h 0m 0s'), findsNothing);
  });

  testWidgets('a multi-week clock correction requires confirmation',
      (tester) async {
    final current = DateTime.utc(2026, 12, 28);
    final future = DateTime.utc(2030, 1, 7);
    final goals = {current: 600, future: 900};
    query().thenAnswer((_) async => _history());
    when(() => repository.observeWeeklyGoals(
          ownerId: StudySession.guestOwner,
          today: current,
        )).thenAnswer((_) async => WeeklyStudyGoals(goals));
    when(() => repository.correctWeeklyGoalDate(
          ownerId: StudySession.guestOwner,
          today: today,
          expectedLatestWeek: future,
        )).thenAnswer((_) async {
      goals.remove(future);
      return true;
    });

    await show(tester);
    await tester.pumpAndSettle();
    final correction = find.text('Use corrected date');
    await tap(tester, correction);
    await tap(tester, find.text('Close'));
    expect(find.text('Edit goal'), findsNothing);

    await tap(tester, correction);
    final confirm = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    await tap(tester, confirm);
    expect(find.text('Edit goal'), findsOneWidget);
    expect(find.text('Target: 10h 0m 0s'), findsOneWidget);
    expect(correction, findsNothing);
  });
}
