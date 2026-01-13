import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../helpers/test_helpers.dart';

/// Testable AuthProvider that allows injection of mocked dependencies.
/// This class mirrors the behavior of AuthProvider but accepts mocked
/// FirebaseAuth and GoogleSignIn instances for testing.
class TestableAuthProvider {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  User? _user;
  bool _isLoading = false;
  String? _error;
  StreamSubscription<User?>? _authSubscription;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSignedIn => _user != null;
  String? get error => _error;
  String get displayName => _user?.displayName ?? 'Anonymous';
  String get email => _user?.email ?? '';
  String? get photoUrl => _user?.photoURL;
  String get userId => _user?.uid ?? '';

  final List<void Function()> _listeners = [];

  TestableAuthProvider({
    required FirebaseAuth auth,
    required GoogleSignIn googleSignIn,
  })  : _auth = auth,
        _googleSignIn = googleSignIn {
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      _user = user;
      _notifyListeners();
    });
  }

  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  Future<bool> signInWithGoogle() async {
    try {
      _isLoading = true;
      _error = null;
      _notifyListeners();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        _notifyListeners();
        return false; // User cancelled
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);

      _isLoading = false;
      _notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      _isLoading = true;
      _notifyListeners();

      await _googleSignIn.signOut();
      await _auth.signOut();

      _isLoading = false;
      _notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notifyListeners();
    }
  }

  Future<void> updateUserName(String name) async {
    try {
      _isLoading = true;
      _notifyListeners();

      await _user?.updateDisplayName(name);
      await _user?.reload();
      _user = _auth.currentUser;

      _isLoading = false;
      _notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notifyListeners();
      rethrow;
    }
  }

  Future<String?> getIdToken() async {
    return await _user?.getIdToken();
  }

  void dispose() {
    _authSubscription?.cancel();
  }
}

/// Fake AuthCredential for mocktail fallback registration
class FakeAuthCredential extends Fake implements AuthCredential {}

void main() {
  late MockFirebaseAuth mockFirebaseAuth;
  late MockGoogleSignIn mockGoogleSignIn;
  late TestableAuthProvider provider;
  late StreamController<User?> authStateController;

  setUpAll(() {
    registerFallbackValue(FakeAuthCredential());
  });

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    mockGoogleSignIn = MockGoogleSignIn();
    authStateController = StreamController<User?>.broadcast();

    when(() => mockFirebaseAuth.authStateChanges())
        .thenAnswer((_) => authStateController.stream);

    provider = TestableAuthProvider(
      auth: mockFirebaseAuth,
      googleSignIn: mockGoogleSignIn,
    );
  });

  tearDown(() {
    provider.dispose();
    authStateController.close();
  });

  group('AuthProvider', () {
    group('Initial State', () {
      test('isSignedIn is false initially', () {
        expect(provider.isSignedIn, false);
      });

      test('displayName is Anonymous when not signed in', () {
        expect(provider.displayName, 'Anonymous');
      });

      test('email is empty when not signed in', () {
        expect(provider.email, '');
      });

      test('userId is empty when not signed in', () {
        expect(provider.userId, '');
      });

      test('isLoading is false initially', () {
        expect(provider.isLoading, false);
      });

      test('error is null initially', () {
        expect(provider.error, isNull);
      });
    });

    group('signInWithGoogle', () {
      test('returns false when user cancels sign in', () async {
        when(() => mockGoogleSignIn.signIn()).thenAnswer((_) async => null);

        final result = await provider.signInWithGoogle();

        expect(result, false);
        expect(provider.isLoading, false);
      });

      test('returns false and sets error on exception', () async {
        when(() => mockGoogleSignIn.signIn())
            .thenThrow(Exception('Sign in failed'));

        final result = await provider.signInWithGoogle();

        expect(result, false);
        expect(provider.error, contains('Sign in failed'));
        expect(provider.isLoading, false);
      });

      test('sets isLoading during sign in attempt', () async {
        final completer = Completer<GoogleSignInAccount?>();
        when(() => mockGoogleSignIn.signIn())
            .thenAnswer((_) => completer.future);

        final future = provider.signInWithGoogle();

        // Should be loading while waiting
        expect(provider.isLoading, true);

        // Complete with null (cancelled)
        completer.complete(null);
        await future;

        expect(provider.isLoading, false);
      });

      test('successful sign in returns true', () async {
        final mockAccount = MockGoogleSignInAccount();
        final mockAuthentication = MockGoogleSignInAuthentication();
        final mockCredential = MockUserCredential();

        when(() => mockGoogleSignIn.signIn())
            .thenAnswer((_) async => mockAccount);
        when(() => mockAccount.authentication)
            .thenAnswer((_) async => mockAuthentication);
        when(() => mockAuthentication.accessToken).thenReturn('access-token');
        when(() => mockAuthentication.idToken).thenReturn('id-token');
        when(() => mockFirebaseAuth.signInWithCredential(any()))
            .thenAnswer((_) async => mockCredential);

        final result = await provider.signInWithGoogle();

        expect(result, true);
        expect(provider.isLoading, false);
        expect(provider.error, isNull);
      });
    });

    group('signOut', () {
      test('calls googleSignIn.signOut and auth.signOut', () async {
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
        when(() => mockFirebaseAuth.signOut()).thenAnswer((_) async {});

        await provider.signOut();

        verify(() => mockGoogleSignIn.signOut()).called(1);
        verify(() => mockFirebaseAuth.signOut()).called(1);
        expect(provider.isLoading, false);
      });

      test('sets error on exception', () async {
        when(() => mockGoogleSignIn.signOut())
            .thenThrow(Exception('Sign out failed'));

        await provider.signOut();

        expect(provider.error, contains('Sign out failed'));
        expect(provider.isLoading, false);
      });
    });

    group('authStateChanges', () {
      test('updates user when auth state changes', () async {
        final mockUser = MockUser();
        when(() => mockUser.displayName).thenReturn('Test User');
        when(() => mockUser.email).thenReturn('test@example.com');
        when(() => mockUser.uid).thenReturn('user-123');

        // Emit user through auth state stream
        authStateController.add(mockUser);
        await Future.delayed(Duration.zero);

        expect(provider.isSignedIn, true);
        expect(provider.displayName, 'Test User');
        expect(provider.email, 'test@example.com');
        expect(provider.userId, 'user-123');
      });

      test('clears user when auth state emits null', () async {
        final mockUser = MockUser();
        when(() => mockUser.displayName).thenReturn('Test User');

        // First sign in
        authStateController.add(mockUser);
        await Future.delayed(Duration.zero);
        expect(provider.isSignedIn, true);

        // Then sign out
        authStateController.add(null);
        await Future.delayed(Duration.zero);
        expect(provider.isSignedIn, false);
        expect(provider.displayName, 'Anonymous');
      });
    });
  });
}
