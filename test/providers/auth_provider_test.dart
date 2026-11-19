import 'dart:async';
// fake_async is provided by flutter_test.
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_peaks/config/app_config.dart';
import 'package:study_peaks/providers/auth_provider.dart';
import 'package:study_peaks/services/network_exception.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:google_sign_in/google_sign_in.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockFirebaseAuth mockFirebaseAuth;
  late MockGoogleSignIn mockGoogleSignIn;
  late AuthProvider provider;
  late StreamController<User?> authStateController;

  setUpAll(() {
    registerMocktailFallbacks();
  });

  setUp(() {
    mockFirebaseAuth = MockFirebaseAuth();
    mockGoogleSignIn = MockGoogleSignIn();
    authStateController = StreamController<User?>.broadcast();

    when(() => mockFirebaseAuth.authStateChanges())
        .thenAnswer((_) => authStateController.stream);

    when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {});

    provider = AuthProvider(
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
      test('current Firebase user is available before the first auth event',
          () {
        provider.dispose();
        final user = MockUser();
        when(() => user.uid).thenReturn('restored-account');
        when(() => mockFirebaseAuth.currentUser).thenReturn(user);
        provider = AuthProvider(
            auth: mockFirebaseAuth, googleSignIn: mockGoogleSignIn);
        expect(provider.isSignedIn, true);
        expect(provider.userId, 'restored-account');
      });

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
        when(() => mockGoogleSignIn.authenticate()).thenThrow(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        );

        final result = await provider.signInWithGoogle();

        expect(result, false);
        expect(provider.error, isNull);
        expect(provider.isLoading, false);
      });

      test('returns false and sets error on exception', () async {
        when(() => mockGoogleSignIn.authenticate())
            .thenThrow(Exception('Sign in failed'));

        final result = await provider.signInWithGoogle();

        expect(result, false);
        expect(provider.error, contains('Sign in failed'));
        expect(provider.isLoading, false);
      });

      test('sets isLoading during sign in attempt', () async {
        final completer = Completer<GoogleSignInAccount>();
        when(() => mockGoogleSignIn.authenticate())
            .thenAnswer((_) => completer.future);

        final future = provider.signInWithGoogle();

        // Should be loading while waiting
        expect(provider.isLoading, true);

        // Cancel the interactive authentication.
        completer.completeError(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        );
        await future;

        expect(provider.isLoading, false);
      });

      test('successful sign in returns true', () async {
        final mockAccount = MockGoogleSignInAccount();
        final mockCredential = MockUserCredential();

        when(() => mockGoogleSignIn.authenticate())
            .thenAnswer((_) async => mockAccount);
        when(() => mockAccount.authentication)
            .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
        when(() => mockFirebaseAuth.signInWithCredential(any()))
            .thenAnswer((_) async => mockCredential);

        final result = await provider.signInWithGoogle();

        final credential = verify(() => mockFirebaseAuth.signInWithCredential(
              captureAny(),
            )).captured.single as OAuthCredential;
        expect(credential.idToken, 'id-token');
        expect(credential.accessToken, isNull);
        expect(result, true);
        expect(provider.isLoading, false);
        expect(provider.error, isNull);
      });
    });

    group('7.x authentication', () {
      void stubSuccessfulAuthentication() {
        final account = MockGoogleSignInAccount();
        when(() => mockGoogleSignIn.authenticate())
            .thenAnswer((_) async => account);
        when(() => account.authentication)
            .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
        when(() => mockFirebaseAuth.signInWithCredential(any()))
            .thenAnswer((_) async => MockUserCredential());
      }

      test('reports Google configuration errors', () async {
        when(() => mockGoogleSignIn.authenticate()).thenThrow(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
            description: 'Invalid client configuration',
          ),
        );
        expect(await provider.signInWithGoogle(), false);
        expect(provider.error, contains('Invalid client configuration'));
        expect(provider.isLoading, false);
      });

      test('maps network errors to the localized error key', () async {
        stubSuccessfulAuthentication();
        when(() => mockFirebaseAuth.signInWithCredential(any()))
            .thenThrow(const NetworkException('Offline'));
        expect(await provider.signInWithGoogle(), false);
        expect(provider.error, NetworkErrorKey.networkError);
        expect(provider.isLoading, false);
      });

      test('times out Firebase credential exchange and clears loading', () {
        fakeAsync((async) {
          stubSuccessfulAuthentication();
          final exchange = Completer<UserCredential>();
          when(() => mockFirebaseAuth.signInWithCredential(any()))
              .thenAnswer((_) => exchange.future);
          bool? result;
          provider.signInWithGoogle().then((value) => result = value);
          async.flushMicrotasks();
          expect(provider.isLoading, true);
          async.elapse(
              AppConfig.signInTimeout - const Duration(milliseconds: 1));
          expect(result, isNull);
          expect(provider.isLoading, true);
          async.elapse(const Duration(milliseconds: 1));
          expect(result, false);
          expect(provider.error, NetworkErrorKey.networkError);
          expect(provider.isLoading, false);
        });
      });

      test('does not time out interactive authentication', () {
        fakeAsync((async) {
          final interaction = Completer<GoogleSignInAccount>();
          when(() => mockGoogleSignIn.authenticate())
              .thenAnswer((_) => interaction.future);
          bool? result;
          provider.signInWithGoogle().then((value) => result = value);
          async.flushMicrotasks();
          async.elapse(AppConfig.signInTimeout * 2);
          expect(result, isNull);
          expect(provider.isLoading, true);
          verifyNever(() => mockFirebaseAuth.signInWithCredential(any()));
          interaction.completeError(const GoogleSignInException(
            code: GoogleSignInExceptionCode.canceled,
          ));
          async.flushMicrotasks();
          expect(result, false);
          expect(provider.error, isNull);
          expect(provider.isLoading, false);
        });
      });

      test('initializes only once across two sign-ins', () async {
        stubSuccessfulAuthentication();
        expect(await provider.signInWithGoogle(), true);
        expect(await provider.signInWithGoogle(), true);
        verify(() => mockGoogleSignIn.initialize()).called(1);
      });

      test('retries initialization after a failed attempt', () async {
        stubSuccessfulAuthentication();
        var calls = 0;
        when(() => mockGoogleSignIn.initialize()).thenAnswer((_) async {
          calls++;
          if (calls == 1) throw Exception('init failed');
        });

        expect(await provider.signInWithGoogle(), false);
        expect(provider.error, isNotNull);
        expect(await provider.signInWithGoogle(), true);
        verify(() => mockGoogleSignIn.initialize()).called(2);
      });

      test('concurrent sign-ins await the same initialization', () async {
        stubSuccessfulAuthentication();
        final initialization = Completer<void>();
        when(() => mockGoogleSignIn.initialize())
            .thenAnswer((_) => initialization.future);
        final first = provider.signInWithGoogle();
        final second = provider.signInWithGoogle();
        verify(() => mockGoogleSignIn.initialize()).called(1);
        verifyNever(() => mockGoogleSignIn.authenticate());
        initialization.complete();
        expect(await first, true);
        expect(await second, true);
      });
    });

    group('getIdToken', () {
      test('returns null when signed out', () async {
        expect(await provider.getIdToken(), isNull);
      });

      test('retries network errors and preserves forceRefresh', () async {
        final user = MockUser();
        authStateController.add(user);
        await Future<void>.delayed(Duration.zero);
        fakeAsync((async) {
          var attempts = 0;
          when(() => user.getIdToken(true)).thenAnswer((_) async {
            if (++attempts == 1) throw const NetworkException('Offline');
            return 'refreshed-token';
          });
          String? token;
          provider
              .getIdToken(forceRefresh: true)
              .then((value) => token = value);
          async.flushMicrotasks();
          expect(attempts, 1);
          async.elapse(AppConfig.retryDelays.first);
          expect(token, 'refreshed-token');
          verify(() => user.getIdToken(true)).called(2);
        });
      });

      test('does not retry non-network errors', () async {
        final user = MockUser();
        when(() => user.getIdToken(false))
            .thenThrow(StateError('Invalid user'));
        authStateController.add(user);
        await Future<void>.delayed(Duration.zero);
        await expectLater(provider.getIdToken(), throwsStateError);
        verify(() => user.getIdToken(false)).called(1);
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

      for (final failsInitialization in [true, false]) {
        final googleStep = failsInitialization ? 'initialize' : 'signOut';
        test('still signs out Firebase when Google $googleStep fails',
            () async {
          when(() => mockFirebaseAuth.signOut()).thenAnswer((_) async {});
          if (failsInitialization) {
            when(() => mockGoogleSignIn.initialize())
                .thenAnswer((_) async => throw Exception('init failed'));
          } else {
            when(() => mockGoogleSignIn.signOut()).thenAnswer(
                (_) async => throw Exception('Google sign out failed'));
          }

          await provider.signOut();

          verify(() => mockFirebaseAuth.signOut()).called(1);
          expect(provider.isLoading, false);
          expect(provider.error, isNull);
        });
      }

      test('sets error when Firebase signOut fails', () async {
        when(() => mockGoogleSignIn.signOut()).thenAnswer((_) async {});
        when(() => mockFirebaseAuth.signOut())
            .thenThrow(Exception('Firebase sign out failed'));

        await provider.signOut();

        verify(() => mockFirebaseAuth.signOut()).called(1);
        expect(provider.error, contains('Firebase sign out failed'));
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
