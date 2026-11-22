import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Global Study Peaks'**
  String get appTitle;

  /// No description provided for @chooseYourPeak.
  ///
  /// In en, this message translates to:
  /// **'Choose Your Peak'**
  String get chooseYourPeak;

  /// No description provided for @joinRoomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join a virtual study room and start focusing'**
  String get joinRoomSubtitle;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @signInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to save your study progress and sync across devices.'**
  String get signInPrompt;

  /// No description provided for @signedInSuccess.
  ///
  /// In en, this message translates to:
  /// **'Signed in successfully!'**
  String get signedInSuccess;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @seat.
  ///
  /// In en, this message translates to:
  /// **'Seat'**
  String get seat;

  /// No description provided for @occupancy.
  ///
  /// In en, this message translates to:
  /// **'{current}/{total}'**
  String occupancy(int current, int total);

  /// No description provided for @timer.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get timer;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @normalMode.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normalMode;

  /// No description provided for @pomodoroMode.
  ///
  /// In en, this message translates to:
  /// **'Pomodoro'**
  String get pomodoroMode;

  /// No description provided for @focusPhase.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get focusPhase;

  /// No description provided for @breakPhase.
  ///
  /// In en, this message translates to:
  /// **'Break'**
  String get breakPhase;

  /// No description provided for @sitDown.
  ///
  /// In en, this message translates to:
  /// **'Sit Down'**
  String get sitDown;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @leaveSeat.
  ///
  /// In en, this message translates to:
  /// **'Leave Seat'**
  String get leaveSeat;

  /// No description provided for @leaveSeatConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave your seat?'**
  String get leaveSeatConfirmation;

  /// No description provided for @leaveConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not confirm that your seat was released. Check your internet connection.'**
  String get leaveConnectionFailed;

  /// No description provided for @leaveRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not confirm that your seat was released.'**
  String get leaveRequestFailed;

  /// No description provided for @leftSeat.
  ///
  /// In en, this message translates to:
  /// **'You have left your seat.'**
  String get leftSeat;

  /// No description provided for @sessionSeatReleased.
  ///
  /// In en, this message translates to:
  /// **'Your seat was released because you sat down elsewhere or the session expired.'**
  String get sessionSeatReleased;

  /// No description provided for @leaveSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Study time recorded'**
  String get leaveSummaryTitle;

  /// No description provided for @leaveSummarySession.
  ///
  /// In en, this message translates to:
  /// **'This session'**
  String get leaveSummarySession;

  /// No description provided for @leaveRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry leaving'**
  String get leaveRetry;

  /// No description provided for @leaveSummaryAllocation.
  ///
  /// In en, this message translates to:
  /// **'From this session, {today} counts toward today and {week} toward this week.'**
  String leaveSummaryAllocation(String today, String week);

  /// No description provided for @leaveSummaryTotalsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not load today’s and this week’s totals.'**
  String get leaveSummaryTotalsUnavailable;

  /// No description provided for @anonymous.
  ///
  /// In en, this message translates to:
  /// **'Anonymous User'**
  String get anonymous;

  /// No description provided for @useGoogleAvatar.
  ///
  /// In en, this message translates to:
  /// **'Use Google avatar'**
  String get useGoogleAvatar;

  /// No description provided for @useAutoGeneratedAvatar.
  ///
  /// In en, this message translates to:
  /// **'Use auto-generated avatar'**
  String get useAutoGeneratedAvatar;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect to the internet. Please check your connection.'**
  String get networkError;

  /// Button to retry a failed request
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Generic error message when the room list cannot be loaded
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load rooms.'**
  String get loadRoomsFailed;

  /// No description provided for @connectionRestored.
  ///
  /// In en, this message translates to:
  /// **'Connection restored'**
  String get connectionRestored;

  /// No description provided for @seatTaken.
  ///
  /// In en, this message translates to:
  /// **'This seat was just taken. Please select another.'**
  String get seatTaken;

  /// No description provided for @sessionRestoredFromSeatMap.
  ///
  /// In en, this message translates to:
  /// **'Session restored from seat map'**
  String get sessionRestoredFromSeatMap;

  /// No description provided for @notificationStudyingAt.
  ///
  /// In en, this message translates to:
  /// **'Studying at {roomName}'**
  String notificationStudyingAt(String roomName);

  /// No description provided for @notificationSessionStarted.
  ///
  /// In en, this message translates to:
  /// **'Session started - 0m'**
  String get notificationSessionStarted;

  /// No description provided for @notificationStudying.
  ///
  /// In en, this message translates to:
  /// **'Studying - {duration}'**
  String notificationStudying(String duration);

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @notificationFocusRemaining.
  ///
  /// In en, this message translates to:
  /// **'Focus: {duration} remaining'**
  String notificationFocusRemaining(String duration);

  /// No description provided for @notificationBreakRemaining.
  ///
  /// In en, this message translates to:
  /// **'Break: {duration} remaining'**
  String notificationBreakRemaining(String duration);

  /// No description provided for @notificationFocusFinished.
  ///
  /// In en, this message translates to:
  /// **'Focus Finished!'**
  String get notificationFocusFinished;

  /// No description provided for @notificationBreakFinished.
  ///
  /// In en, this message translates to:
  /// **'Break Finished!'**
  String get notificationBreakFinished;

  /// No description provided for @notificationTimeForBreak.
  ///
  /// In en, this message translates to:
  /// **'Time for a break.'**
  String get notificationTimeForBreak;

  /// No description provided for @notificationTimeToFocus.
  ///
  /// In en, this message translates to:
  /// **'Time to focus.'**
  String get notificationTimeToFocus;

  /// No description provided for @lockScreenDuringFocus.
  ///
  /// In en, this message translates to:
  /// **'Lock screen during focus'**
  String get lockScreenDuringFocus;

  /// No description provided for @lockTaskDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Start Screen Pinning'**
  String get lockTaskDialogTitle;

  /// No description provided for @lockTaskDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Screen pinning keeps this app in view while you focus. Android will ask for confirmation and show how to unpin.'**
  String get lockTaskDialogBody;

  /// No description provided for @lockTaskDialogPinAndStart.
  ///
  /// In en, this message translates to:
  /// **'Pin & Start'**
  String get lockTaskDialogPinAndStart;

  /// No description provided for @lockTaskDialogStartWithoutLock.
  ///
  /// In en, this message translates to:
  /// **'Start without Pinning'**
  String get lockTaskDialogStartWithoutLock;

  /// No description provided for @lockTaskDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get lockTaskDialogCancel;

  /// No description provided for @lockTaskUnpinHint.
  ///
  /// In en, this message translates to:
  /// **'To unpin, follow the Android instructions.'**
  String get lockTaskUnpinHint;

  /// No description provided for @lockTaskExitedMessage.
  ///
  /// In en, this message translates to:
  /// **'Screen pinning was released'**
  String get lockTaskExitedMessage;

  /// No description provided for @studyHistory.
  ///
  /// In en, this message translates to:
  /// **'Study History'**
  String get studyHistory;

  /// No description provided for @historyToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get historyToday;

  /// No description provided for @historyThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get historyThisWeek;

  /// No description provided for @historyWeek.
  ///
  /// In en, this message translates to:
  /// **'Week graph'**
  String get historyWeek;

  /// No description provided for @historyMonth.
  ///
  /// In en, this message translates to:
  /// **'Month graph'**
  String get historyMonth;

  /// No description provided for @historyCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get historyCalendar;

  /// No description provided for @historyStudyDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 study day} other{{count} study days}}'**
  String historyStudyDays(int count);

  /// No description provided for @historyCalendarLegend.
  ///
  /// In en, this message translates to:
  /// **'Daily study time'**
  String get historyCalendarLegend;

  /// No description provided for @historyCalendarNoStudy.
  ///
  /// In en, this message translates to:
  /// **'0 min'**
  String get historyCalendarNoStudy;

  /// No description provided for @historyCalendarUnderThirty.
  ///
  /// In en, this message translates to:
  /// **'<30 min'**
  String get historyCalendarUnderThirty;

  /// No description provided for @historyCalendarUnderSixty.
  ///
  /// In en, this message translates to:
  /// **'30–59 min'**
  String get historyCalendarUnderSixty;

  /// No description provided for @historyCalendarSixtyOrMore.
  ///
  /// In en, this message translates to:
  /// **'60+ min'**
  String get historyCalendarSixtyOrMore;

  /// No description provided for @historyCalendarFuture.
  ///
  /// In en, this message translates to:
  /// **'Future date'**
  String get historyCalendarFuture;

  /// No description provided for @historyCalendarToday.
  ///
  /// In en, this message translates to:
  /// **'{date} (today)'**
  String historyCalendarToday(String date);

  /// No description provided for @historyCalendarDayLabel.
  ///
  /// In en, this message translates to:
  /// **'{date}, {duration}'**
  String historyCalendarDayLabel(String date, String duration);

  /// No description provided for @historyDayTotal.
  ///
  /// In en, this message translates to:
  /// **'Total for this day: {duration}'**
  String historyDayTotal(String duration);

  /// No description provided for @historyDaySessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get historyDaySessions;

  /// No description provided for @historyDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No study sessions'**
  String get historyDayEmpty;

  /// No description provided for @historySessionStart.
  ///
  /// In en, this message translates to:
  /// **'Started {date}'**
  String historySessionStart(String date);

  /// No description provided for @historyPreviousPeriod.
  ///
  /// In en, this message translates to:
  /// **'Previous period'**
  String get historyPreviousPeriod;

  /// No description provided for @historyNextPeriod.
  ///
  /// In en, this message translates to:
  /// **'Next period'**
  String get historyNextPeriod;

  /// No description provided for @historyPreviousDay.
  ///
  /// In en, this message translates to:
  /// **'Previous day'**
  String get historyPreviousDay;

  /// No description provided for @historyNextDay.
  ///
  /// In en, this message translates to:
  /// **'Next day'**
  String get historyNextDay;

  /// No description provided for @historyPeriodEmpty.
  ///
  /// In en, this message translates to:
  /// **'No study time in this period'**
  String get historyPeriodEmpty;

  /// No description provided for @historyDateRange.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String historyDateRange(String start, String end);

  /// No description provided for @historyDurationHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m {seconds}s'**
  String historyDurationHours(int hours, int minutes, int seconds);

  /// No description provided for @historyDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String historyDurationMinutes(int minutes, int seconds);

  /// No description provided for @historyHours.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String historyHours(int hours);

  /// No description provided for @historyMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String historyMinutes(int minutes);

  /// No description provided for @historySeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String historySeconds(int seconds);

  /// No description provided for @historyTotal.
  ///
  /// In en, this message translates to:
  /// **'Total Study Time'**
  String get historyTotal;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No study records yet'**
  String get historyEmpty;

  /// No description provided for @historyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load history'**
  String get historyLoadFailed;

  /// No description provided for @historySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save your study record. Please retry leaving your seat.'**
  String get historySaveFailed;

  /// No description provided for @historyOtherOwnerActive.
  ///
  /// In en, this message translates to:
  /// **'A study session for another user remains on this device. Switch back to that user and leave the seat.'**
  String get historyOtherOwnerActive;

  /// No description provided for @historySignInNotice.
  ///
  /// In en, this message translates to:
  /// **'Sign in with the same Google account to sync completed study records across your devices. Guest records stay on this device.'**
  String get historySignInNotice;

  /// No description provided for @historySyncAction.
  ///
  /// In en, this message translates to:
  /// **'Sync study history'**
  String get historySyncAction;

  /// No description provided for @historySyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing study history…'**
  String get historySyncing;

  /// No description provided for @historySynced.
  ///
  /// In en, this message translates to:
  /// **'Study history synced'**
  String get historySynced;

  /// No description provided for @historySyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sync study history. Tap the sync button to try again.'**
  String get historySyncFailed;

  /// No description provided for @weeklyGoal.
  ///
  /// In en, this message translates to:
  /// **'Weekly study goal'**
  String get weeklyGoal;

  /// No description provided for @weeklyGoalNotSet.
  ///
  /// In en, this message translates to:
  /// **'No goal set'**
  String get weeklyGoalNotSet;

  /// No description provided for @weeklyGoalSet.
  ///
  /// In en, this message translates to:
  /// **'Set goal'**
  String get weeklyGoalSet;

  /// No description provided for @weeklyGoalEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get weeklyGoalEdit;

  /// No description provided for @weeklyGoalClear.
  ///
  /// In en, this message translates to:
  /// **'Clear goal'**
  String get weeklyGoalClear;

  /// No description provided for @weeklyGoalSave.
  ///
  /// In en, this message translates to:
  /// **'Save goal'**
  String get weeklyGoalSave;

  /// No description provided for @weeklyGoalMinutes.
  ///
  /// In en, this message translates to:
  /// **'Goal (minutes per week)'**
  String get weeklyGoalMinutes;

  /// No description provided for @weeklyGoalInputHelp.
  ///
  /// In en, this message translates to:
  /// **'{min}–{max} minutes, in {step}-minute steps'**
  String weeklyGoalInputHelp(int min, int max, int step);

  /// No description provided for @weeklyGoalInvalidMinutes.
  ///
  /// In en, this message translates to:
  /// **'Enter minutes within the range and step shown.'**
  String get weeklyGoalInvalidMinutes;

  /// No description provided for @weeklyGoalTarget.
  ///
  /// In en, this message translates to:
  /// **'Target: {duration}'**
  String weeklyGoalTarget(String duration);

  /// No description provided for @weeklyGoalActual.
  ///
  /// In en, this message translates to:
  /// **'Studied: {duration}'**
  String weeklyGoalActual(String duration);

  /// No description provided for @weeklyGoalRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining: {duration}'**
  String weeklyGoalRemaining(String duration);

  /// No description provided for @weeklyGoalAchievement.
  ///
  /// In en, this message translates to:
  /// **'Progress: {percent}'**
  String weeklyGoalAchievement(String percent);

  /// No description provided for @weeklyGoalLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load weekly goals.'**
  String get weeklyGoalLoadFailed;

  /// No description provided for @weeklyGoalSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the weekly goal. Try again.'**
  String get weeklyGoalSaveFailed;

  /// No description provided for @weeklyGoalOwnerChanged.
  ///
  /// In en, this message translates to:
  /// **'Your account changed. Open the goal editor again.'**
  String get weeklyGoalOwnerChanged;

  /// No description provided for @weeklyGoalWeekChanged.
  ///
  /// In en, this message translates to:
  /// **'The week has changed. Open this week’s goal to edit it.'**
  String get weeklyGoalWeekChanged;

  /// No description provided for @weeklyGoalDateEarlier.
  ///
  /// In en, this message translates to:
  /// **'The device date is before the latest saved week. Editing is available from that week onward.'**
  String get weeklyGoalDateEarlier;

  /// No description provided for @weeklyGoalCorrectDate.
  ///
  /// In en, this message translates to:
  /// **'Use corrected date'**
  String get weeklyGoalCorrectDate;

  /// No description provided for @weeklyGoalCorrectDateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm that your device date is correct. This clears goal settings for later weeks on this device.'**
  String get weeklyGoalCorrectDateConfirm;

  /// No description provided for @profileSettings.
  ///
  /// In en, this message translates to:
  /// **'Profile Settings'**
  String get profileSettings;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayName;

  /// No description provided for @displayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter your display name'**
  String get displayNameHint;

  /// No description provided for @saveDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Save display name'**
  String get saveDisplayName;

  /// No description provided for @displayNameSaved.
  ///
  /// In en, this message translates to:
  /// **'Name saved!'**
  String get displayNameSaved;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @regenerateIcon.
  ///
  /// In en, this message translates to:
  /// **'Regenerate Icon'**
  String get regenerateIcon;

  /// No description provided for @iconRegenerated.
  ///
  /// In en, this message translates to:
  /// **'Icon regenerated!'**
  String get iconRegenerated;

  /// No description provided for @signedInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Signed in with Google'**
  String get signedInWithGoogle;

  /// No description provided for @signedOutSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Signed out successfully'**
  String get signedOutSuccessfully;

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get signingIn;

  /// No description provided for @joinRoom.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinRoom;

  /// No description provided for @roomOccupancy.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total} studying'**
  String roomOccupancy(int current, int total);

  /// No description provided for @occupiedPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% occupied'**
  String occupiedPercent(int percent);

  /// No description provided for @roomInfo.
  ///
  /// In en, this message translates to:
  /// **'Room information'**
  String get roomInfo;

  /// No description provided for @roomCapacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity: {count} seats'**
  String roomCapacity(int count);

  /// No description provided for @roomCurrentOccupancy.
  ///
  /// In en, this message translates to:
  /// **'Currently: {count} studying'**
  String roomCurrentOccupancy(int count);

  /// No description provided for @studyingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} studying'**
  String studyingCount(int count);

  /// No description provided for @noSeatsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No seats available'**
  String get noSeatsAvailable;

  /// No description provided for @loadSeatsFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load seats.'**
  String get loadSeatsFailed;

  /// No description provided for @seatCountUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Seat count unavailable'**
  String get seatCountUnavailable;

  /// No description provided for @seatTitle.
  ///
  /// In en, this message translates to:
  /// **'Seat {number}'**
  String seatTitle(int number);

  /// No description provided for @emptySeatSemantics.
  ///
  /// In en, this message translates to:
  /// **'Seat {number}, empty. Tap to sit down.'**
  String emptySeatSemantics(int number);

  /// No description provided for @occupiedSeatSemantics.
  ///
  /// In en, this message translates to:
  /// **'Seat {number}, {name}, {country}, {duration}'**
  String occupiedSeatSemantics(
      int number, String name, String country, String duration);

  /// No description provided for @ownSeatSemantics.
  ///
  /// In en, this message translates to:
  /// **'Seat {number}, your seat, {duration}'**
  String ownSeatSemantics(int number, String duration);

  /// No description provided for @sitQuestion.
  ///
  /// In en, this message translates to:
  /// **'Do you want to take this seat and start studying?'**
  String get sitQuestion;

  /// No description provided for @sitSuccess.
  ///
  /// In en, this message translates to:
  /// **'You are now seated at seat {number}!'**
  String sitSuccess(int number);

  /// No description provided for @sitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not take this seat.'**
  String get sitFailed;

  /// No description provided for @alreadySeated.
  ///
  /// In en, this message translates to:
  /// **'You are already seated!'**
  String get alreadySeated;

  /// No description provided for @leaveSeatInRoom.
  ///
  /// In en, this message translates to:
  /// **'Leave seat {number} in {roomName}?'**
  String leaveSeatInRoom(int number, String roomName);

  /// No description provided for @leaveRoom.
  ///
  /// In en, this message translates to:
  /// **'Leave your seat in {roomName}?'**
  String leaveRoom(String roomName);

  /// No description provided for @expandTimer.
  ///
  /// In en, this message translates to:
  /// **'Expand timer'**
  String get expandTimer;

  /// No description provided for @collapseTimer.
  ///
  /// In en, this message translates to:
  /// **'Collapse timer'**
  String get collapseTimer;

  /// No description provided for @focusTime.
  ///
  /// In en, this message translates to:
  /// **'Focus Time'**
  String get focusTime;

  /// No description provided for @breakTime.
  ///
  /// In en, this message translates to:
  /// **'Break Time'**
  String get breakTime;

  /// No description provided for @cyclesCompleted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 cycle completed} other{{count} cycles completed}}'**
  String cyclesCompleted(int count);

  /// No description provided for @seatedFor.
  ///
  /// In en, this message translates to:
  /// **'Seated for {duration}'**
  String seatedFor(String duration);

  /// No description provided for @notificationPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused · {duration}'**
  String notificationPaused(String duration);

  /// No description provided for @notificationFocusReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to focus · {duration}'**
  String notificationFocusReady(String duration);

  /// No description provided for @notificationBreakReady.
  ///
  /// In en, this message translates to:
  /// **'Ready for a break · {duration}'**
  String notificationBreakReady(String duration);

  /// No description provided for @countryName.
  ///
  /// In en, this message translates to:
  /// **'{code, select, JP{Japan} US{United States} GB{United Kingdom} CN{China} KR{South Korea} DE{Germany} FR{France} IT{Italy} ES{Spain} BR{Brazil} IN{India} AU{Australia} CA{Canada} MX{Mexico} RU{Russia} TW{Taiwan} SG{Singapore} TH{Thailand} VN{Vietnam} PH{Philippines} other{{code}}}'**
  String countryName(String code);

  /// No description provided for @notificationSessionAt.
  ///
  /// In en, this message translates to:
  /// **'Study session at {roomName}'**
  String notificationSessionAt(String roomName);

  /// No description provided for @notificationTimerReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to start'**
  String get notificationTimerReady;

  /// No description provided for @studyBgm.
  ///
  /// In en, this message translates to:
  /// **'Background audio'**
  String get studyBgm;

  /// No description provided for @studyBgmPlay.
  ///
  /// In en, this message translates to:
  /// **'Play background audio'**
  String get studyBgmPlay;

  /// No description provided for @studyBgmDuringTimer.
  ///
  /// In en, this message translates to:
  /// **'Plays while the study timer is running.'**
  String get studyBgmDuringTimer;

  /// No description provided for @studyBgmTrack.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get studyBgmTrack;

  /// No description provided for @studyBgmVolume.
  ///
  /// In en, this message translates to:
  /// **'BGM volume'**
  String get studyBgmVolume;

  /// No description provided for @studyBgmInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Audio was interrupted. Turn it on to resume.'**
  String get studyBgmInterrupted;

  /// No description provided for @studyBgmFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not play audio. Try turning it on again.'**
  String get studyBgmFailed;

  /// No description provided for @studyBgmRain.
  ///
  /// In en, this message translates to:
  /// **'Nature · Rain'**
  String get studyBgmRain;

  /// No description provided for @studyBgmWaves.
  ///
  /// In en, this message translates to:
  /// **'Nature · Waves'**
  String get studyBgmWaves;

  /// No description provided for @studyBgmMusicBox.
  ///
  /// In en, this message translates to:
  /// **'Music box'**
  String get studyBgmMusicBox;

  /// No description provided for @studyBgmDreamy.
  ///
  /// In en, this message translates to:
  /// **'Dreamy ambient'**
  String get studyBgmDreamy;

  /// No description provided for @studyBgmPiano.
  ///
  /// In en, this message translates to:
  /// **'Piano'**
  String get studyBgmPiano;

  /// No description provided for @studyBgmOrchestra.
  ///
  /// In en, this message translates to:
  /// **'Orchestral strings'**
  String get studyBgmOrchestra;

  /// No description provided for @studyBgmLoFi.
  ///
  /// In en, this message translates to:
  /// **'Lo-fi'**
  String get studyBgmLoFi;

  /// No description provided for @studyBgmJazz.
  ///
  /// In en, this message translates to:
  /// **'Jazz'**
  String get studyBgmJazz;

  /// No description provided for @studyBgmBrownNoise.
  ///
  /// In en, this message translates to:
  /// **'Brown noise'**
  String get studyBgmBrownNoise;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
