import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'l10n/app_localizations.dart';
import 'providers/auth_provider.dart';
import 'providers/room_provider.dart';
import 'providers/session_provider.dart';
import 'providers/timer_provider.dart';
import 'providers/user_settings_provider.dart';
import 'repositories/mock_data_repository.dart';
import 'screens/room_list_screen.dart';
import 'services/notification_service.dart';

/// Build-time constant for mock data usage.
/// Set to false in production builds using: --dart-define=USE_MOCK_DATA=false
const bool kUseMockData = bool.fromEnvironment('USE_MOCK_DATA', defaultValue: true);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialize notification service for foreground notifications
  await NotificationService().initialize();
  
  // Initialize user settings
  final userSettingsProvider = UserSettingsProvider();
  await userSettingsProvider.init();
  
  runApp(StudyPeaksApp(userSettingsProvider: userSettingsProvider));
}

class StudyPeaksApp extends StatelessWidget {
  final UserSettingsProvider userSettingsProvider;
  
  const StudyPeaksApp({super.key, required this.userSettingsProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: userSettingsProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TimerProvider()),
        ChangeNotifierProvider(
          create: (_) => RoomProvider(
            mockDataRepository: kUseMockData ? DevMockDataRepository() : null,
          ),
        ),
        ChangeNotifierProxyProvider2<AuthProvider, UserSettingsProvider, SessionProvider>(
          create: (_) => SessionProvider(),
          update: (_, auth, userSettings, session) {
            session?.setAuthProvider(auth);
            session?.setUserSettingsProvider(userSettings);
            return session ?? SessionProvider()
              ..setAuthProvider(auth)
              ..setUserSettingsProvider(userSettings);
          },
        ),
      ],
      child: MaterialApp(
        title: 'Global Study Peaks',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: context.watch<UserSettingsProvider>().themeMode,
        home: const RoomListScreen(),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A237E),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1A237E),
        elevation: 0,
        centerTitle: true,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF5C6BC0),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF121212),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
